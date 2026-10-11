// ============================================================
// dma.v —— 6 通道 DMA 控制器（基本功能版，单拍传输）
//
// 对应赛题"6 通道独立 DMA，支持存储器↔FIR / 存储器↔存储器"。
//
// 结构：
//   - AXI-Lite 从口：CPU 通过它配置每个通道的 源地址/目的地址/长度/控制。
//   - AXI4 主口：DMA 自己发起的读/写（单拍，AW_LEN=0/AR_LEN=0）。
//   - irq 输出：任一通道传完拉高。
//
// 每个通道的寄存器（字节地址 = 0x10 * N + 偏移，N=0..5）：
//   +0x00  SRC   源地址（字节）
//   +0x04  DST   目的地址（字节）
//   +0x08  LEN   传输字数（32bit 字个数）
//   +0x0C  CTRL  [0]START=1 启动  [1]SRC_INC 源地址自增
//                [2]DST_INC 目的地址自增   [31]DONE 完成标志（读，写1清）
//
// 传输过程（一个通道一次）：
//   读 SRC 的一个字 -> 写 DST 的一个字 -> 地址按 INC 位自增 -> LEN 减 1，
//   直到 LEN==0 置 DONE + 拉 irq。6 个通道按编号轮询（先到先做）。
// ============================================================
`timescale 1ns/1ps

module dma #(
    parameter ADDR_W = 32,
    parameter DATA_W = 32,
    parameter NCH    = 6
)(
    input  wire                 clk,
    input  wire                 rst_n,

    // ============ AXI-Lite 从口（CPU 配置）============
    input  wire [ADDR_W-1:0]    awaddr,
    input  wire                 awvalid,
    output reg                  awready,
    input  wire [DATA_W-1:0]    wdata,
    input  wire [DATA_W/8-1:0]  wstrb,
    input  wire                 wvalid,
    output reg                  wready,
    output reg  [1:0]           bresp,
    output reg                  bvalid,
    input  wire                 bready,
    input  wire [ADDR_W-1:0]    araddr,
    input  wire                 arvalid,
    output reg                  arready,
    output reg  [DATA_W-1:0]    rdata,
    output reg  [1:0]           rresp,
    output reg                  rvalid,
    input  wire                 rready,

    // ============ AXI4 主口（搬数据，单拍）============
    output reg                  AW_VALID,
    input  wire                 AW_READY,
    output reg  [2:0]           AW_SIZE,
    output reg  [1:0]           AW_BURST,
    output reg  [7:0]           AW_LEN,
    output reg  [ADDR_W-1:0]    AW_ADDR,
    output reg                  W_VALID,
    input  wire                 W_READY,
    output reg                  W_LAST,
    output reg  [DATA_W-1:0]    W_DATA,
    input  wire                 B_VALID,
    output reg                  B_READY,
    input  wire  [1:0]          B_RESP,
    output reg                  AR_VALID,
    input  wire                 AR_READY,
    output reg  [2:0]           AR_SIZE,
    output reg  [1:0]           AR_BURST,
    output reg  [7:0]           AR_LEN,
    output reg  [ADDR_W-1:0]    AR_ADDR,
    input  wire                 R_VALID,
    output reg                  R_READY,
    input  wire                 R_LAST,
    input  wire  [DATA_W-1:0]   R_DATA,
    input  wire  [1:0]          R_RESP,

    // ============ 中断 ============
    output reg                  irq
);

    localparam [1:0] SEL_SRC = 2'd0;
    localparam [1:0] SEL_DST = 2'd1;
    localparam [1:0] SEL_LEN = 2'd2;
    localparam [1:0] SEL_CTRL = 2'd3;

    // ============================================================
    // 1. 通道寄存器
    // ============================================================
    reg [ADDR_W-1:0]  src [0:NCH-1];
    reg [ADDR_W-1:0]  dst [0:NCH-1];
    reg [15:0]        len [0:NCH-1];
    reg               start [0:NCH-1];
    reg               src_inc [0:NCH-1];
    reg               dst_inc [0:NCH-1];
    reg               done  [0:NCH-1];

    // ============================================================
    // 2. AXI-Lite 从口：配置寄存器
    // ============================================================
    reg [ADDR_W-1:0] awaddr_r;
    reg [DATA_W-1:0] wdata_r;
    reg              aw_stored, w_stored;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            awaddr_r <= 0; aw_stored <= 0; awready <= 0;
            wdata_r  <= 0; w_stored  <= 0; wready  <= 0;
            bresp <= 0; bvalid <= 0;
        end else begin
            awready <= !aw_stored && !bvalid;
            wready  <= !w_stored  && !bvalid;

            if (awvalid && awready) begin awaddr_r <= awaddr; aw_stored <= 1; end
            if (wvalid && wready)   begin wdata_r  <= wdata;  w_stored  <= 1; end

            if (aw_stored && w_stored && !bvalid) begin
                // 译码通道号（0x10 一个通道）与寄存器
                if (awaddr_r < NCH*16) begin
                    reg [3:0] ch;
                    ch = awaddr_r[7:4];                 // 通道号（0x10 对齐）
                    case (awaddr_r[3:2])
                        SEL_SRC:  src[ch]  <= wdata_r;
                        SEL_DST:  dst[ch]  <= wdata_r;
                        SEL_LEN:  len[ch]  <= wdata_r[15:0];
                        SEL_CTRL: begin
                            start[ch]   <= wdata_r[0];
                            src_inc[ch] <= wdata_r[1];
                            dst_inc[ch] <= wdata_r[2];
                            if (wdata_r[31]) done[ch] <= 1'b0;  // 写1清DONE
                        end
                    endcase
                end
                bresp <= 2'b00; bvalid <= 1;
            end

            if (bvalid && bready) begin bvalid <= 0; aw_stored <= 0; w_stored <= 0; end
        end
    end

    reg [ADDR_W-1:0] araddr_r;
    reg              ar_stored;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            araddr_r <= 0; ar_stored <= 0; arready <= 0;
            rdata <= 0; rresp <= 0; rvalid <= 0;
        end else begin
            arready <= !ar_stored && !rvalid;
            if (arvalid && arready) begin araddr_r <= araddr; ar_stored <= 1; end
            if (ar_stored && !rvalid) begin
                rdata <= 0;
                if (araddr_r < NCH*16) begin
                    case (araddr_r[3:2])
                        SEL_SRC:  rdata <= src[araddr_r[7:4]];
                        SEL_DST:  rdata <= dst[araddr_r[7:4]];
                        SEL_LEN:  rdata <= {16'b0, len[araddr_r[7:4]]};
                        SEL_CTRL: rdata <= {30'b0, dst_inc[araddr_r[7:4]],
                                            src_inc[araddr_r[7:4]], start[araddr_r[7:4]]}
                                          | (done[araddr_r[7:4]] ? 32'h80000000 : 32'h0);
                    endcase
                end
                rresp <= 0; rvalid <= 1;
            end
            if (rvalid && rready) begin rvalid <= 0; ar_stored <= 0; end
        end
    end

    // ============================================================
    // 3. 传输引擎（一次搬一个字，单拍）
    // ============================================================
    localparam [3:0] S_IDLE = 0, S_RADDR = 1, S_RDATA = 2,
                     S_WADDR = 3, S_WDATA = 4, S_WRESP = 5, S_NEXT = 6;

    reg [3:0]        state;
    reg [3:0]        ch;                 // 当前通道
    reg [ADDR_W-1:0] cur_src, cur_dst;
    reg [15:0]       cur_len;
    reg [DATA_W-1:0] rdata_buf;

    integer i;

    // 找下一个待传输通道
    function [3:0] next_ch;
        input [3:0] from;
        integer j;
        begin
            next_ch = 4'd0;
            for (j = 0; j < NCH; j = j + 1) begin
                if (start[(from + j) % NCH]) begin
                    next_ch = (from + j) % NCH;
                    j = NCH;                // break
                end
            end
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE; ch <= 0; cur_src <= 0; cur_dst <= 0;
            cur_len <= 0; rdata_buf <= 0;
            AW_VALID <= 0; W_VALID <= 0; B_READY <= 0;
            AR_VALID <= 0; R_READY <= 0; irq <= 0;
            AW_SIZE <= 3'd2; AW_BURST <= 2'd1; AW_LEN <= 0;
            AR_SIZE <= 3'd2; AR_BURST <= 2'd1; AR_LEN <= 0;
            W_LAST <= 1; AW_ADDR <= 0; W_DATA <= 0; AR_ADDR <= 0;
        end else begin
            // 默认：脉冲信号复位
            AW_VALID <= 0; W_VALID <= 0; B_READY <= 0; AR_VALID <= 0; R_READY <= 0; irq <= 0;

            case (state)
                S_IDLE: begin
                    for (i = 0; i < NCH; i = i + 1)
                        if (start[i]) begin
                            ch       <= i[3:0];
                            cur_src  <= src[i];
                            cur_dst  <= dst[i];
                            cur_len  <= len[i];
                            start[i] <= 1'b0;       // 取走 START
                            state    <= S_RADDR;
                            i = NCH;
                        end
                end

                S_RADDR: begin                          // 发读地址
                    AR_ADDR  <= cur_src;
                    AR_VALID <= 1;
                    if (AR_READY) state <= S_RDATA;
                end

                S_RDATA: begin                          // 等读数据
                    R_READY <= 1;
                    if (R_VALID && R_READY) begin
                        rdata_buf <= R_DATA;
                        state <= S_WADDR;
                    end
                end

                S_WADDR: begin                          // 发写地址
                    AW_ADDR  <= cur_dst;
                    AW_VALID <= 1;
                    if (AW_READY) state <= S_WDATA;
                end

                S_WDATA: begin                          // 发写数据
                    W_DATA  <= rdata_buf;
                    W_VALID <= 1;
                    if (W_READY) state <= S_WRESP;
                end

                S_WRESP: begin                          // 等写响应
                    B_READY <= 1;
                    if (B_VALID && B_READY) state <= S_NEXT;
                end

                S_NEXT: begin                           // 更新地址/长度，判断是否结束
                    if (src_inc[ch]) cur_src <= cur_src + 4;
                    if (dst_inc[ch]) cur_dst <= cur_dst + 4;
                    if (cur_len <= 1) begin
                        done[ch] <= 1'b1;
                        irq      <= 1'b1;
                        state    <= S_IDLE;
                    end else begin
                        cur_len <= cur_len - 1;
                        state   <= S_RADDR;
                    end
                end
            endcase
        end
    end

endmodule

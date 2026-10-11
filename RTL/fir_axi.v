// ============================================================
// fir_axi.v —— FIR 滤波器的 AXI-Lite 从设备（寄存器映射外设）
//
// 这就是赛题里"FIR 滤波器挂载在 AXI 总线上"的实现：
//   CPU 通过读写一段"寄存器地址"，就能：
//     1. 配置系数（写 COEF[0..NTAP-1]）
//     2. 启动/清空（写 CTRL 的 START 位）
//     3. 喂入样本（写 DIN，每写一个 = 输入一个样本）
//     4. 取回结果（读 DOUT，每读一个 = 取走一个滤波结果）
//
// 寄存器映射（字节地址）：
//   0x000  CTRL    写：[0] START=1 清空延迟线和输出 FIFO，准备新一轮
//   0x004  DIN     写：低 16bit 是一个输入样本（触发一次滤波）
//   0x008  DOUT    读：低 16bit 是一个滤波结果（弹出一个结果）
//   0x00C  STATUS  读：[0] FIFO空 [1] FIFO满 [31:16] 结果个数
//   0x100+4*k COEF[k]  写：第 k 个系数（Q1.15）
//
// 内部结构：
//   AXI写通道 --写地址/数据--> 寄存器译码 --coef_we/en/flush--> fir_cfg
//   fir_cfg 的 dout --dout_v--> sync_fifo --rdata--> AXI读通道
// ============================================================
`timescale 1ns/1ps

module fir_axi #(
    parameter ADDR_W = 32,
    parameter DATA_W = 32,
    parameter DW     = 16,      // 数据位宽
    parameter CW     = 16,      // 系数位宽
    parameter AW     = 40,      // 累加器位宽
    parameter NTAP   = 81       // 抽头数
)(
    input  wire                 clk,
    input  wire                 rst_n,

    // ---- AXI-Lite 写地址 ----
    input  wire [ADDR_W-1:0]    awaddr,
    input  wire                 awvalid,
    output reg                  awready,
    // ---- AXI-Lite 写数据 ----
    input  wire [DATA_W-1:0]    wdata,
    input  wire [DATA_W/8-1:0]  wstrb,
    input  wire                 wvalid,
    output reg                  wready,
    // ---- AXI-Lite 写响应 ----
    output reg  [1:0]           bresp,
    output reg                  bvalid,
    input  wire                 bready,
    // ---- AXI-Lite 读地址 ----
    input  wire [ADDR_W-1:0]    araddr,
    input  wire                 arvalid,
    output reg                  arready,
    // ---- AXI-Lite 读数据 ----
    output reg  [DATA_W-1:0]    rdata,
    output reg  [1:0]           rresp,
    output reg                  rvalid,
    input  wire                 rready
);

    // ============================================================
    // 地址常量
    // ============================================================
    localparam ADDR_CTRL   = 32'h000;
    localparam ADDR_DIN    = 32'h004;
    localparam ADDR_DOUT   = 32'h008;
    localparam ADDR_STATUS = 32'h00C;
    localparam COEF_BASE   = 32'h100;

    // ============================================================
    // 内部控制信号（由写通道产生，送到 FIR / FIFO）
    // ============================================================
    reg [$clog2(NTAP)-1:0] coef_idx;
    reg signed [CW-1:0]    coef_din;
    reg                    coef_we;

    reg signed [DW-1:0]    fir_din;
    reg                    fir_en;
    reg                    fir_flush;

    // ============================================================
    // 1. AXI-Lite 写通道（地址+数据+响应）
    // ============================================================
    reg [ADDR_W-1:0] awaddr_r;
    reg [DATA_W-1:0] wdata_r;
    reg              aw_stored, w_stored;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            awaddr_r  <= {ADDR_W{1'b0}};
            wdata_r   <= {DATA_W{1'b0}};
            aw_stored <= 1'b0;
            w_stored  <= 1'b0;
            awready   <= 1'b0;
            wready    <= 1'b0;
            bresp     <= 2'b00;
            bvalid    <= 1'b0;
            coef_we   <= 1'b0;
            fir_en    <= 1'b0;
            fir_flush <= 1'b0;
            coef_idx  <= 0;
            coef_din  <= {CW{1'b0}};
            fir_din   <= {DW{1'b0}};
        end else begin
            awready <= !aw_stored && !bvalid;
            wready  <= !w_stored  && !bvalid;

            if (awvalid && awready) begin
                awaddr_r  <= awaddr;
                aw_stored <= 1'b1;
            end
            if (wvalid && wready) begin
                wdata_r  <= wdata;
                w_stored <= 1'b1;
            end

            // 默认：控制脉冲这一拍之后就归零（都是单拍脉冲）
            coef_we   <= 1'b0;
            fir_en    <= 1'b0;
            fir_flush <= 1'b0;

            // 地址和数据都到齐 -> 译码执行
            if (aw_stored && w_stored && !bvalid) begin
                // 系数写
                if (awaddr_r >= COEF_BASE && awaddr_r < COEF_BASE + 4*NTAP) begin
                    coef_idx <= (awaddr_r - COEF_BASE) >> 2;
                    coef_din <= wdata_r[CW-1:0];
                    coef_we  <= 1'b1;
                end
                // 样本输入
                else if (awaddr_r == ADDR_DIN) begin
                    fir_din <= wdata_r[DW-1:0];
                    fir_en  <= 1'b1;
                end
                // 控制：START 清空
                else if (awaddr_r == ADDR_CTRL && wdata_r[0]) begin
                    fir_flush <= 1'b1;
                end

                bresp  <= 2'b00;
                bvalid <= 1'b1;
            end

            if (bvalid && bready) begin
                bvalid    <= 1'b0;
                aw_stored <= 1'b0;
                w_stored  <= 1'b0;
            end
        end
    end

    // ============================================================
    // 2. FIR 内核
    // ============================================================
    wire signed [DW-1:0] fir_dout;
    wire                 fir_dout_v;

    fir_cfg #(.DW(DW), .CW(CW), .AW(AW), .NTAP(NTAP)) u_fir (
        .clk(clk), .rst_n(rst_n),
        .en(fir_en), .flush(fir_flush),
        .din(fir_din),
        .dout(fir_dout), .dout_v(fir_dout_v),
        .coef_idx(coef_idx), .coef_din(coef_din), .coef_we(coef_we)
    );

    // ============================================================
    // 3. 输出 FIFO：FIR 连续吐结果，CPU 慢慢读
    // ============================================================
    wire [DW-1:0] fifo_rdata;
    wire          fifo_empty, fifo_full;
    wire [$clog2(513)-1:0] fifo_count;
    reg           fifo_clr;
    reg           fifo_ren;

    sync_fifo #(.WIDTH(DW), .DEPTH(512)) u_fifo (
        .clk(clk), .rst_n(rst_n), .clr(fifo_clr),
        .wen(fir_dout_v), .wdata(fir_dout), .full(fifo_full),
        .ren(fifo_ren), .rdata(fifo_rdata), .empty(fifo_empty),
        .count(fifo_count)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            fifo_clr <= 1'b0;
        else
            fifo_clr <= fir_flush;      // START 时顺带清空 FIFO
    end

    // ============================================================
    // 4. AXI-Lite 读通道
    // ============================================================
    reg [ADDR_W-1:0] araddr_r;
    reg              ar_stored;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            araddr_r  <= {ADDR_W{1'b0}};
            ar_stored <= 1'b0;
            arready   <= 1'b0;
            rdata     <= {DATA_W{1'b0}};
            rresp     <= 2'b00;
            rvalid    <= 1'b0;
            fifo_ren  <= 1'b0;
        end else begin
            arready <= !ar_stored && !rvalid;

            fifo_ren <= 1'b0;               // 默认不弹 FIFO

            if (arvalid && arready) begin
                araddr_r  <= araddr;
                ar_stored <= 1'b1;
            end

            if (ar_stored && !rvalid) begin
                case (araddr_r)
                    ADDR_DOUT:   rdata <= {{(DATA_W-DW){1'b0}}, fifo_rdata};
                    ADDR_STATUS: rdata <= {6'b0, fifo_count, 14'b0, fifo_full, fifo_empty};
                    default:     rdata <= {DATA_W{1'b0}};
                endcase
                rresp  <= 2'b00;
                rvalid <= 1'b1;
            end

            // 主设备真正取走 DOUT 那一拍，才把 FIFO 弹出一个
            if (rvalid && rready && (araddr_r == ADDR_DOUT))
                fifo_ren <= 1'b1;

            if (rvalid && rready) begin
                rvalid    <= 1'b0;
                ar_stored <= 1'b0;
            end
        end
    end

endmodule

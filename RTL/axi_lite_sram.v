// ============================================================
// axi_lite_sram.v —— AXI-Lite 从设备：一块小 SRAM（片上存储）
//
// 作用（对应赛题"存储系统：片内 SRAM，通过 AXI 互连"）：
//   1. 当"内存"用：CPU 的指令 / 数据、DMA 的源/目的地址都指向这里。
//   2. 当"教学样板"用：这是 AXI-Lite 五通道握手的标准写法，
//      看懂这一个模块，就能照葫芦画瓢写任何 AXI-Lite 从设备。
//
// 本模块实现了 AXI-Lite 的完整握手（单拍，无 Burst）：
//   写地址通道  AW : awaddr / awvalid / awready
//   写数据通道  W  : wdata  / wstrb  / wvalid / wready
//   写响应通道  B  : bresp  / bvalid / bready
//   读地址通道  AR : araddr / arvalid / arready
//   读数据通道  R  : rdata  / rresp  / rvalid / rready
//
// 握手铁律（A 和 B 两个信号）：
//   A 拉高 valid 后，必须等 B 的 ready 也为高，
//   在"valid 和 ready 同一个时钟上升沿同时为 1"的那一刻，数据才算完成传输。
//   在此之前 A 不能撤 valid，B 也不能撤 ready。
//
// 存储组织：
//   32 位数据宽，按"字"编址。字节地址 addr[11:2] 是字索引。
//   wstrb 是按字节的写使能：wstrb[0] 对应 data[7:0]，wstrb[3] 对应 data[31:24]。
// ============================================================
`timescale 1ns/1ps

module axi_lite_sram #(
    parameter ADDR_W = 32,          // AXI 地址位宽
    parameter DATA_W = 32,          // AXI 数据位宽
    parameter DEPTH  = 1024         // 存储深度（字），1024 字 = 4KB
)(
    input  wire                 clk,
    input  wire                 rst_n,

    // ---- 写地址通道 ----
    input  wire [ADDR_W-1:0]    awaddr,
    input  wire                 awvalid,
    output reg                  awready,
    // ---- 写数据通道 ----
    input  wire [DATA_W-1:0]    wdata,
    input  wire [DATA_W/8-1:0]  wstrb,
    input  wire                 wvalid,
    output reg                  wready,
    // ---- 写响应通道 ----
    output reg  [1:0]           bresp,
    output reg                  bvalid,
    input  wire                 bready,
    // ---- 读地址通道 ----
    input  wire [ADDR_W-1:0]    araddr,
    input  wire                 arvalid,
    output reg                  arready,
    // ---- 读数据通道 ----
    output reg  [DATA_W-1:0]    rdata,
    output reg  [1:0]           rresp,
    output reg                  rvalid,
    input  wire                 rready
);

    // ============================================================
    // 1. 存储阵列
    // ============================================================
    reg [DATA_W-1:0] mem [0:DEPTH-1];

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            for (i = 0; i < DEPTH; i = i + 1)
                mem[i] <= {DATA_W{1'b0}};
    end

    // ============================================================
    // 2. 写通道：先存地址，再存数据，都到齐后真正写入，最后回 B 响应
    //
    // 为什么"地址和数据分开收"？
    //   因为 AXI 里 AW 和 W 是两个独立通道，地址可能比数据早一拍到，
    //   也可能晚一拍到，所以从设备要能"先接住一个、等另一个"。
    // ============================================================
    reg [ADDR_W-1:0] awaddr_r;
    reg [DATA_W-1:0] wdata_r;
    reg [DATA_W/8-1:0] wstrb_r;
    reg              aw_stored;      // 已经收到写地址
    reg              w_stored;       // 已经收到写数据

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            awaddr_r  <= {ADDR_W{1'b0}};
            wdata_r   <= {DATA_W{1'b0}};
            wstrb_r   <= {DATA_W/8{1'b0}};
            aw_stored <= 1'b0;
            w_stored  <= 1'b0;
            awready   <= 1'b0;
            wready    <= 1'b0;
            bresp     <= 2'b00;
            bvalid    <= 1'b0;
        end else begin
            // 准备好接地址/数据：只要当前没有压着一笔未完成的写
            awready <= !aw_stored && !bvalid;
            wready  <= !w_stored  && !bvalid;

            if (awvalid && awready) begin
                awaddr_r  <= awaddr;
                aw_stored <= 1'b1;
            end
            if (wvalid && wready) begin
                wdata_r  <= wdata;
                wstrb_r  <= wstrb;
                w_stored <= 1'b1;
            end

            // 地址和数据都到齐了 -> 真正写入（按字节使能）
            if (aw_stored && w_stored && !bvalid) begin
                if (wstrb_r[0]) mem[awaddr_r[11:2]][ 7: 0] <= wdata_r[ 7: 0];
                if (wstrb_r[1]) mem[awaddr_r[11:2]][15: 8] <= wdata_r[15: 8];
                if (wstrb_r[2]) mem[awaddr_r[11:2]][23:16] <= wdata_r[23:16];
                if (wstrb_r[3]) mem[awaddr_r[11:2]][31:24] <= wdata_r[31:24];
                bresp  <= 2'b00;            // OKAY
                bvalid <= 1'b1;
            end

            // 主设备把 B 响应拿走 -> 这一笔写彻底结束，放开通道
            if (bvalid && bready) begin
                bvalid    <= 1'b0;
                aw_stored <= 1'b0;
                w_stored  <= 1'b0;
            end
        end
    end

    // ============================================================
    // 3. 读通道：收到读地址 -> 取出数据 -> R 响应
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
        end else begin
            arready <= !ar_stored && !rvalid;

            if (arvalid && arready) begin
                araddr_r  <= araddr;
                ar_stored <= 1'b1;
            end

            if (ar_stored && !rvalid) begin
                rdata  <= mem[araddr_r[11:2]];
                rresp  <= 2'b00;            // OKAY
                rvalid <= 1'b1;
            end

            if (rvalid && rready) begin
                rvalid    <= 1'b0;
                ar_stored <= 1'b0;
            end
        end
    end

endmodule

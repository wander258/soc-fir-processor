// ============================================================
// soc_cm0_top.v —— 用【真实 Cortex-M0 DesignStart 核】的 SoC 顶层
//
// 这是把赛题指定 CPU 接进项目的版本：
//
//                    ┌──────────────────────────┐
//                    │  cortexm0ds (真 Cortex-M0)│
//                    │  内置 AHB→AXI 桥 → AXI 主 │
//                    └───────────┬──────────────┘
//                                │ AXI4
//                    ┌───────────┴──────────────┐
//                    │   地址译码 + 路由(本文件)  │
//                    └──┬─────────┬──────────┬───┘
//              ┌────────┴───┐ ┌───┴────┐ ┌────┴────────┐
//              │ RAM(程序+数据)│ │ FIR    │ │  UART       │
//              │ 0x00000000  │ │0x40000000│ │0x40001000  │
//              └────────────┘ └─────────┘ └─────────────┘
//
// 内存地图：
//   0x0000_0000 ~ 0x0000_FFFF  RAM（64KB，程序+数据+栈，上电从这里取指令）
//   0x4000_0000                FIR 滤波器（寄存器同 fir_axi.v）
//   0x4000_1000                UART（寄存器同 uart_axi.v）
//
// 与之前 BFM 版(08_soc)的区别：
//   1. CPU 从"测试台里的一段假代码"换成"真 Cortex-M0 核"。
//   2. 总线从 AXI-Lite 换成 AXI4（M0 自带 AHB→AXI 桥输出的是 AXI4）。
//   3. 内存地图按 CMSDK 惯例调整（外设放到 0x40000000 段）。
// ============================================================
`timescale 1ns/1ps

module soc_cm0_top #(
    parameter NTAP = 9             // FIR 抽头数：9=调试快；81=赛题（DesignStart 核仿真很慢，81 阶要跑很久）
)(
    input  wire        ACLK,       // 系统时钟
    input  wire        ARESETn,    // 低有效复位
    output wire        uart_txd    // UART 串行输出
);

    // ============================================================
    // 1. 地址译码
    // ============================================================
    localparam RAM_BASE  = 32'h0000_0000;
    localparam FIR_BASE  = 32'h4000_0000;
    localparam UART_BASE = 32'h4000_1000;

    localparam [1:0] SEL_RAM  = 2'd0;
    localparam [1:0] SEL_FIR  = 2'd1;
    localparam [1:0] SEL_UART = 2'd2;

    function [1:0] decode;
        input [31:0] a;
        begin
            if      (a[31:16] == 16'h0000)     decode = SEL_RAM;   // 0x0000xxxx
            else if (a[31:12] == 20'h40000)    decode = SEL_FIR;   // 0x40000xxx
            else if (a[31:12] == 20'h40001)    decode = SEL_UART;  // 0x40001xxx
            else                               decode = SEL_RAM;   // 默认给 RAM
        end
    endfunction

    // ============================================================
    // 2. Cortex-M0 的 AXI 主接口信号
    // ============================================================
    wire             AW_VALID, AW_READY;
    wire [2:0]       AW_SIZE;
    wire [1:0]       AW_BURST;
    wire [7:0]       AW_LEN;
    wire [31:0]      AW_ADDR;
    wire             W_VALID, W_READY, W_LAST;
    wire [31:0]      W_DATA;
    wire             B_VALID, B_READY;
    wire [1:0]       B_RESP;
    wire             AR_VALID, AR_READY;
    wire [2:0]       AR_SIZE;
    wire [1:0]       AR_BURST;
    wire [7:0]       AR_LEN;
    wire [31:0]      AR_ADDR;
    wire             R_VALID, R_READY, R_LAST;
    wire [31:0]      R_DATA;
    wire [1:0]       R_RESP;

    cortexm0ds u_cm0 (
        .ACLK(ACLK), .ARESETn(ARESETn),
        .AW_VALID(AW_VALID), .AW_READY(AW_READY),
        .AW_SIZE(AW_SIZE), .AW_BURST(AW_BURST), .AW_LEN(AW_LEN), .AW_ADDR(AW_ADDR),
        .W_VALID(W_VALID), .W_READY(W_READY), .W_LAST(W_LAST), .W_DATA(W_DATA),
        .B_VALID(B_VALID), .B_READY(B_READY), .B_RESP(B_RESP),
        .AR_VALID(AR_VALID), .AR_READY(AR_READY),
        .AR_SIZE(AR_SIZE), .AR_BURST(AR_BURST), .AR_LEN(AR_LEN), .AR_ADDR(AR_ADDR),
        .R_VALID(R_VALID), .R_READY(R_READY), .R_LAST(R_LAST), .R_DATA(R_DATA), .R_RESP(R_RESP),
        .NMI(1'b0), .IRQ(32'd0), .RXEV(1'b0),
        .STCLKEN(1'b1), .STCALIB(26'd0),
        .TXEV(), .LOCKUP(), .SYSRESETREQ(), .SLEEPING()
    );

    // ============================================================
    // 3. 地址译码 + 锁存（锁存"这次访问选了谁"，用于数据/响应阶段路由）
    // ============================================================
    wire [1:0] aw_sel = decode(AW_ADDR);
    wire [1:0] ar_sel = decode(AR_ADDR);

    reg [1:0] aw_sel_r, ar_sel_r;
    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            aw_sel_r <= SEL_RAM;
            ar_sel_r <= SEL_RAM;
        end else begin
            if (AW_VALID && AW_READY) aw_sel_r <= aw_sel;
            if (AR_VALID && AR_READY) ar_sel_r <= ar_sel;
        end
    end

    // ============================================================
    // 4. RAM（程序+数据，用 CMSDK 的 AXI RAM 行为模型，支持突发）
    // ============================================================
    wire ram_awready, ram_wready, ram_bvalid, ram_arready, ram_rvalid, ram_rlast;
    wire [1:0] ram_bresp, ram_rresp;
    wire [31:0] ram_rdata;

    // 关键：RAM 的 AW_SEL/AR_SEL 固定为 1，改用"门控 valid"来选通。
    //   为什么 W 通道也用当前译码 aw_sel（而不是锁存的 aw_sel_r）？
    //   因为 M0 的 AHB→AXI 桥是【同一拍同时】把 AW_VALID 和 W_VALID 拉高，
    //   此刻 aw_sel_r 还没来得及锁存（还是上一笔的旧值），用它门控 W 会把写喂错/喂空，导致写挂死。
    //   而 M0 单点未完成、AW_ADDR 在 W 期间保持不变，所以 W 用当前 aw_sel 是安全的。
    cmsdk_axi_ram_beh #(.AW(16), .filename("image.hex"), .WS_N(0), .WS_S(0)) u_ram (
        .ACLK(ACLK), .ARESETn(ARESETn),
        .AW_SEL(1'b1), .AW_VALID(AW_VALID && (aw_sel == SEL_RAM)), .AW_READY(ram_awready),
        .AW_SIZE(AW_SIZE), .AW_BURST(AW_BURST), .AW_LEN(AW_LEN), .AW_ADDR(AW_ADDR),
        .W_VALID(W_VALID && (aw_sel == SEL_RAM)), .W_READY(ram_wready), .W_LAST(W_LAST), .W_DATA(W_DATA),
        .B_VALID(ram_bvalid), .B_READY(B_READY && (aw_sel_r == SEL_RAM)), .B_RESP(ram_bresp),
        .AR_SEL(1'b1), .AR_VALID(AR_VALID && (ar_sel == SEL_RAM)), .AR_READY(ram_arready),
        .AR_SIZE(AR_SIZE), .AR_BURST(AR_BURST), .AR_LEN(AR_LEN), .AR_ADDR(AR_ADDR),
        .R_VALID(ram_rvalid), .R_READY(R_READY && (ar_sel_r == SEL_RAM)),
        .R_LAST(ram_rlast), .R_DATA(ram_rdata), .R_RESP(ram_rresp)
    );

    // ============================================================
    // 5. FIR（AXI-Lite 从设备 + AXI4 转换器）
    // ============================================================
    wire [31:0] fir_awaddr, fir_wdata, fir_araddr, fir_rdata;
    wire        fir_awvalid, fir_awready, fir_wvalid, fir_wready;
    wire [3:0]  fir_wstrb;
    wire        fir_bvalid, fir_bready, fir_arvalid, fir_arready, fir_rvalid, fir_rready;
    wire [1:0]  fir_bresp, fir_rresp;

    // 注意：axi4_to_axilite 的主侧 ready/valid 输出（AW_READY/W_READY/B_VALID/
    // AR_READY/R_VALID/R_DATA/R_RESP）其实是从侧信号的直通，这里故意【留空】，
    // 直接用 fir_axi 的 awready/wready/bvalid/arready/rvalid/rdata 接到 M0 的 mux。
    // 若把它们也接到 fir_awready 等同一根线上，会和 fir_axi 的输出多驱动冲突变成 X。
    axi4_to_axilite u_fir_adapter (
        .clk(ACLK), .rst_n(ARESETn),
        .AW_VALID(AW_VALID && (aw_sel == SEL_FIR)), .AW_READY(),
        .AW_SIZE(AW_SIZE), .AW_BURST(AW_BURST), .AW_LEN(AW_LEN), .AW_ADDR(AW_ADDR - FIR_BASE),
        .W_VALID(W_VALID && (aw_sel == SEL_FIR)), .W_READY(),
        .W_LAST(W_LAST), .W_DATA(W_DATA),
        .B_VALID(), .B_READY(B_READY && (aw_sel_r == SEL_FIR)), .B_RESP(),
        .AR_VALID(AR_VALID && (ar_sel == SEL_FIR)), .AR_READY(),
        .AR_SIZE(AR_SIZE), .AR_BURST(AR_BURST), .AR_LEN(AR_LEN), .AR_ADDR(AR_ADDR - FIR_BASE),
        .R_VALID(), .R_READY(R_READY && (ar_sel_r == SEL_FIR)), .R_LAST(),
        .R_DATA(), .R_RESP(),
        .awaddr(fir_awaddr), .awvalid(fir_awvalid), .awready(fir_awready),
        .wdata(fir_wdata), .wstrb(fir_wstrb), .wvalid(fir_wvalid), .wready(fir_wready),
        .bresp(fir_bresp), .bvalid(fir_bvalid), .bready(fir_bready),
        .araddr(fir_araddr), .arvalid(fir_arvalid), .arready(fir_arready),
        .rdata(fir_rdata), .rresp(fir_rresp), .rvalid(fir_rvalid), .rready(fir_rready)
    );

    fir_axi #(.ADDR_W(32), .DATA_W(32), .DW(16), .CW(16), .AW(40), .NTAP(NTAP)) u_fir (
        .clk(ACLK), .rst_n(ARESETn),
        .awaddr(fir_awaddr), .awvalid(fir_awvalid), .awready(fir_awready),
        .wdata(fir_wdata), .wstrb(fir_wstrb), .wvalid(fir_wvalid), .wready(fir_wready),
        .bresp(fir_bresp), .bvalid(fir_bvalid), .bready(fir_bready),
        .araddr(fir_araddr), .arvalid(fir_arvalid), .arready(fir_arready),
        .rdata(fir_rdata), .rresp(fir_rresp), .rvalid(fir_rvalid), .rready(fir_rready)
    );

    // ============================================================
    // 6. UART（AXI-Lite 从设备 + AXI4 转换器）
    // ============================================================
    wire [31:0] uart_awaddr, uart_wdata, uart_araddr, uart_rdata;
    wire        uart_awvalid, uart_awready, uart_wvalid, uart_wready;
    wire [3:0]  uart_wstrb;
    wire        uart_bvalid, uart_bready, uart_arvalid, uart_arready, uart_rvalid, uart_rready;
    wire [1:0]  uart_bresp, uart_rresp;

    axi4_to_axilite u_uart_adapter (
        .clk(ACLK), .rst_n(ARESETn),
        .AW_VALID(AW_VALID && (aw_sel == SEL_UART)), .AW_READY(),
        .AW_SIZE(AW_SIZE), .AW_BURST(AW_BURST), .AW_LEN(AW_LEN), .AW_ADDR(AW_ADDR - UART_BASE),
        .W_VALID(W_VALID && (aw_sel == SEL_UART)), .W_READY(),
        .W_LAST(W_LAST), .W_DATA(W_DATA),
        .B_VALID(), .B_READY(B_READY && (aw_sel_r == SEL_UART)), .B_RESP(),
        .AR_VALID(AR_VALID && (ar_sel == SEL_UART)), .AR_READY(),
        .AR_SIZE(AR_SIZE), .AR_BURST(AR_BURST), .AR_LEN(AR_LEN), .AR_ADDR(AR_ADDR - UART_BASE),
        .R_VALID(), .R_READY(R_READY && (ar_sel_r == SEL_UART)), .R_LAST(),
        .R_DATA(), .R_RESP(),
        .awaddr(uart_awaddr), .awvalid(uart_awvalid), .awready(uart_awready),
        .wdata(uart_wdata), .wstrb(uart_wstrb), .wvalid(uart_wvalid), .wready(uart_wready),
        .bresp(uart_bresp), .bvalid(uart_bvalid), .bready(uart_bready),
        .araddr(uart_araddr), .arvalid(uart_arvalid), .arready(uart_arready),
        .rdata(uart_rdata), .rresp(uart_rresp), .rvalid(uart_rvalid), .rready(uart_rready)
    );

    uart_axi #(.ADDR_W(32), .DATA_W(32), .BAUD(921600)) u_uart (  // 仿真加速用高波特率
        .clk(ACLK), .rst_n(ARESETn),
        .awaddr(uart_awaddr), .awvalid(uart_awvalid), .awready(uart_awready),
        .wdata(uart_wdata), .wstrb(uart_wstrb), .wvalid(uart_wvalid), .wready(uart_wready),
        .bresp(uart_bresp), .bvalid(uart_bvalid), .bready(uart_bready),
        .araddr(uart_araddr), .arvalid(uart_arvalid), .arready(uart_arready),
        .rdata(uart_rdata), .rresp(uart_rresp), .rvalid(uart_rvalid), .rready(uart_rready),
        .txd(uart_txd)
    );

    // ============================================================
    // 7. 把各从设备的 ready/valid 汇总回 M0
    // ============================================================
    assign AW_READY = (aw_sel == SEL_RAM)  ? ram_awready :
                      (aw_sel == SEL_FIR)  ? fir_awready  : uart_awready;

    assign W_READY  = (aw_sel == SEL_RAM)  ? ram_wready :
                      (aw_sel == SEL_FIR)  ? fir_wready  : uart_wready;

    assign B_VALID  = (aw_sel_r == SEL_RAM)  ? ram_bvalid :
                      (aw_sel_r == SEL_FIR)  ? fir_bvalid  : uart_bvalid;
    assign B_RESP   = (aw_sel_r == SEL_RAM)  ? ram_bresp :
                      (aw_sel_r == SEL_FIR)  ? fir_bresp  : uart_bresp;

    assign AR_READY = (ar_sel == SEL_RAM)  ? ram_arready :
                      (ar_sel == SEL_FIR)  ? fir_arready  : uart_arready;

    assign R_VALID  = (ar_sel_r == SEL_RAM)  ? ram_rvalid :
                      (ar_sel_r == SEL_FIR)  ? fir_rvalid  : uart_rvalid;
    assign R_DATA   = (ar_sel_r == SEL_RAM)  ? ram_rdata :
                      (ar_sel_r == SEL_FIR)  ? fir_rdata  : uart_rdata;
    assign R_RESP   = (ar_sel_r == SEL_RAM)  ? ram_rresp :
                      (ar_sel_r == SEL_FIR)  ? fir_rresp  : uart_rresp;
    assign R_LAST   = (ar_sel_r == SEL_RAM)  ? ram_rlast :
                      (ar_sel_r == SEL_FIR)  ? 1'b1        : 1'b1;

endmodule

// ============================================================
// soc_top.v —— 完整 SoC 顶层（最基本功能版）
//
// 系统框图：
//
//                    ┌──────────────┐
//                    │   CPU 核      │  (真系统里是 Cortex-M0；
//                    │  (AXI 主设备) │   仿真里用测试台的 BFM 扮演)
//                    └──────┬───────┘
//                           │ AXI-Lite
//                  ┌────────┴────────┐
//                  │  axi_lite_xbar  │  总线互连（地址译码 + 路由）
//                  └──┬──────┬───────┘
//              ┌──────┘      │       └────────┐
//        ┌─────┴─────┐ ┌────┴─────┐ ┌─────────┴─────┐
//        │  fir_axi  │ │ uart_axi │ │ axi_lite_sram │
//        │ 81阶 FIR  │ │  UART TX │ │   片上 SRAM   │
//        └───────────┘ └──────────┘ └───────────────┘
//
// 内存地图：
//   0x0000_0000  FIR   （0x100 起是系数寄存器）
//   0x0000_1000  UART
//   0x0000_2000  SRAM
//
// 这就是赛题 5.1"模块说明"里要求的那张图，落到代码上长这样。
// ============================================================
`timescale 1ns/1ps

module soc_top #(
    parameter ADDR_W = 32,
    parameter DATA_W = 32,
    parameter DW     = 16,      // FIR 数据位宽
    parameter CW     = 16,      // FIR 系数位宽
    parameter AW     = 40,      // FIR 累加器位宽
    parameter NTAP   = 81       // FIR 抽头数（赛题 81）
)(
    input  wire                 clk,
    input  wire                 rst_n,

    // ---- AXI-Lite 主端口（连 CPU）----
    input  wire [ADDR_W-1:0]    m_awaddr,
    input  wire                 m_awvalid,
    output wire                 m_awready,
    input  wire [DATA_W-1:0]    m_wdata,
    input  wire [DATA_W/8-1:0]  m_wstrb,
    input  wire                 m_wvalid,
    output wire                 m_wready,
    output wire [1:0]           m_bresp,
    output wire                 m_bvalid,
    input  wire                 m_bready,
    input  wire [ADDR_W-1:0]    m_araddr,
    input  wire                 m_arvalid,
    output wire                 m_arready,
    output wire [DATA_W-1:0]    m_rdata,
    output wire [1:0]           m_rresp,
    output wire                 m_rvalid,
    input  wire                 m_rready,

    // ---- UART 串行输出 ----
    output wire                 txd
);

    // ---- 互连 ----
    wire [ADDR_W-1:0]    s0_awaddr, s0_araddr, s1_awaddr, s1_araddr, s2_awaddr, s2_araddr;
    wire                 s0_awvalid, s0_arvalid, s1_awvalid, s1_arvalid, s2_awvalid, s2_arvalid;
    wire                 s0_awready, s0_arready, s1_awready, s1_arready, s2_awready, s2_arready;
    wire [DATA_W-1:0]    s0_wdata, s1_wdata, s2_wdata;
    wire [DATA_W/8-1:0]  s0_wstrb, s1_wstrb, s2_wstrb;
    wire                 s0_wvalid, s1_wvalid, s2_wvalid;
    wire                 s0_wready, s1_wready, s2_wready;
    wire [1:0]           s0_bresp, s1_bresp, s2_bresp;
    wire                 s0_bvalid, s1_bvalid, s2_bvalid;
    wire                 s0_bready, s1_bready, s2_bready;
    wire [DATA_W-1:0]    s0_rdata, s1_rdata, s2_rdata;
    wire [1:0]           s0_rresp, s1_rresp, s2_rresp;
    wire                 s0_rvalid, s1_rvalid, s2_rvalid;
    wire                 s0_rready, s1_rready, s2_rready;

    axi_lite_xbar #(.ADDR_W(ADDR_W), .DATA_W(DATA_W)) u_xbar (
        .clk(clk), .rst_n(rst_n),
        .m_awaddr(m_awaddr), .m_awvalid(m_awvalid), .m_awready(m_awready),
        .m_wdata(m_wdata),   .m_wstrb(m_wstrb),     .m_wvalid(m_wvalid), .m_wready(m_wready),
        .m_bresp(m_bresp),   .m_bvalid(m_bvalid),   .m_bready(m_bready),
        .m_araddr(m_araddr), .m_arvalid(m_arvalid), .m_arready(m_arready),
        .m_rdata(m_rdata),   .m_rresp(m_rresp),     .m_rvalid(m_rvalid), .m_rready(m_rready),
        .s0_awaddr(s0_awaddr), .s0_awvalid(s0_awvalid), .s0_awready(s0_awready),
        .s0_wdata(s0_wdata),   .s0_wstrb(s0_wstrb),     .s0_wvalid(s0_wvalid), .s0_wready(s0_wready),
        .s0_bresp(s0_bresp),   .s0_bvalid(s0_bvalid),   .s0_bready(s0_bready),
        .s0_araddr(s0_araddr), .s0_arvalid(s0_arvalid), .s0_arready(s0_arready),
        .s0_rdata(s0_rdata),   .s0_rresp(s0_rresp),     .s0_rvalid(s0_rvalid), .s0_rready(s0_rready),
        .s1_awaddr(s1_awaddr), .s1_awvalid(s1_awvalid), .s1_awready(s1_awready),
        .s1_wdata(s1_wdata),   .s1_wstrb(s1_wstrb),     .s1_wvalid(s1_wvalid), .s1_wready(s1_wready),
        .s1_bresp(s1_bresp),   .s1_bvalid(s1_bvalid),   .s1_bready(s1_bready),
        .s1_araddr(s1_araddr), .s1_arvalid(s1_arvalid), .s1_arready(s1_arready),
        .s1_rdata(s1_rdata),   .s1_rresp(s1_rresp),     .s1_rvalid(s1_rvalid), .s1_rready(s1_rready),
        .s2_awaddr(s2_awaddr), .s2_awvalid(s2_awvalid), .s2_awready(s2_awready),
        .s2_wdata(s2_wdata),   .s2_wstrb(s2_wstrb),     .s2_wvalid(s2_wvalid), .s2_wready(s2_wready),
        .s2_bresp(s2_bresp),   .s2_bvalid(s2_bvalid),   .s2_bready(s2_bready),
        .s2_araddr(s2_araddr), .s2_arvalid(s2_arvalid), .s2_arready(s2_arready),
        .s2_rdata(s2_rdata),   .s2_rresp(s2_rresp),     .s2_rvalid(s2_rvalid), .s2_rready(s2_rready)
    );

    // ---- 从设备 0：FIR（81 阶）----
    fir_axi #(.ADDR_W(ADDR_W), .DATA_W(DATA_W),
              .DW(DW), .CW(CW), .AW(AW), .NTAP(NTAP)) u_fir (
        .clk(clk), .rst_n(rst_n),
        .awaddr(s0_awaddr), .awvalid(s0_awvalid), .awready(s0_awready),
        .wdata(s0_wdata),   .wstrb(s0_wstrb),     .wvalid(s0_wvalid), .wready(s0_wready),
        .bresp(s0_bresp),   .bvalid(s0_bvalid),   .bready(s0_bready),
        .araddr(s0_araddr), .arvalid(s0_arvalid), .arready(s0_arready),
        .rdata(s0_rdata),   .rresp(s0_rresp),     .rvalid(s0_rvalid), .rready(s0_rready)
    );

    // ---- 从设备 1：UART ----
    uart_axi #(.ADDR_W(ADDR_W), .DATA_W(DATA_W)) u_uart (
        .clk(clk), .rst_n(rst_n),
        .awaddr(s1_awaddr), .awvalid(s1_awvalid), .awready(s1_awready),
        .wdata(s1_wdata),   .wstrb(s1_wstrb),     .wvalid(s1_wvalid), .wready(s1_wready),
        .bresp(s1_bresp),   .bvalid(s1_bvalid),   .bready(s1_bready),
        .araddr(s1_araddr), .arvalid(s1_arvalid), .arready(s1_arready),
        .rdata(s1_rdata),   .rresp(s1_rresp),     .rvalid(s1_rvalid), .rready(s1_rready),
        .txd(txd)
    );

    // ---- 从设备 2：SRAM ----
    axi_lite_sram #(.ADDR_W(ADDR_W), .DATA_W(DATA_W), .DEPTH(1024)) u_sram (
        .clk(clk), .rst_n(rst_n),
        .awaddr(s2_awaddr), .awvalid(s2_awvalid), .awready(s2_awready),
        .wdata(s2_wdata),   .wstrb(s2_wstrb),     .wvalid(s2_wvalid), .wready(s2_wready),
        .bresp(s2_bresp),   .bvalid(s2_bvalid),   .bready(s2_bready),
        .araddr(s2_araddr), .arvalid(s2_arvalid), .arready(s2_arready),
        .rdata(s2_rdata),   .rresp(s2_rresp),     .rvalid(s2_rvalid), .rready(s2_rready)
    );

endmodule

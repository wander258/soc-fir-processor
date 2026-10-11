// ============================================================
// axi_lite_xbar.v —— AXI-Lite 总线互连（1 主设备 -> 3 从设备）
//
// 对应赛题"基于 AXI 协议的 SoC 共享总线互连结构"：
//   CPU 只有一个 AXI 口，但 FIR、UART、SRAM 是三个不同的从设备，
//   中间就需要一个"交换开关"（crossbar）按地址把请求送到对的从设备。
//
// 地址映射（本 SoC 的"内存地图"）：
//   0x0000_0000 ~ 0x0000_0FFF   FIR 滤波器   (4KB)
//   0x0000_1000 ~ 0x0000_1FFF   UART          (4KB)
//   0x0000_2000 ~ 0x0000_3FFF   SRAM          (8KB)
//
// 工作原理（就两件事）：
//   1. 看地址落在哪个区间 -> 把主设备的 valid/addr/data 送到那个从设备；
//      其它从设备收到 valid=0（等于"没这回事"）。
//   2. 从设备的响应（bvalid/rvalid）再按"刚才选了谁"选回来送回主设备。
//
// 注意：本版只有 1 个主设备（CPU），所以不需要"仲裁"。
//   赛题要求"多主设备 + 总线仲裁"（CPU + DMA 两个主），那是下一步；
//   本模块把地址译码讲清楚，再加仲裁就是水到渠成。
// ============================================================
`timescale 1ns/1ps

module axi_lite_xbar #(
    parameter ADDR_W = 32,
    parameter DATA_W = 32
)(
    input  wire                 clk,
    input  wire                 rst_n,

    // ============ 主设备侧（连 CPU） ============
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

    // ============ 从设备侧（连 FIR / UART / SRAM） ============
    // 从设备 0：FIR
    output wire [ADDR_W-1:0]    s0_awaddr, s0_araddr,
    output wire                 s0_awvalid, s0_arvalid,
    input  wire                 s0_awready, s0_arready,
    output wire [DATA_W-1:0]    s0_wdata,
    output wire [DATA_W/8-1:0]  s0_wstrb,
    output wire                 s0_wvalid,
    input  wire                 s0_wready,
    input  wire [1:0]           s0_bresp, s0_rresp,
    input  wire                 s0_bvalid, s0_rvalid,
    output wire                 s0_bready, s0_rready,
    input  wire [DATA_W-1:0]    s0_rdata,

    // 从设备 1：UART
    output wire [ADDR_W-1:0]    s1_awaddr, s1_araddr,
    output wire                 s1_awvalid, s1_arvalid,
    input  wire                 s1_awready, s1_arready,
    output wire [DATA_W-1:0]    s1_wdata,
    output wire [DATA_W/8-1:0]  s1_wstrb,
    output wire                 s1_wvalid,
    input  wire                 s1_wready,
    input  wire [1:0]           s1_bresp, s1_rresp,
    input  wire                 s1_bvalid, s1_rvalid,
    output wire                 s1_bready, s1_rready,
    input  wire [DATA_W-1:0]    s1_rdata,

    // 从设备 2：SRAM
    output wire [ADDR_W-1:0]    s2_awaddr, s2_araddr,
    output wire                 s2_awvalid, s2_arvalid,
    input  wire                 s2_awready, s2_arready,
    output wire [DATA_W-1:0]    s2_wdata,
    output wire [DATA_W/8-1:0]  s2_wstrb,
    output wire                 s2_wvalid,
    input  wire                 s2_wready,
    input  wire [1:0]           s2_bresp, s2_rresp,
    input  wire                 s2_bvalid, s2_rvalid,
    output wire                 s2_bready, s2_rready,
    input  wire [DATA_W-1:0]    s2_rdata
);

    // ============================================================
    // 1. 地址译码：写地址选从设备，读地址选从设备
    // ============================================================
    localparam FIR_BASE  = 32'h0000_0000;
    localparam UART_BASE = 32'h0000_1000;
    localparam SRAM_BASE = 32'h0000_2000;
    localparam SRAM_END  = 32'h0000_4000;

    function [1:0] decode;
        input [ADDR_W-1:0] a;
        begin
            if (a >= SRAM_BASE && a < SRAM_END)   decode = 2'd2;
            else if (a >= UART_BASE)              decode = 2'd1;
            else                                  decode = 2'd0;
        end
    endfunction

    wire [1:0] aw_sel = decode(m_awaddr);
    wire [1:0] ar_sel = decode(m_araddr);

    // ============================================================
    // 2. 路由（主 -> 从）
    // ============================================================
    // 写地址/数据通道
    // 关键：从设备看到的是"相对地址"（减去自己的基地址），
    //       这样每个从设备都可以从 0x000 开始编自己的寄存器，互不干扰。
    assign s0_awaddr  = m_awaddr - FIR_BASE;   assign s0_awvalid = m_awvalid && (aw_sel == 2'd0);
    assign s1_awaddr  = m_awaddr - UART_BASE;  assign s1_awvalid = m_awvalid && (aw_sel == 2'd1);
    assign s2_awaddr  = m_awaddr - SRAM_BASE;  assign s2_awvalid = m_awvalid && (aw_sel == 2'd2);

    assign s0_wdata = m_wdata; assign s0_wstrb = m_wstrb; assign s0_wvalid = m_wvalid && (aw_sel == 2'd0);
    assign s1_wdata = m_wdata; assign s1_wstrb = m_wstrb; assign s1_wvalid = m_wvalid && (aw_sel == 2'd1);
    assign s2_wdata = m_wdata; assign s2_wstrb = m_wstrb; assign s2_wvalid = m_wvalid && (aw_sel == 2'd2);

    // 主设备 awready/wready = 被选中的从设备的 ready
    assign m_awready = (aw_sel == 2'd0) ? s0_awready :
                       (aw_sel == 2'd1) ? s1_awready : s2_awready;
    assign m_wready  = (aw_sel == 2'd0) ? s0_wready :
                       (aw_sel == 2'd1) ? s1_wready  : s2_wready;

    // 读地址通道
    assign s0_araddr = m_araddr - FIR_BASE;  assign s0_arvalid = m_arvalid && (ar_sel == 2'd0);
    assign s1_araddr = m_araddr - UART_BASE; assign s1_arvalid = m_arvalid && (ar_sel == 2'd1);
    assign s2_araddr = m_araddr - SRAM_BASE; assign s2_arvalid = m_arvalid && (ar_sel == 2'd2);

    assign m_arready = (ar_sel == 2'd0) ? s0_arready :
                       (ar_sel == 2'd1) ? s1_arready : s2_arready;

    // ============================================================
    // 3. 记住"刚才选了谁"（握手完成那一拍锁存），用于选响应回来
    // ============================================================
    reg [1:0] aw_sel_r, ar_sel_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_sel_r <= 2'd0;
            ar_sel_r <= 2'd0;
        end else begin
            if (m_awvalid && m_awready) aw_sel_r <= aw_sel;
            if (m_arvalid && m_arready) ar_sel_r <= ar_sel;
        end
    end

    // ============================================================
    // 4. 响应选回来（从 -> 主）
    // ============================================================
    // 写响应 B
    assign m_bvalid = (aw_sel_r == 2'd0) ? s0_bvalid :
                      (aw_sel_r == 2'd1) ? s1_bvalid : s2_bvalid;
    assign m_bresp  = (aw_sel_r == 2'd0) ? s0_bresp :
                      (aw_sel_r == 2'd1) ? s1_bresp  : s2_bresp;
    assign s0_bready = m_bready && (aw_sel_r == 2'd0);
    assign s1_bready = m_bready && (aw_sel_r == 2'd1);
    assign s2_bready = m_bready && (aw_sel_r == 2'd2);

    // 读响应 R
    assign m_rvalid = (ar_sel_r == 2'd0) ? s0_rvalid :
                      (ar_sel_r == 2'd1) ? s1_rvalid : s2_rvalid;
    assign m_rresp  = (ar_sel_r == 2'd0) ? s0_rresp :
                      (ar_sel_r == 2'd1) ? s1_rresp  : s2_rresp;
    assign m_rdata  = (ar_sel_r == 2'd0) ? s0_rdata :
                      (ar_sel_r == 2'd1) ? s1_rdata  : s2_rdata;
    assign s0_rready = m_rready && (ar_sel_r == 2'd0);
    assign s1_rready = m_rready && (ar_sel_r == 2'd1);
    assign s2_rready = m_rready && (ar_sel_r == 2'd2);

endmodule

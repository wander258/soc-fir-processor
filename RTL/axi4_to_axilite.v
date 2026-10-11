// ============================================================
// axi4_to_axilite.v —— AXI4 主接口 → AXI-Lite 从接口的协议转换
//
// 为什么需要它：
//   Cortex-M0 的 AXI 口是"完整 AXI4"（带 AW_SIZE/AW_BURST/AW_LEN/
//   W_LAST/R_LAST 等突发信号），而我之前的 FIR/UART 从设备是
//   "AXI-Lite"（只有单拍，没有突发）。
//   这个模块就是一个"翻译器"：把 M0 的 AXI4 信号接到 AXI-Lite 从设备上。
//
// 关键点：
//   1. Cortex-M0 访问外设寄存器时永远只发"单拍"（AW_LEN=0），
//      所以这里可以安全地把突发信号丢掉、把 R_LAST 固定为 1。
//   2. AXI4 没有 WSTRB（写字节选通），而 AXI-Lite 需要它；
//      因为我们的 C 程序对寄存器都是"整字(32bit)访问"，所以直接给 4'hF。
//      （需要字节/半字访问时，可改成按 AW_SIZE+AW_ADDR[1:0] 译码。）
// ============================================================
`timescale 1ns/1ps

module axi4_to_axilite (
    input  wire             clk,
    input  wire             rst_n,

    // ---- AXI4 主设备侧（连 Cortex-M0）----
    input  wire             AW_VALID,
    output wire             AW_READY,
    input  wire [2:0]       AW_SIZE,
    input  wire [1:0]       AW_BURST,
    input  wire [7:0]       AW_LEN,
    input  wire [31:0]      AW_ADDR,

    input  wire             W_VALID,
    output wire             W_READY,
    input  wire             W_LAST,
    input  wire [31:0]      W_DATA,

    output wire             B_VALID,
    input  wire             B_READY,
    output wire [1:0]       B_RESP,

    input  wire             AR_VALID,
    output wire             AR_READY,
    input  wire [2:0]       AR_SIZE,
    input  wire [1:0]       AR_BURST,
    input  wire [7:0]       AR_LEN,
    input  wire [31:0]      AR_ADDR,

    output wire             R_VALID,
    input  wire             R_READY,
    output wire             R_LAST,
    output wire [31:0]      R_DATA,
    output wire [1:0]       R_RESP,

    // ---- AXI-Lite 从设备侧（连 fir_axi / uart_axi）----
    output wire [31:0]      awaddr,
    output wire             awvalid,
    input  wire             awready,
    output wire [31:0]      wdata,
    output wire [3:0]       wstrb,
    output wire             wvalid,
    input  wire             wready,
    input  wire [1:0]       bresp,
    input  wire             bvalid,
    output wire             bready,
    output wire [31:0]      araddr,
    output wire             arvalid,
    input  wire             arready,
    input  wire [31:0]      rdata,
    input  wire [1:0]       rresp,
    input  wire             rvalid,
    output wire             rready
);

    // ---- 写地址 ----
    assign awaddr  = AW_ADDR;
    assign awvalid = AW_VALID;
    assign AW_READY = awready;

    // ---- 写数据（整字访问，wstrb 固定全 1）----
    assign wdata  = W_DATA;
    assign wstrb  = 4'hF;
    assign wvalid = W_VALID;
    assign W_READY = wready;

    // ---- 写响应 ----
    assign B_VALID = bvalid;
    assign B_RESP  = bresp;
    assign bready  = B_READY;

    // ---- 读地址 ----
    assign araddr  = AR_ADDR;
    assign arvalid = AR_VALID;
    assign AR_READY = arready;

    // ---- 读数据（单拍，R_LAST 恒为 1）----
    assign R_VALID = rvalid;
    assign R_DATA  = rdata;
    assign R_RESP  = rresp;
    assign R_LAST  = rvalid;      // 每笔读都是最后一拍
    assign rready  = R_READY;

    // AW_SIZE/AW_BURST/AW_LEN/W_LAST/AR_* 突发信号在这里有意忽略，
    // 因为 Cortex-M0 对外设寄存器只发单拍。

endmodule

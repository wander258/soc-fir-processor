// ============================================================
// uart_axi.v —— UART 发送器的 AXI-Lite 从设备（寄存器映射外设）
//
// 寄存器映射（字节地址）：
//   0x000  DATA    写：低 8bit 是要发送的字节（触发一次发送）
//   0x004  STATUS  读：[0] busy（1=正在发送）
//
// CPU 用它的流程（对应赛题"UART 回显"）：
//   写一个字节 -> 读 STATUS 等 busy=0 -> 写下一个字节 -> ...
// ============================================================
`timescale 1ns/1ps

module uart_axi #(
    parameter ADDR_W = 32,
    parameter DATA_W = 32
)(
    input  wire                 clk,
    input  wire                 rst_n,

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

    // ---- UART 串行输出 ----
    output wire                 txd
);

    localparam ADDR_DATA   = 32'h000;
    localparam ADDR_STATUS = 32'h004;

    // ---- 发送控制 ----
    reg [7:0] tx_data;
    reg       tx_start;
    wire      tx_busy;

    uart_tx u_tx (
        .clk(clk), .rst_n(rst_n),
        .din(tx_data), .start(tx_start),
        .txd(txd), .busy(tx_busy)
    );

    // ============================================================
    // 写通道
    // ============================================================
    reg [ADDR_W-1:0] awaddr_r;
    reg [DATA_W-1:0] wdata_r;
    reg              aw_stored, w_stored;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            awaddr_r  <= 0; aw_stored <= 0; awready <= 0;
            wdata_r   <= 0; w_stored  <= 0; wready  <= 0;
            bresp <= 0; bvalid <= 0;
            tx_data <= 0; tx_start <= 0;
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

            tx_start <= 1'b0;                        // 单拍脉冲

            if (aw_stored && w_stored && !bvalid) begin
                if (awaddr_r == ADDR_DATA) begin
                    tx_data  <= wdata_r[7:0];
                    tx_start <= 1'b1;
                end
                bresp  <= 2'b00;
                bvalid <= 1'b1;
            end

            if (bvalid && bready) begin
                bvalid <= 0; aw_stored <= 0; w_stored <= 0;
            end
        end
    end

    // ============================================================
    // 读通道
    // ============================================================
    reg [ADDR_W-1:0] araddr_r;
    reg              ar_stored;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            araddr_r <= 0; ar_stored <= 0; arready <= 0;
            rdata <= 0; rresp <= 0; rvalid <= 0;
        end else begin
            arready <= !ar_stored && !rvalid;

            if (arvalid && arready) begin
                araddr_r  <= araddr;
                ar_stored <= 1'b1;
            end

            if (ar_stored && !rvalid) begin
                case (araddr_r)
                    ADDR_STATUS: rdata <= {31'b0, tx_busy};
                    default:     rdata <= 32'b0;
                endcase
                rresp  <= 2'b00;
                rvalid <= 1'b1;
            end

            if (rvalid && rready) begin
                rvalid <= 0; ar_stored <= 0;
            end
        end
    end

endmodule

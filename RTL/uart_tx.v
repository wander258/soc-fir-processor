// ============================================================
// uart_tx.v —— 简易 UART 发送器（8N1，无校验位，1 停止位）
//
// 作用（对应赛题"AXI 到 APB 接口桥（UART）"里的 UART 外设）：
//   CPU 把一个字节写进寄存器，这个模块就按串口协议一比特一比特发出去。
//   在仿真里，我们看 txd 线上的电平变化就能"看到"它发出的字节。
//
// 协议（8N1）：
//   空闲 = 高电平；起始位 = 1 拍低电平；
//   然后 8 个数据位（先发最低位 LSB）；最后 1 个停止位 = 高电平。
//
// 波特率：默认 115200。CLK_FREQ/BAUD = 每个比特占多少个时钟。
//   （仿真里 100MHz 时钟、115200 波特，一个比特约 868 拍，有点慢，
//     所以给了 BAUD 参数，需要时可以调大加快仿真。）
// ============================================================
`timescale 1ns/1ps

module uart_tx #(
    parameter CLK_FREQ = 100_000_000,   // 时钟频率 Hz
    parameter BAUD     = 115200          // 波特率
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  din,             // 要发送的字节
    input  wire        start,           // 拉高一拍：开始发送
    output reg         txd,             // 串行输出线
    output reg         busy             // 1=正在发送
);

    localparam BIT_CNT = CLK_FREQ / BAUD;   // 每个比特的时钟数（868）

    localparam S_IDLE = 0, S_START = 1, S_DATA = 2, S_STOP = 3;

    reg [1:0]  state;
    reg [15:0] bit_timer;
    reg [2:0]  bit_idx;
    reg [7:0]  shifter;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            txd       <= 1'b1;
            busy      <= 1'b0;
            bit_timer <= 0;
            bit_idx   <= 0;
            shifter   <= 8'b0;
        end
        else begin
            case (state)
                S_IDLE: begin
                    txd  <= 1'b1;
                    busy <= 1'b0;
                    if (start) begin
                        shifter   <= din;
                        busy      <= 1'b1;
                        bit_timer <= BIT_CNT - 1;
                        state     <= S_START;
                    end
                end
                S_START: begin
                    txd <= 1'b0;                        // 起始位（低）
                    if (bit_timer == 0) begin
                        bit_timer <= BIT_CNT - 1;
                        bit_idx   <= 0;
                        state     <= S_DATA;
                    end else
                        bit_timer <= bit_timer - 1'b1;
                end
                S_DATA: begin
                    txd <= shifter[0];                  // 先发最低位
                    if (bit_timer == 0) begin
                        shifter   <= {1'b0, shifter[7:1]};
                        if (bit_idx == 7) begin
                            bit_timer <= BIT_CNT - 1;
                            state     <= S_STOP;
                        end else begin
                            bit_idx   <= bit_idx + 1'b1;
                            bit_timer <= BIT_CNT - 1;
                        end
                    end else
                        bit_timer <= bit_timer - 1'b1;
                end
                S_STOP: begin
                    txd <= 1'b1;                        // 停止位（高）
                    if (bit_timer == 0) begin
                        busy  <= 1'b0;
                        state <= S_IDLE;
                    end else
                        bit_timer <= bit_timer - 1'b1;
                end
            endcase
        end
    end

endmodule

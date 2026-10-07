// ============================================================
// 实验 02：移位寄存器 / 延迟线
//
// 这就是 FIR 滤波器的"骨架"：
//   FIR 的输出 y[n] = h[0]*x[n] + h[1]*x[n-1] + ... + h[NTAP-1]*x[n-NTAP+1]
//   要同时拿到 x[n..n-NTAP+1] 这 NTAP 个历史样本，靠的就是这条延迟线。
//
// 一个必须记住的结论：
//   延迟线的每一级都占用 1 个时钟周期，所以在 1 sample/cycle 的架构里，
//   81 阶 FIR 的群延迟就是 (81-1)/2 = 40 拍。
// ============================================================
`timescale 1ns/1ps

module delay_line #(
    parameter WIDTH = 8,
    parameter TAPS  = 4
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     en,         // 每拍移入一个新样本
    input  wire signed [WIDTH-1:0]  din,        // 最新样本 x[n]
    output wire signed [WIDTH-1:0]  d0,         // = x[n]
    output wire signed [WIDTH-1:0]  dout        // = x[n-TAPS+1]，最老的一级
);

    // 用寄存器数组当延迟线：z[0] 最新，z[k] = x[n-k]
    reg signed [WIDTH-1:0] z [0:TAPS-1];
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < TAPS; i = i + 1)
                z[i] <= {WIDTH{1'b0}};
        end
        else if (en) begin
            z[0] <= din;                        // 新样本从 0 号挤进来
            for (i = 1; i < TAPS; i = i + 1)
                z[i] <= z[i-1];                 // 老的往后挪一格
        end
    end

    assign d0   = z[0];
    assign dout = z[TAPS-1];

endmodule

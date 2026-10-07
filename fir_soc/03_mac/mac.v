// ============================================================
// 实验 03：有符号乘累加器 MAC（Multiply-Accumulate）
//
// 这是 FIR 里唯一"有难度"的算术点，也是大二最容易错的地方：
//
//   1. 16bit × 16bit 有符号相乘 = 32bit 有符号结果
//   2. 要把 32bit 塞进 40bit 累加器，必须做【符号扩展】
//      —— 负数高位补 1，不能补 0。补 0 就是错的，而且错了还很难看出来。
//   3. 81 阶 FIR 为什么累加器要 40 位？
//      最坏情况 81 * 32768 * 32768 ≈ 8.7e10 < 2^40 ≈ 1.1e12  ✔
//      32 位只有 2.1e9，一定会溢出。
// ============================================================
`timescale 1ns/1ps

module mac #(
    parameter DW = 16,          // 乘数位宽（16bit 数据 / 系数）
    parameter AW = 40           // 累加器位宽
)(
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 en,             // 累加使能
    input  wire                 clr,            // 清零（优先级高于 en）
    input  wire signed [DW-1:0] a,
    input  wire signed [DW-1:0] b,
    output reg  signed [AW-1:0] acc
);

    // ---- 有符号乘法：16 x 16 -> 32 ----
    // 注意 Verilog 的位宽规则：表达式位宽由"上下文"（这里左边是 32 位）决定，
    // 所以 a、b 会先被符号扩展到 32 位再相乘，结果就是正确的 32 位有符号乘积。
    // 这也是最容易踩的坑：如果左边只有 16 位，高位就被截掉了。
    wire signed [2*DW-1:0] prod = a * b;

    // ---- 符号扩展到 AW 位 ----
    // {N{prod[最高位]}} 是把符号位复制 N 份，这就是"符号扩展"
    // AW - 2*DW = 40 - 32 = 8，所以复制 8 份符号位
    wire signed [AW-1:0] prod_ext = {{(AW-2*DW){prod[2*DW-1]}}, prod};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)     acc <= {AW{1'b0}};
        else if (clr)   acc <= {AW{1'b0}};
        else if (en)    acc <= acc + prod_ext;
    end

endmodule

// ============================================================
// 实验 01：最简单的时序电路 —— 计数器
//
// 目的：搞懂最核心的 4 件事
//   1. 时钟是什么（always @(posedge clk)）
//   2. 异步复位怎么写（or negedge rst_n）
//   3. 时序逻辑必须用非阻塞赋值 <=，组合逻辑用 assign
//   4. 怎么看波形
// ============================================================
`timescale 1ns/1ps

module counter #(
    parameter WIDTH = 4
)(
    input  wire             clk,
    input  wire             rst_n,      // 低电平有效复位
    input  wire             en,         // 计数使能
    output reg  [WIDTH-1:0] cnt,        // 当前计数值
    output wire             tick        // 计满回绕的那一拍拉高
);

    // ---- 时序逻辑：只在时钟上升沿（或复位下降沿）改变 ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            cnt <= {WIDTH{1'b0}};       // 非阻塞赋值 <= ：时序逻辑必须用它
        else if (en)
            cnt <= cnt + 1'b1;
    end

    // ---- 组合逻辑：用 assign，输入一变输出立刻变 ----
    assign tick = en && (cnt == {WIDTH{1'b1}});

endmodule

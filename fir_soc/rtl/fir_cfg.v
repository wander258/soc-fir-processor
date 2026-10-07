// ============================================================
// fir_cfg.v —— 可配置系数的 FIR 滤波器内核（全并行，1 sample/cycle）
//
// 和实验 04/05 里的 fir.v 几乎一样，唯一区别：
//   实验版：系数用 `include "coeffs.vh" 写死（编译期常量），适合教学。
//   本模块：系数是【寄存器】，可以在运行时通过 coef_we 一个一个写进去。
//           这正是赛题"81 阶可配置系数 FIR"要求的"可配置"。
//
// 端口说明：
//   en        ：拉高一个时钟，表示输入一个样本 din 并算一次滤波
//   din/dout  ：16bit 有符号定点（Q1.15：真实值 = 整数 / 2^15）
//   dout_v    ：dout 有效的标志（比输入晚 1 拍）
//   coef_idx  ：要写第几个系数（0 ~ NTAP-1）
//   coef_din  ：该系数的值（Q1.15）
//   coef_we   ：写使能，拉高一个时钟把 coef_din 写进 h[coef_idx]
//
// 定点约定（必须和黄金模型 gen_fir_vectors.py 完全一致）：
//   乘积 = X*H / 2^30，累加后右移 15 位回到 Q1.15，再饱和。
// ============================================================
`timescale 1ns/1ps

module fir_cfg #(
    parameter DW   = 16,        // 数据位宽
    parameter CW   = 16,        // 系数位宽（Q1.15）
    parameter AW   = 40,        // 累加器位宽（81 阶必须 >= 39，取 40）
    parameter NTAP = 81         // 抽头数（赛题 81；调试可用 9）
)(
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 en,                     // 每拍处理一个样本
    input  wire                 flush,                  // 拉高一拍：清空延迟线（系数保留）
    input  wire signed [DW-1:0] din,
    output reg  signed [DW-1:0] dout,
    output reg                  dout_v,

    // ---- 系数配置端口 ----
    input  wire [$clog2(NTAP)-1:0] coef_idx,
    input  wire signed [CW-1:0]    coef_din,
    input  wire                    coef_we
);

    // ---------------------------------------------------------
    // 1. 系数寄存器（可运行时配置）
    // ---------------------------------------------------------
    reg signed [CW-1:0] h [0:NTAP-1];

    // ---------------------------------------------------------
    // 2. 样本延迟线：x[0] 是最新样本，x[k] = x[n-k]
    // ---------------------------------------------------------
    reg signed [DW-1:0] x [0:NTAP-1];

    // ---------------------------------------------------------
    // 3. 并行乘法：NTAP 个 16x16 有符号乘法器
    // ---------------------------------------------------------
    wire signed [DW+CW-1:0] p [0:NTAP-1];
    genvar g;
    generate
        for (g = 0; g < NTAP; g = g + 1) begin : g_mul
            assign p[g] = x[g] * h[g];
        end
    endgenerate

    // ---------------------------------------------------------
    // 4. 累加（组合逻辑，符号扩展到 AW 位）
    // ---------------------------------------------------------
    reg signed [AW-1:0] sum;
    integer k;
    always @(*) begin
        sum = {AW{1'b0}};
        for (k = 0; k < NTAP; k = k + 1)
            sum = sum + {{(AW-DW-CW){p[k][DW+CW-1]}}, p[k]};
    end

    // ---------------------------------------------------------
    // 5. 截位回 Q1.15 + 饱和
    // ---------------------------------------------------------
    localparam SHIFT = CW - 1;          // = 15

    wire signed [DW-1:0] y_trunc = sum[SHIFT+DW-1 : SHIFT];
    wire overflow = (sum[AW-1 : SHIFT+DW] != {{(AW-SHIFT-DW){sum[SHIFT+DW-1]}}});
    wire signed [DW-1:0] y_sat = overflow
                               ? (sum[AW-1] ? {1'b1, {DW-1{1'b0}}}
                                            : {1'b0, {DW-1{1'b1}}})
                               : y_trunc;

    // ---------------------------------------------------------
    // 6. 时序逻辑：系数写入 + 延迟线移位 + 输出寄存
    // ---------------------------------------------------------
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < NTAP; i = i + 1) begin
                h[i] <= {CW{1'b0}};
                x[i] <= {DW{1'b0}};
            end
            dout   <= {DW{1'b0}};
            dout_v <= 1'b0;
        end
        else begin
            if (coef_we)
                h[coef_idx] <= coef_din;

            if (flush) begin
                for (i = 0; i < NTAP; i = i + 1)
                    x[i] <= {DW{1'b0}};
                dout_v <= 1'b0;
            end
            else if (en) begin
                for (i = NTAP-1; i > 0; i = i - 1)
                    x[i] <= x[i-1];
                x[0]   <= din;
                dout   <= y_sat;        // 用的是移位"前"的 x[]，正是滤波需要的 x[n-k]
                dout_v <= 1'b1;
            end
            else begin
                dout_v <= 1'b0;
            end
        end
    end

endmodule

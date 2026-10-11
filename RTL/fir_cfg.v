// ============================================================
// fir_cfg.v —— 可配置系数的 FIR 滤波器内核（流水线加法树，1 sample/cycle）
//
// 和实验 04/05 里的 fir.v 的区别：
//   实验版：系数用 `include "coeffs.vh" 写死（编译期常量），适合教学。
//   本模块：系数是【寄存器】，可以在运行时通过 coef_we 一个一个写进去。
//           这正是赛题"81 阶可配置系数 FIR"要求的"可配置"。
//
// 端口说明：
//   en        ：拉高一个时钟，表示输入一个样本 din 并算一次滤波
//   din/dout  ：16bit 有符号定点（Q1.15：真实值 = 整数 / 2^15）
//   dout_v    ：dout 有效的标志（比 en 晚 LAT=5 拍）
//   coef_idx  ：要写第几个系数（0 ~ NTAP-1）
//   coef_din  ：该系数的值（Q1.15）
//   coef_we   ：写使能，拉高一个时钟把 coef_din 写进 h[coef_idx]
//
// 定点约定（必须和黄金模型 gen_fir_vectors.py 完全一致）：
//   乘积 = X*H / 2^30，累加后右移 15 位回到 Q1.15，再饱和。
//
// ============================================================
// 【本次改造】累加结构：81 级串行链 → 7 级加法树 + 5 级流水
// ============================================================
// 改造前（旧版）：
//     always @(*) begin
//         sum = 0;
//         for (k = 0; k < NTAP; k = k + 1)
//             sum = sum + p[k];        // ← 81 项【依次】串起来
//     end
//   综合出来是一条 81 级的串行进位链，关键路径约 32~65 ns，
//   对应 Fmax 只有 15~31 MHz —— 25 MHz 都没余量，50 MHz 必然不收敛。
//   （详见 docs/任务5-FIR定点方案说明书.md 第 6.1 节）
//
// 改造后（本文件）：
//   S1  81 个 16x16 有符号乘法             → 打拍寄存
//   S2  加法树 第 1~3 级（81→41→21→11）    → 打拍寄存
//   S3  加法树 第 4~5 级（11→6→3）         → 打拍寄存
//   S4  加法树 第 6~7 级（3→2→1）          → 打拍寄存
//   S5  右移 15 位 + 溢出判断 + 饱和       → 打拍寄存
//
//   加法树把组合深度从 81 级降到 7 级（同样的 80 个加法器，面积几乎不变，
//   速度提升一个数量级）。再分成 3 段打拍，每段只剩 2~3 级加法。
//
//   吞吐量不变：仍然 1 sample/cycle。
//   代价是延迟从 1 拍变成 LAT=5 拍（100MHz 下 50ns，相对系统 μs 级延迟可忽略）。
//
//   输出序列本身没有变（第 i 个 dout_v 有效输出还是序列里第 i 个结果），
//   只是整体往后平移了 4 拍，所以原有的 testbench 比对约定不需要改。
// ============================================================
`timescale 1ns/1ps

module fir_cfg #(
    parameter DW   = 16,        // 数据位宽
    parameter CW   = 16,        // 系数位宽（Q1.15）
    parameter AW   = 40,        // 累加器位宽（81 阶下限 38，取 40，见任务5说明书 §3.4）
    parameter NTAP = 81         // 抽头数（赛题 81；调试可用 9）
)(
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 en,                     // 每拍处理一个样本
    input  wire                 flush,                  // 拉高一拍：清空延迟线与流水线（系数保留）
    input  wire signed [DW-1:0] din,
    output reg  signed [DW-1:0] dout,
    output wire                 dout_v,

    // ---- 系数配置端口 ----
    input  wire [$clog2(NTAP)-1:0] coef_idx,
    input  wire signed [CW-1:0]    coef_din,
    input  wire                    coef_we
);

    // ---- 流水线总延迟（en 拉高到 dout 有效之间的拍数）----
    localparam LAT   = 5;
    localparam SHIFT = CW - 1;          // = 15，累加结果右移回 Q1.15

    // ============================================================
    // 1. 系数寄存器 + 样本延迟线
    // ============================================================
    reg signed [CW-1:0] h [0:NTAP-1];
    reg signed [DW-1:0] x [0:NTAP-1];

    // ============================================================
    // 2. 并行乘法（组合），并符号扩展到累加器位宽 AW
    // ============================================================
    wire signed [DW+CW-1:0] p  [0:NTAP-1];
    wire signed [AW-1:0]    pe [0:NTAP-1];

    genvar g;
    generate
        for (g = 0; g < NTAP; g = g + 1) begin : g_mul
            assign p[g]  = x[g] * h[g];
            assign pe[g] = {{(AW-DW-CW){p[g][DW+CW-1]}}, p[g]};
        end
    endgenerate

    // ============================================================
    // 3. 加法树：每层的节点数
    //    81 → 41 → 21 → 11 → 6 → 3 → 2 → 1
    //    （NTAP=9 时是 9 → 5 → 3 → 2 → 1，多出来的层自动退化成直通）
    // ============================================================
    localparam L1 = (NTAP + 1) / 2;
    localparam L2 = (L1   + 1) / 2;
    localparam L3 = (L2   + 1) / 2;
    localparam L4 = (L3   + 1) / 2;
    localparam L5 = (L4   + 1) / 2;
    localparam L6 = (L5   + 1) / 2;
    localparam L7 = (L6   + 1) / 2;

    // ============================================================
    // 4. 流水线寄存器
    // ============================================================
    reg signed [AW-1:0] s1 [0:NTAP-1];      // S1：乘法结果
    reg signed [AW-1:0] r2 [0:L3-1];        // S2：加法树第 1~3 级之后
    reg signed [AW-1:0] r3 [0:L5-1];        // S3：加法树第 4~5 级之后
    reg signed [AW-1:0] r4;                 // S4：加法树第 6~7 级之后（只剩一个数）

    // en 的流水线：每一级寄存器的时钟使能都要跟着样本一起走，
    // 否则样本喂得不连续时，流水线各级会对不齐。
    reg [LAT-1:0] en_pipe;

    integer i;

    // ---- 系数写入 ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < NTAP; i = i + 1) h[i] <= {CW{1'b0}};
        end
        else if (coef_we) begin
            h[coef_idx] <= coef_din;
        end
    end

    // ---- 样本延迟线 ----
    // 注意：dout 用的是移位【前】的 x[]，这正是滤波需要的 x[n-k]。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < NTAP; i = i + 1) x[i] <= {DW{1'b0}};
        end
        else if (flush) begin
            for (i = 0; i < NTAP; i = i + 1) x[i] <= {DW{1'b0}};
        end
        else if (en) begin
            for (i = NTAP-1; i > 0; i = i - 1) x[i] <= x[i-1];
            x[0] <= din;
        end
    end

    // ---- en 打拍：给流水线各级当使能 ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            en_pipe <= {LAT{1'b0}};
        else if (flush)
            en_pipe <= {LAT{1'b0}};
        else
            en_pipe <= {en_pipe[LAT-2:0], en};
    end

    // ============================================================
    // 5. S1：乘法结果寄存
    // ============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < NTAP; i = i + 1) s1[i] <= {AW{1'b0}};
        end
        else if (flush) begin
            for (i = 0; i < NTAP; i = i + 1) s1[i] <= {AW{1'b0}};
        end
        else if (en) begin
            for (i = 0; i < NTAP; i = i + 1) s1[i] <= pe[i];
        end
    end

    // ============================================================
    // 6. 加法树（组合，7 级）
    // ============================================================
    wire signed [AW-1:0] n1 [0:L1-1];
    wire signed [AW-1:0] n2 [0:L2-1];
    wire signed [AW-1:0] n3 [0:L3-1];
    wire signed [AW-1:0] n4 [0:L4-1];
    wire signed [AW-1:0] n5 [0:L5-1];
    wire signed [AW-1:0] n6 [0:L6-1];
    wire signed [AW-1:0] n7 [0:L7-1];

    generate
        for (g = 0; g < L1; g = g + 1) begin : g_l1
            if (2*g + 1 < NTAP) assign n1[g] = s1[2*g] + s1[2*g+1];
            else                assign n1[g] = s1[2*g];
        end
        for (g = 0; g < L2; g = g + 1) begin : g_l2
            if (2*g + 1 < L1) assign n2[g] = n1[2*g] + n1[2*g+1];
            else              assign n2[g] = n1[2*g];
        end
        for (g = 0; g < L3; g = g + 1) begin : g_l3
            if (2*g + 1 < L2) assign n3[g] = n2[2*g] + n2[2*g+1];
            else              assign n3[g] = n2[2*g];
        end
        // 注意：第 4~5 级必须从【打拍后的 r2】出发，不能从 n3 出发，
        // 否则 r2 变成死逻辑，组合链会一路串到第 5 级，流水线就白打了。
        for (g = 0; g < L4; g = g + 1) begin : g_l4
            if (2*g + 1 < L3) assign n4[g] = r2[2*g] + r2[2*g+1];
            else              assign n4[g] = r2[2*g];
        end
        for (g = 0; g < L5; g = g + 1) begin : g_l5
            if (2*g + 1 < L4) assign n5[g] = n4[2*g] + n4[2*g+1];
            else              assign n5[g] = n4[2*g];
        end
        // 第 6~7 级从【打拍后的 r3】出发
        for (g = 0; g < L6; g = g + 1) begin : g_l6
            if (2*g + 1 < L5) assign n6[g] = r3[2*g] + r3[2*g+1];
            else              assign n6[g] = r3[2*g];
        end
        for (g = 0; g < L7; g = g + 1) begin : g_l7
            if (2*g + 1 < L6) assign n7[g] = n6[2*g] + n6[2*g+1];
            else              assign n7[g] = n6[2*g];
        end
    endgenerate

    // ============================================================
    // 7. S2 / S3 / S4：把加法树切成三段打拍
    // ============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < L3; i = i + 1) r2[i] <= {AW{1'b0}};
        end
        else if (flush) begin
            for (i = 0; i < L3; i = i + 1) r2[i] <= {AW{1'b0}};
        end
        else if (en_pipe[0]) begin
            for (i = 0; i < L3; i = i + 1) r2[i] <= n3[i];
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < L5; i = i + 1) r3[i] <= {AW{1'b0}};
        end
        else if (flush) begin
            for (i = 0; i < L5; i = i + 1) r3[i] <= {AW{1'b0}};
        end
        else if (en_pipe[1]) begin
            for (i = 0; i < L5; i = i + 1) r3[i] <= n5[i];
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)              r4 <= {AW{1'b0}};
        else if (flush)          r4 <= {AW{1'b0}};
        else if (en_pipe[2])     r4 <= n7[0];
    end

    // ============================================================
    // 8. S5：截位回 Q1.15 + 饱和 + 输出寄存
    // ============================================================
    wire signed [DW-1:0] y_trunc = r4[SHIFT+DW-1 : SHIFT];
    wire overflow = (r4[AW-1 : SHIFT+DW] != {{(AW-SHIFT-DW){r4[SHIFT+DW-1]}}});
    wire signed [DW-1:0] y_sat = overflow
                               ? (r4[AW-1] ? {1'b1, {DW-1{1'b0}}}
                                           : {1'b0, {DW-1{1'b1}}})
                               : y_trunc;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)              dout <= {DW{1'b0}};
        else if (flush)          dout <= {DW{1'b0}};
        else if (en_pipe[LAT-2]) dout <= y_sat;
    end

    // dout_v 用【组合】输出，不能用寄存器：
    // 如果写成 dout_v <= en_pipe[LAT-1]，它会比 dout 晚一拍拉高，
    // 下游就会在 dout_v 有效的那一拍读到"下一个"数据（整体错位）。
    // 组合输出保证 dout_v=1 的那一拍，dout 正好是它标记的那个结果。
    assign dout_v = en_pipe[LAT-1];

endmodule

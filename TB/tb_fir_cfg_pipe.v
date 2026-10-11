// ============================================================
// tb_fir_cfg_pipe.v —— 流水线版 fir_cfg 的单元验证
//
// 验证三件事：
//   1) 流水线延迟确实是 LAT 拍（en 拉高一次，数到 dout_v 拉高）
//   2) flush 之后流水线被清干净（不会漏出旧数据）
//   3) 与软件黄金模型【逐位一致】（这是赛题误差 <0.1% 的最强形式）
//
// 数据来源（都在本实验目录下，由 gen_fir_vectors.py 生成）：
//   coeffs.hex  —— 81 个 Q1.15 系数（TB 通过 coef_idx/coef_din/coef_we 写进去，
//                  而不是 `include，因为本模块的卖点就是"系数可配置"）
//   stim.hex    —— 测试激励
//   exp.hex     —— 黄金模型算出的期望输出
// ============================================================
`timescale 1ns/1ps

module tb_fir_cfg_pipe;

    localparam DW    = 16;
    localparam CW    = 16;
    localparam AW    = 40;
    localparam NTAP  = 81;
    localparam LAT   = 5;                       // 和 fir_cfg.v 里的 LAT 保持一致
    localparam NSAMP = 256;
    localparam NEXP  = NSAMP + NTAP - 1;        // 全卷积长度 = 336

    reg  clk = 0;
    reg  rst_n = 0;
    reg  en = 0;
    reg  flush = 0;
    reg  signed [DW-1:0] din = 0;

    wire signed [DW-1:0] dout;
    wire                 dout_v;

    reg  [$clog2(NTAP)-1:0] coef_idx = 0;
    reg  signed [CW-1:0]    coef_din = 0;
    reg                     coef_we  = 0;

    fir_cfg #(.DW(DW), .CW(CW), .AW(AW), .NTAP(NTAP)) dut (
        .clk(clk), .rst_n(rst_n),
        .en(en), .flush(flush), .din(din),
        .dout(dout), .dout_v(dout_v),
        .coef_idx(coef_idx), .coef_din(coef_din), .coef_we(coef_we)
    );

    reg signed [CW-1:0] coeffs [0:NTAP-1];
    reg signed [DW-1:0] stim   [0:NSAMP-1];
    reg signed [DW-1:0] exp    [0:NEXP-1];
    reg signed [DW-1:0] got    [0:NEXP+16];

    integer cap    = 0;
    integer errors = 0;
    integer checks = 0;
    integer m, i;
    integer lat_cnt;

    always #5 clk = ~clk;                       // 100 MHz

    // ---- 逐拍追踪（只在 test[1] 打开）----
    reg trace_on = 0;
    integer tr_cnt = 0;
    always @(posedge clk) begin
        if (tr_cnt >= 1 && tr_cnt <= 14) begin
            $display("   [T3] t=%0t en=%b pipe=%b dout_v=%b dout=%0d x0=%0d x1=%0d x2=%0d cap=%0d",
                     $time, en, dut.en_pipe, dout_v, dout,
                     dut.x[0], dut.x[1], dut.x[2], cap);
            tr_cnt = tr_cnt + 1;
        end
    end
    always @(posedge clk) begin
        if (trace_on)
            $display("   [TR] t=%0t en=%b pipe=%b dout_v=%b dout=%0d s1_40=%0d r2_10=%0d r3_2=%0d r4=%0d",
                     $time, en, dut.en_pipe, dout_v, dout,
                     dut.s1[40], dut.r2[10], dut.r3[2], dut.r4);
    end

    // ---- 采集 DUT 输出 ----
    always @(posedge clk) begin
        if (rst_n && dout_v && (cap <= NEXP + 8)) begin
            got[cap] = dout;
            cap      = cap + 1;
        end
    end

    task chk;
        input [31:0]  got_v;
        input [31:0]  exp_v;
        input [255:0] name;
        begin
            checks = checks + 1;
            if (got_v !== exp_v) begin
                errors = errors + 1;
                $display("  [FAIL] %0s : got=%0d 期望=%0d", name, got_v, exp_v);
            end
        end
    endtask

    initial begin
        $dumpfile("tb_fir_cfg_pipe.vcd");
        $dumpvars(0, tb_fir_cfg_pipe);

        $readmemh("coeffs.hex", coeffs);
        $readmemh("stim.hex",   stim);
        $readmemh("exp.hex",    exp);

        for (i = 0; i <= NEXP + 16; i = i + 1) got[i] = {DW{1'b0}};

        // ---- 复位 ----
        repeat (4) @(posedge clk);
        @(negedge clk); rst_n = 1;
        repeat (2) @(posedge clk);

        $display("");
        $display("========== 流水线版 fir_cfg 单元测试 ==========");

        // ----------------------------------------------------
        // 0) 写系数（通过可配置端口，不是 `include）
        // ----------------------------------------------------
        $display("[0] 通过 coef 端口写入 %0d 个系数", NTAP);
        for (i = 0; i < NTAP; i = i + 1) begin
            @(negedge clk);
            coef_idx = i[$clog2(NTAP)-1:0];
            coef_din = coeffs[i];
            coef_we  = 1'b1;
        end
        @(negedge clk); coef_we = 1'b0;
        repeat (2) @(posedge clk);

        // ----------------------------------------------------
        // 1) 测流水线延迟：只喂一个样本，数 dout_v 第几拍来
        // ----------------------------------------------------
        $display("[1] 测流水线延迟（期望 LAT=%0d 拍）", LAT);
        @(negedge clk); flush = 1'b1;
        @(negedge clk); flush = 1'b0;
        repeat (2) @(posedge clk);

        trace_on = 1'b0;      // 改成 1'b1 可以打印逐拍时序
        @(negedge clk); en = 1'b1; din = 16'sd1000;
        @(negedge clk); en = 1'b0; din = 0;

        lat_cnt = 0;
        while (dout_v !== 1'b1 && lat_cnt < 50) begin
            @(posedge clk);
            lat_cnt = lat_cnt + 1;
        end
        trace_on = 1'b0;
        // 从 en 拉高的那一拍到 dout_v 拉高，中间隔了 LAT 拍
        chk(lat_cnt, LAT, "流水线延迟拍数");

        // ----------------------------------------------------
        // 2) flush 之后流水线应该是干净的
        // ----------------------------------------------------
        $display("[2] flush 清流水线：清完 LAT 拍内不应有 dout_v");
        @(negedge clk); flush = 1'b1;
        @(negedge clk); flush = 1'b0;
        // 把之前可能残留的结果排空
        repeat (LAT + 2) @(posedge clk);
        cap = 0;
        repeat (LAT) @(posedge clk);
        chk(cap, 0, "flush 后不应再输出结果");

        // ----------------------------------------------------
        // 3) 全量回归：256 个样本 vs 黄金模型逐位比对
        // ----------------------------------------------------
        $display("[3] 全量回归：%0d 个样本 vs 黄金模型", NSAMP);
        @(negedge clk); flush = 1'b1;
        @(negedge clk); flush = 1'b0;
        repeat (2) @(posedge clk);
        cap = 0;

        @(negedge clk); en = 1'b1;
        tr_cnt = 0;           // 改成 1 可以打印喂数据前 14 拍
        for (m = 0; m < NSAMP; m = m + 1) begin
            din = stim[m];
            @(negedge clk);
        end
        // 排空延迟线和流水线
        din = 0;
        repeat (NTAP + LAT + 8) @(negedge clk);

        $display("     采集到 %0d 个输出，黄金模型期望 %0d 个", cap, NEXP);
        $display("     前 8 个采集值 got[0..7] = %0d %0d %0d %0d %0d %0d %0d %0d",
                 got[0],got[1],got[2],got[3],got[4],got[5],got[6],got[7]);
        $display("     黄金模型     exp[0..7] = %0d %0d %0d %0d %0d %0d %0d %0d",
                 exp[0],exp[1],exp[2],exp[3],exp[4],exp[5],exp[6],exp[7]);
        $display("     激励         stim[0..3] = %0d %0d %0d %0d",
                 stim[0],stim[1],stim[2],stim[3]);
        $display("     系数         h[0..3]   = %0d %0d %0d %0d",
                 coeffs[0],coeffs[1],coeffs[2],coeffs[3]);
        for (i = 0; i < NEXP; i = i + 1) begin
            if (got[i+1] !== exp[i]) begin
                errors = errors + 1;
                if (errors <= 10)
                    $display("  [MISMATCH] 第 %0d 个样本: RTL = %0d, 参考 = %0d",
                             i, got[i+1], exp[i]);
            end
        end
        checks = checks + 1;

        $writememh("got.hex", got);

        $display("");
        $display("============================================");
        if (errors == 0)
            $display("===== PASS: %0d 项检查通过，%0d 个样本与黄金模型逐位一致 =====", checks, NEXP);
        else
            $display("===== FAIL: %0d 个错误（含延迟/flush 检查）=====", errors);
        $display("============================================");
        $finish;
    end

    initial begin
        #500000;
        $display("!!!! TIMEOUT：仿真超时");
        $finish;
    end

endmodule

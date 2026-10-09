// ============================================================
// 实验 05 的 testbench —— 自校验 + 与软件黄金模型逐位比对
//
// 数据流：
//   gen_fir_vectors.py  --生成-->  stim.hex（激励）
//                                  exp.hex （黄金模型期望输出）
//                                        |
//   tb_fir.v  --$readmemh 读入--> 喂给 fir  --采集--> got 数组
//                                        |
//                            与 exp 逐位比对 --> PASS / FAIL
//                                        |
//                              $writememh 导出 got.hex
//                                        |
//   python gen_fir_vectors.py --check got.hex   （Python 侧二次确认）
//
// 这个"RTL vs 软件参考模型"的双向比对，就是赛题要求的
// "FIR 滤波结果与相关软件算法参考值误差 < 0.1%" 的做法。
// 我们这个做法更严格：要求逐位一致。
// ============================================================
`timescale 1ns/1ps

module tb_fir;

    localparam DW    = 16;
    localparam CW    = 16;
    localparam AW    = 40;
    localparam NTAP  = 81;
    localparam NSAMP = 256;                     // 激励样本数
    localparam NEXP  = NSAMP + NTAP - 1;        // 全卷积长度 = 336

    reg  clk   = 0;
    reg  rst_n = 0;
    reg  en    = 0;
    reg  signed [DW-1:0] din = 0;

    wire signed [DW-1:0] dout;
    wire                 dout_v;

    reg signed [DW-1:0] stim [0:NSAMP-1];
    reg signed [DW-1:0] exp  [0:NEXP-1];
    reg signed [DW-1:0] got  [0:NEXP+8];        // 多留几个位置放拖尾

    integer cap    = 0;
    integer m, i;
    integer errors = 0;

    fir #(.DW(DW), .CW(CW), .AW(AW), .NTAP(NTAP)) dut (
        .clk(clk), .rst_n(rst_n), .en(en), .din(din),
        .dout(dout), .dout_v(dout_v)
    );

    always #5 clk = ~clk;                       // 100 MHz

    // ---- 采集 DUT 输出 ----
    // 在 posedge 读到的是"上一拍结束时稳定下来"的值，不会有竞争
    always @(posedge clk) begin
        if (rst_n && dout_v && (cap <= NEXP + 8)) begin
            got[cap] = dout;
            cap     = cap + 1;
        end
    end

    initial begin
        $dumpfile("tb_fir.vcd");
        $dumpvars(0, tb_fir);

        $readmemh("stim.hex", stim);
        $readmemh("exp.hex",  exp);

        // 先把 got 全部清零：否则 $writememh 会把没赋值的项写成 xxxx，
        // 后面 Python 读 got.hex 就会报错
        for (i = 0; i <= NEXP + 8; i = i + 1)
            got[i] = {DW{1'b0}};

        // 复位
        repeat (4) @(posedge clk);
        @(negedge clk);
        rst_n = 1;
        en    = 1;

        // ---- 把 NSAMP 个样本一个一拍喂进去 ----
        for (m = 0; m < NSAMP; m = m + 1) begin
            din = stim[m];
            @(negedge clk);
        end

        // ---- 继续打拍，把延迟线里剩下的样本"排空" ----
        din = 0;
        repeat (NTAP + 8) @(negedge clk);

        // ---- 比对 ----
        // DUT 比黄金模型多 1 拍流水线前导，所以 got[0] 恒为 0，从 got[1] 开始比
        $display("采集到 %0d 个输出，黄金模型期望 %0d 个", cap, NEXP);
        $display("前 5 个样本对比（索引: RTL / 参考）:");
        for (i = 0; i < 5; i = i + 1)
            $display("   %0d: %0d / %0d", i, got[i+1], exp[i]);
        $display("");

        for (i = 0; i < NEXP; i = i + 1) begin
            if (got[i+1] !== exp[i]) begin
                errors = errors + 1;
                if (errors <= 10)
                    $display("[MISMATCH] 第 %0d 个样本: RTL = %0d, 参考 = %0d",
                             i, got[i+1], exp[i]);
            end
        end

        $writememh("got.hex", got);

        if (errors == 0)
            $display("\n===== PASS: %0d 个样本与软件黄金模型逐位一致 =====\n", NEXP);
        else
            $display("\n===== FAIL: %0d / %0d 个样本不一致 =====\n", errors, NEXP);

        $finish;
    end

endmodule

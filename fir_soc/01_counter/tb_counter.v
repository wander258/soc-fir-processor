// ============================================================
// 实验 01 的 testbench（自校验）
//
// testbench 的特点：
//   - 不是硬件，不需要综合，可以随便用 #延时 / initial / $display
//   - 负责产生时钟和激励，然后检查 DUT 的输出对不对
//   - 检查结果用 !== 而不是 != （!== 能把 X 态也判为不相等，更容易发现 bug）
// ============================================================
`timescale 1ns/1ps

module tb_counter;

    reg  clk   = 0;
    reg  rst_n = 0;
    reg  en    = 0;
    wire [3:0] cnt;
    wire       tick;

    integer errors = 0;
    integer i;

    // ---- 例化被测模块（DUT = Device Under Test）----
    counter #(.WIDTH(4)) dut (
        .clk   (clk),
        .rst_n (rst_n),
        .en    (en),
        .cnt   (cnt),
        .tick  (tick)
    );

    // ---- 产生时钟：每 5ns 翻转一次 => 周期 10ns => 100MHz ----
    always #5 clk = ~clk;

    initial begin
        // 这 2 行生成波形文件，后面用 GTKWave 打开
        $dumpfile("tb_counter.vcd");
        $dumpvars(0, tb_counter);

        // ---------- 检查 1：复位后计数器必须是 0 ----------
        repeat (3) @(posedge clk);
        if (cnt !== 4'd0) begin
            errors = errors + 1;
            $display("[FAIL] 复位后 cnt = %0d，期望 0", cnt);
        end else begin
            $display("[ OK ] 复位后 cnt = 0");
        end

        // ---------- 检查 2：使能 20 拍后应该是 20 % 16 = 4 ----------
        @(negedge clk);  rst_n = 1;
        @(negedge clk);  en    = 1;

        for (i = 0; i < 20; i = i + 1) begin
            @(negedge clk);          // 在下降沿采样，避开建立/保持的竞争
            $display("  第 %2d 拍: cnt = %2d  tick = %b", i + 1, cnt, tick);
        end

        if (cnt !== 4'd4) begin
            errors = errors + 1;
            $display("[FAIL] 计数 20 拍后 cnt = %0d，期望 4", cnt);
        end else begin
            $display("[ OK ] 计数 20 拍后 cnt = 4（正确回绕）");
        end

        // ---------- 汇总 ----------
        if (errors == 0) $display("\n===== PASS: 实验 01 全部通过 =====\n");
        else             $display("\n===== FAIL: %0d 项不通过 =====\n", errors);

        $finish;
    end

endmodule

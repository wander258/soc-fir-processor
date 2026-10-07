// ============================================================
// 实验 03 的 testbench
//
// 重点检查【负数】。初学者写的乘法器基本都在负数上翻车：
//   - 忘了声明 signed，乘法就变成了无符号乘
//   - 位宽扩展时补 0 而不是补符号位
// 这个 TB 专门用 4 组用例把这些坑都踩一遍。
//
// 驱动和检查都放在时钟下降沿，彻底避开仿真竞争。
// ============================================================
`timescale 1ns/1ps

module tb_mac;

    localparam DW = 16;
    localparam AW = 40;

    reg  clk   = 0;
    reg  rst_n = 0;
    reg  en    = 0;
    reg  clr   = 0;
    reg  signed [DW-1:0] a = 0;
    reg  signed [DW-1:0] b = 0;
    wire signed [AW-1:0] acc;

    integer errors = 0;

    mac #(.DW(DW), .AW(AW)) dut (
        .clk(clk), .rst_n(rst_n), .en(en), .clr(clr),
        .a(a), .b(b), .acc(acc)
    );

    always #5 clk = ~clk;

    // ---- 累加一次 ----
    task do_mac(input signed [DW-1:0] av, input signed [DW-1:0] bv);
        begin
            a = av;  b = bv;  en = 1;  clr = 0;
            @(negedge clk);
        end
    endtask

    // ---- 清零累加器 ----
    task do_clr;
        begin
            en = 0;  clr = 1;
            @(negedge clk);
            clr = 0;
        end
    endtask

    // ---- 检查结果 ----
    task expect_acc(input signed [AW-1:0] want, input [8*40-1:0] name);
        begin
            if (acc !== want) begin
                errors = errors + 1;
                $display("[FAIL] %0s -> acc = %0d, 期望 %0d", name, acc, want);
            end else begin
                $display("[ OK ] %0s -> acc = %0d", name, acc);
            end
        end
    endtask

    initial begin
        $dumpfile("tb_mac.vcd");
        $dumpvars(0, tb_mac);

        repeat (3) @(posedge clk);
        @(negedge clk);  rst_n = 1;

        // ---------- 用例 1：正数累加 3 次 ----------
        do_clr;
        do_mac(16'sd1000, 16'sd1000);
        do_mac(16'sd1000, 16'sd1000);
        do_mac(16'sd1000, 16'sd1000);
        expect_acc(40'sd3000000, "3 x (1000 * 1000)");

        // ---------- 用例 2：负数 x 正数 ----------
        do_clr;
        do_mac(-16'sd1000, 16'sd1000);
        expect_acc(-40'sd1000000, "(-1000) * 1000");

        // ---------- 用例 3：两个最大正数，累加 3 次 ----------
        // 32767 * 32767 = 1,073,676,289，已经超过 32 位有符号的直观感受，
        // 但它本身仍在 32 位内；累加 3 次 = 3,221,028,867，只有 40 位装得下
        do_clr;
        do_mac(16'sd32767, 16'sd32767);
        do_mac(16'sd32767, 16'sd32767);
        do_mac(16'sd32767, 16'sd32767);
        expect_acc(40'sd3221028867, "3 x (32767 * 32767)");

        // ---------- 用例 4：最负 x 最大正 ----------
        // 16'sh8000 就是 -32768（16 位补码的最小值）
        // (-32768) * 32767 = -1,073,709,056
        do_clr;
        do_mac(16'sh8000, 16'sd32767);
        expect_acc(-40'sd1073709056, "(-32768) * 32767");

        if (errors == 0) $display("\n===== PASS: 实验 03 全部通过（有符号算术正确）=====\n");
        else             $display("\n===== FAIL: %0d 项不通过 =====\n", errors);

        $finish;
    end

endmodule

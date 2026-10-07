// ============================================================
// 实验 02 的 testbench
//
// 做法：喂进 1,2,3,4,5,6,7,8 这 8 个数，TAPS=4，那么数完第 8 拍时：
//     z[0] = 8, z[1] = 7, z[2] = 6, z[3] = 5
//   即 d0 = 8，dout = 5（最老的）
// 这个"喂已知序列 → 检查延迟"的套路，就是后面验证 FIR 的同一套路。
// ============================================================
`timescale 1ns/1ps

module tb_delay_line;

    localparam WIDTH = 8;
    localparam TAPS  = 4;

    reg  clk   = 0;
    reg  rst_n = 0;
    reg  en    = 0;
    reg  signed [WIDTH-1:0] din = 0;

    wire signed [WIDTH-1:0] d0;
    wire signed [WIDTH-1:0] dout;

    integer errors = 0;
    integer m;

    delay_line #(.WIDTH(WIDTH), .TAPS(TAPS)) dut (
        .clk   (clk),
        .rst_n (rst_n),
        .en    (en),
        .din   (din),
        .d0    (d0),
        .dout  (dout)
    );

    always #5 clk = ~clk;

    initial begin
        $dumpfile("tb_delay_line.vcd");
        $dumpvars(0, tb_delay_line);

        // 复位
        repeat (3) @(posedge clk);
        @(negedge clk);  rst_n = 1;
        @(negedge clk);  en    = 1;

        // 依次喂入 1..8，每个数保持一个时钟周期
        for (m = 1; m <= 8; m = m + 1) begin
            din = m;                    // integer 自动截断成 8 位
            @(negedge clk);
            $display("  喂入 din = %0d  ->  d0 = %0d, dout = %0d", m, d0, dout);
        end

        // 此刻延迟线里应该是 8,7,6,5
        if (d0 !== 8'sd8) begin
            errors = errors + 1;
            $display("[FAIL] d0 = %0d，期望 8", d0);
        end else begin
            $display("[ OK ] d0   = 8（最新样本）");
        end

        if (dout !== 8'sd5) begin
            errors = errors + 1;
            $display("[FAIL] dout = %0d，期望 5（第 4 老的样本）", dout);
        end else begin
            $display("[ OK ] dout = 5（延迟了 %0d 拍）", TAPS - 1);
        end

        if (errors == 0) $display("\n===== PASS: 实验 02 全部通过 =====\n");
        else             $display("\n===== FAIL: %0d 项不通过 =====\n", errors);

        $finish;
    end

endmodule

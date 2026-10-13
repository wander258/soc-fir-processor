// ============================================================
// tb_axi_id_check.v —— 契约C 检查器的自测台
//
// 目的：证明 axi_id_contract_check 不是摆设
//   T0  先喂【完全合法】的 ID 编码，必须 0 错误（防误报）
//   T1~T4 逐条制造违规，必须全部被抓到（防漏报）
//
// 运行：
//   iverilog -g2012 -o sim.out TB/axi_id_contract_check.v TB/tb_axi_id_check.v
//   vvp sim.out
// ============================================================
`timescale 1ns/1ps

module tb_axi_id_check;

    localparam ID_W = 4;
    localparam NCH  = 6;

    reg clk = 0;
    reg rst_n = 0;

    reg [ID_W-1:0] awid = 0;
    reg            awvalid = 0, awready = 1;
    reg [ID_W-1:0] bid = 0;
    reg            bvalid = 0, bready = 1;
    reg [ID_W-1:0] arid = 0;
    reg            arvalid = 0, arready = 1;
    reg [ID_W-1:0] rid = 0;
    reg            rvalid = 0, rready = 1;

    wire [31:0] error_count;

    axi_id_contract_check #(
        .ID_W(ID_W), .NCH(NCH), .DMA_TAG(1'b1), .NAME("tb_id")
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .awid(awid), .awvalid(awvalid), .awready(awready),
        .bid(bid),   .bvalid(bvalid),   .bready(bready),
        .arid(arid), .arvalid(arvalid), .arready(arready),
        .rid(rid),   .rvalid(rvalid),   .rready(rready),
        .error_count(error_count)
    );

    always #5 clk = ~clk;          // 100 MHz

    integer checks = 0;
    integer errors = 0;

    task do_reset;
        begin
            @(negedge clk);
            awvalid=0; bvalid=0; arvalid=0; rvalid=0;
            rst_n = 0;
            repeat (3) @(posedge clk);
            @(negedge clk); rst_n = 1;
            repeat (2) @(posedge clk);
        end
    endtask

    task expect_zero;
        input [255:0] name;
        begin
            checks = checks + 1;
            if (error_count !== 0) begin
                errors = errors + 1;
                $display("  [FAIL] %0s : 期望 0 个错误，实际 %0d 个", name, error_count);
            end else
                $display("  [ OK ] %0s : 0 个错误", name);
        end
    endtask

    task expect_at_least;
        input integer want;
        input [255:0] name;
        begin
            checks = checks + 1;
            if (error_count < want) begin
                errors = errors + 1;
                $display("  [FAIL] %0s : 期望至少 %0d 个错误，实际 %0d 个（漏报了！）", name, want, error_count);
            end else
                $display("  [ OK ] %0s : 抓到 %0d 个错误", name, error_count);
        end
    endtask

    // 一次合法的 ID 事务（通道 ch，tag 位固定 1）
    task legal_id;
        input [2:0] ch;
        begin
            @(negedge clk);
            awid = {ch, 1'b1}; awvalid = 1; awready = 1;
            @(negedge clk); awvalid = 0;
            @(negedge clk);
            arid = {ch, 1'b1}; arvalid = 1; arready = 1;
            @(negedge clk); arvalid = 0;
            @(negedge clk);
        end
    endtask

    initial begin
        $dumpfile("tb_axi_id_check.vcd");
        $dumpvars(0, tb_axi_id_check);

        repeat (4) @(posedge clk);

        $display("");
        $display("========== 契约C（AXI ID 编码）检查器 自测 ==========");
        $display("");

        // ----------------------------------------------------
        // T0：合法编码 —— 6 个通道全部发一遍，必须 0 错误
        // ----------------------------------------------------
        $display("[T0] 合法编码：6 个通道各发一次 AW + AR");
        do_reset;
        legal_id(3'd0);
        legal_id(3'd1);
        legal_id(3'd2);
        legal_id(3'd3);
        legal_id(3'd4);
        legal_id(3'd5);
        repeat (4) @(posedge clk);
        expect_zero("T0 合法编码不误报");

        // ----------------------------------------------------
        // T1：C1 —— AWID 最低位不是 1
        // ----------------------------------------------------
        $display("[T1] C1 违规：AWID 最低位 = 0");
        do_reset;
        @(negedge clk); awid = 4'b0010; awvalid = 1; awready = 1;   // tag 位 = 0
        @(negedge clk); awvalid = 0;
        repeat (3) @(posedge clk);
        expect_at_least(1, "T1 抓到 AWID tag 位错");

        // ----------------------------------------------------
        // T2：C2 —— ARID 最低位不是 1
        // ----------------------------------------------------
        $display("[T2] C2 违规：ARID 最低位 = 0");
        do_reset;
        @(negedge clk); arid = 4'b0100; arvalid = 1; arready = 1;   // tag 位 = 0
        @(negedge clk); arvalid = 0;
        repeat (3) @(posedge clk);
        expect_at_least(1, "T2 抓到 ARID tag 位错");

        // ----------------------------------------------------
        // T3：C3 —— AWID 通道号越界（7 >= 6）
        // ----------------------------------------------------
        $display("[T3] C3 违规：AWID 通道号 = 7（越界，只有 0~5）");
        do_reset;
        @(negedge clk); awid = 4'b1111; awvalid = 1; awready = 1;   // ch=7, tag=1
        @(negedge clk); awvalid = 0;
        repeat (3) @(posedge clk);
        expect_at_least(1, "T3 抓到 AWID 通道号越界");

        // ----------------------------------------------------
        // T4：C4 —— ARID 通道号越界（6 >= 6）
        // ----------------------------------------------------
        $display("[T4] C4 违规：ARID 通道号 = 6（越界）");
        do_reset;
        @(negedge clk); arid = 4'b1101; arvalid = 1; arready = 1;   // ch=6, tag=1
        @(negedge clk); arvalid = 0;
        repeat (3) @(posedge clk);
        expect_at_least(1, "T4 抓到 ARID 通道号越界");

        // ----------------------------------------------------
        $display("");
        $display("=========================================================");
        if (errors == 0)
            $display("===== PASS: 自测 %0d 项全部通过（不误报、不漏报）=====", checks);
        else
            $display("===== FAIL: %0d 项检查中 %0d 项不通过 =====", checks, errors);
        $display("=========================================================");
        $finish;
    end

    initial begin
        #200000;
        $display("!!!! TIMEOUT：仿真超时");
        $finish;
    end

endmodule

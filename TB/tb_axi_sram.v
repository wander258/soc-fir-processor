// ============================================================
// 实验 06 的 testbench —— AXI-Lite 主设备模型（BFM）+ SRAM 读写验证
//
// 这个文件扮演"CPU"的角色（只不过是一段测试代码，不是真 CPU）：
//   它用 AXI-Lite 五通道握手，向 SRAM 写几个数、再读回来、逐一对。
//
// 你要重点看懂两个 task：
//   axi_write(a, d) —— 通过 AW/W/B 三个通道完成一次写
//   axi_read (a)    —— 通过 AR/R 两个通道完成一次读
// 这俩 task 就是后面实验里"CPU 怎么操作 FIR/UART"的全部秘密。
// ============================================================
`timescale 1ns/1ps

module tb_axi_sram;

    localparam ADDR_W = 32;
    localparam DATA_W = 32;

    reg clk   = 0;
    reg rst_n = 0;

    // ---- 主设备侧信号（由 BFM 驱动）----
    reg  [ADDR_W-1:0]    awaddr, araddr;
    reg                  awvalid, arvalid;
    reg  [DATA_W-1:0]    wdata;
    reg  [DATA_W/8-1:0]  wstrb;
    reg                  wvalid;
    reg                  bready, rready;

    // ---- 从设备侧信号（由 axi_lite_sram 驱动）----
    wire                 awready, wready, arready, rvalid, bvalid;
    wire [DATA_W-1:0]    rdata;
    wire [1:0]           bresp, rresp;

    axi_lite_sram #(.ADDR_W(ADDR_W), .DATA_W(DATA_W), .DEPTH(1024)) dut (
        .clk(clk), .rst_n(rst_n),
        .awaddr(awaddr), .awvalid(awvalid), .awready(awready),
        .wdata(wdata),   .wstrb(wstrb),     .wvalid(wvalid), .wready(wready),
        .bresp(bresp),   .bvalid(bvalid),   .bready(bready),
        .araddr(araddr), .arvalid(arvalid), .arready(arready),
        .rdata(rdata),   .rresp(rresp),     .rvalid(rvalid), .rready(rready)
    );

    always #5 clk = ~clk;                       // 100 MHz

    // ============================================================
    // AXI-Lite 主设备模型（BFM）：两个 task
    // ============================================================
    reg [DATA_W-1:0] rd_data;

    // ---- 写一次（地址 a，数据 d）----
    //
    // 关键细节：握手完成那一拍，要用"非阻塞赋值 <= "撤 valid，而不是阻塞赋值 =。
    // 原因：非阻塞赋值在 NBA 区生效，晚于从设备在 active 区对 valid 的采样，
    // 这样从设备一定能看到 valid=1 并正确接收；用 = 则可能抢在采样前把 valid 清零。
    task axi_write(input [ADDR_W-1:0] a, input [DATA_W-1:0] d);
        begin
            awaddr = a; awvalid = 1;
            wdata  = d; wstrb  = 4'hF; wvalid = 1;
            wait (awready && wready);   // 等从设备能同时收地址和数据
            @(posedge clk);             // 这个上升沿完成握手
            awvalid <= 0; wvalid <= 0;  // NBA 区撤 valid

            bready = 1;
            wait (bvalid);              // 等写响应
            @(posedge clk);             // 完成响应握手
            bready <= 0;
        end
    endtask

    // ---- 读一次（地址 a，结果放进 d）----
    task axi_read(input [ADDR_W-1:0] a, output [DATA_W-1:0] d);
        begin
            araddr = a; arvalid = 1;
            wait (arready);
            @(posedge clk);
            arvalid <= 0;

            rready = 1;
            wait (rvalid);
            @(posedge clk);
            d = rdata;
            rready <= 0;
        end
    endtask

    // ============================================================
    // 测试流程
    // ============================================================
    integer errors;
    integer k;
    reg [DATA_W-1:0] got;

    // 兜底超时：万一哪里卡住，20us 后强制结束并打印，方便定位
    initial begin
        #20000;
        $display("!!!! TIMEOUT at %0t, bvalid=%0b awready=%0b wready=%0b rvalid=%0b",
                 $time, bvalid, awready, wready, rvalid);
        $finish;
    end

    initial begin
        $dumpfile("tb_axi_sram.vcd");
        $dumpvars(0, tb_axi_sram);

        awvalid = 0; wvalid = 0; arvalid = 0; bready = 0; rready = 0;
        awaddr  = 0; wdata = 0; wstrb = 0; araddr = 0;

        // 复位
        repeat (4) @(posedge clk);
        @(negedge clk);
        rst_n = 1;
        @(posedge clk);

        errors = 0;

        // 1) 写一批"地址 = 数据"的值
        for (k = 0; k < 16; k = k + 1)
            axi_write(k * 4, k * 16'h1000 + k);

        // 2) 读回来逐一比对
        for (k = 0; k < 16; k = k + 1) begin
            axi_read(k * 4, got);
            if (got !== (k * 16'h1000 + k)) begin
                errors = errors + 1;
                $display("[FAIL] 地址 %0d: 读到 %08x，期望 %08x",
                         k * 4, got, k * 16'h1000 + k);
            end
        end

        // 3) 验证按字节写使能 wstrb（只改低字节）
        axi_write(0, 32'hDEAD_BEEF);       // 先整体写一个值
        axi_read(0, got);
        $display("整字写后 0x0 = %08x", got);

        // 只写低字节（wstrb=0001）
        begin
            awaddr = 0; awvalid = 1;
            wdata  = 32'h0000_00A5; wstrb = 4'b0001; wvalid = 1;
            wait (awready && wready); @(posedge clk);
            awvalid = 0; wvalid = 0;
            bready = 1; wait (bvalid); @(posedge clk); bready = 0;
        end
        axi_read(0, got);
        if (got !== 32'hDEAD_BEA5) begin
            errors = errors + 1;
            $display("[FAIL] 字节写后 0x0 = %08x，期望 deadbea5", got);
        end else
            $display("字节写后 0x0 = %08x (低字节被改成 a5)", got);

        // ---- 结论 ----
        if (errors == 0)
            $display("\n===== PASS: AXI-Lite 读写、按字节写使能全部正确 =====");
        else
            $display("\n===== FAIL: %0d 个错误 =====", errors);

        $finish;
    end

endmodule

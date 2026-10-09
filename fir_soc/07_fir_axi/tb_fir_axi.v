// ============================================================
// 实验 07 的 testbench —— 把 FIR 当成"总线外设"来用，端到端验证
//
// 数据流：
//   gen_fir_vectors.py 生成 coeffs.hex / stim.hex / exp.hex
//        |
//   本 TB：主设备模型(BFM) 通过 AXI-Lite 总线
//         1) 写系数到 COEF[0..NTAP-1]
//         2) 写 CTRL 的 START 清空
//         3) 写样本到 DIN（一个样本一拍）
//         4) 写 NTAP 个 0 把延迟线"排空"（得到完整的卷积拖尾）
//         5) 读 DOUT 取结果
//         6) 与 exp.hex 的软件黄金模型逐位比对
//
// 这就是赛题"软硬协同验证"里，CPU 一侧要做的事（在真系统里由 C 驱动做）。
// ============================================================
`timescale 1ns/1ps

module tb_fir_axi;

    localparam ADDR_W = 32;
    localparam DATA_W = 32;
    localparam DW      = 16;
    localparam CW      = 16;
    localparam AW      = 40;
    parameter  NTAP    = 9;              // 抽头数：9（调试）/ 81（赛题），可用 -P 覆盖
    parameter  NSAMP   = 64;             // 激励样本数，可用 -P 覆盖
    localparam NEXP    = NSAMP + NTAP - 1;

    // 寄存器地址（必须和 fir_axi.v 里一致）
    localparam ADDR_CTRL   = 32'h000;
    localparam ADDR_DIN    = 32'h004;
    localparam ADDR_DOUT   = 32'h008;
    localparam ADDR_STATUS = 32'h00C;
    localparam COEF_BASE   = 32'h100;

    reg clk   = 0;
    reg rst_n = 0;

    // ---- 主设备信号 ----
    reg  [ADDR_W-1:0]   awaddr, araddr;
    reg                 awvalid, arvalid;
    reg  [DATA_W-1:0]   wdata;
    reg  [DATA_W/8-1:0] wstrb;
    reg                 wvalid;
    reg                 bready, rready;
    wire                awready, wready, arready, rvalid, bvalid;
    wire [DATA_W-1:0]   rdata;
    wire [1:0]          bresp, rresp;

    fir_axi #(.ADDR_W(ADDR_W), .DATA_W(DATA_W),
              .DW(DW), .CW(CW), .AW(AW), .NTAP(NTAP)) dut (
        .clk(clk), .rst_n(rst_n),
        .awaddr(awaddr), .awvalid(awvalid), .awready(awready),
        .wdata(wdata),   .wstrb(wstrb),     .wvalid(wvalid), .wready(wready),
        .bresp(bresp),   .bvalid(bvalid),   .bready(bready),
        .araddr(araddr), .arvalid(arvalid), .arready(arready),
        .rdata(rdata),   .rresp(rresp),     .rvalid(rvalid), .rready(rready)
    );

    always #5 clk = ~clk;                        // 100 MHz

    // ============================================================
    // 主设备模型（BFM）
    // ============================================================
    reg [DATA_W-1:0] rd_data;

    task axi_write(input [ADDR_W-1:0] a, input [DATA_W-1:0] d);
        begin
            awaddr = a; awvalid = 1;
            wdata  = d; wstrb  = 4'hF; wvalid = 1;
            wait (awready && wready);
            @(posedge clk);
            awvalid <= 0; wvalid <= 0;
            bready = 1;
            wait (bvalid);
            @(posedge clk);
            bready <= 0;
        end
    endtask

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
    // 测试数组
    // ============================================================
    reg signed [CW-1:0] coef [0:NTAP-1];
    reg signed [DW-1:0] stim [0:NSAMP-1];
    reg signed [DW-1:0] exp  [0:NEXP-1];
    reg signed [DW-1:0] got  [0:NSAMP+NTAP-1];

    integer errors, k, m, i;

    initial begin
        $dumpfile("tb_fir_axi.vcd");
        $dumpvars(0, tb_fir_axi);

        awvalid = 0; wvalid = 0; arvalid = 0; bready = 0; rready = 0;
        awaddr  = 0; wdata = 0; wstrb = 0; araddr = 0;
        errors  = 0;

        // 读入黄金数据
        $readmemh("coeffs.hex", coef);
        $readmemh("stim.hex",   stim);
        $readmemh("exp.hex",    exp);

        // 复位
        repeat (4) @(posedge clk);
        @(negedge clk);
        rst_n = 1;
        @(posedge clk);

        // ---- 1) 写系数 ----
        for (k = 0; k < NTAP; k = k + 1)
            axi_write(COEF_BASE + 4*k, {16'h0000, coef[k][CW-1:0]});

        // ---- 2) 清空（START）----
        axi_write(ADDR_CTRL, 32'h1);

        // ---- 3) 写样本 ----
        for (m = 0; m < NSAMP; m = m + 1)
            axi_write(ADDR_DIN, {16'h0000, stim[m][DW-1:0]});

        // ---- 4) 写 NTAP 个 0 排空延迟线 ----
        for (m = 0; m < NTAP; m = m + 1)
            axi_write(ADDR_DIN, 32'h0);

        // ---- 5) 读结果 ----
        for (i = 0; i < NSAMP + NTAP; i = i + 1) begin
            axi_read(ADDR_DOUT, rd_data);
            got[i] = rd_data[DW-1:0];
        end

        // ---- 6) 比对：got[0] 是流水线前导(恒0)，从 got[1] 开始 ----
        $display("FIR 抽头数 = %0d，样本数 = %0d，期望输出 = %0d 个", NTAP, NSAMP, NEXP);
        for (i = 0; i < NEXP; i = i + 1) begin
            if (got[i+1] !== exp[i]) begin
                errors = errors + 1;
                if (errors <= 10)
                    $display("[MISMATCH] 第 %0d 个: RTL=%0d 参考=%0d", i, got[i+1], exp[i]);
            end
        end

        if (errors == 0)
            $display("\n===== PASS: FIR(%0d阶) %0d 个输出与软件黄金模型逐位一致 =====", NTAP, NEXP);
        else
            $display("\n===== FAIL: %0d / %0d 个不一致 =====", errors, NEXP);

        $finish;
    end

    // 兜底超时
    initial begin
        #5000000;
        $display("!!!! TIMEOUT");
        $finish;
    end

endmodule

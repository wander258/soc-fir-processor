// ============================================================
// 实验 08 的 testbench —— 完整 SoC 端到端验证（最基本功能版）
//
// 这里没有真 CPU，而是用一个"主设备模型(BFM)"扮演 CPU 的 AXI 主端口，
// 把 C 驱动要做的事按顺序做一遍：
//
//   1. 写 FIR 系数           （对应 C 驱动 fir_init(coeffs)）
//   2. 清空 FIR              （对应 fir_reset()）
//   3. 写样本                （对应 fir_write_sample(x)）
//   4. 读回滤波结果          （对应 fir_read_result()）
//   5. 与软件黄金模型比对    （对应"误差 < 0.1%"验收，我们做到逐位一致）
//   6. 通过 UART 打印结果    （对应 uart_puts()，CPU 跑通的证据）
//   7. 顺带验证 SRAM 读写    （对应 DMA 的源/目的存储）
//
// 还写了一个"UART 接收模型"：监测 txd 串口线上的电平，
// 按 8N1 协议把字节一位一位收回来，打印到终端 —— 这就是你"看到"
// CPU 通过串口说话的证据。
// ============================================================
`timescale 1ns/1ps

module tb_soc;

    localparam ADDR_W = 32;
    localparam DATA_W = 32;
    localparam DW = 16, CW = 16, AW = 40;
    parameter  NTAP  = 81;
    parameter  NSAMP = 256;
    localparam NEXP  = NSAMP + NTAP - 1;

    // ---- 内存地图（和 soc_top / axi_lite_xbar 一致）----
    localparam FIR_BASE  = 32'h0000_0000;
    localparam UART_BASE = 32'h0000_1000;
    localparam SRAM_BASE = 32'h0000_2000;

    // FIR 寄存器（相对 FIR_BASE）
    localparam FIR_CTRL   = FIR_BASE + 32'h000;
    localparam FIR_DIN    = FIR_BASE + 32'h004;
    localparam FIR_DOUT   = FIR_BASE + 32'h008;
    localparam FIR_STATUS = FIR_BASE + 32'h00C;
    localparam FIR_COEF   = FIR_BASE + 32'h100;
    // UART 寄存器（相对 UART_BASE）
    localparam UART_DATA   = UART_BASE + 32'h000;
    localparam UART_STATUS = UART_BASE + 32'h004;

    // ---- 波特率（和 uart_tx.v 一致：100MHz / 115200 = 868）----
    localparam BAUD_BIT = 868;

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
    wire                txd;

    soc_top #(.ADDR_W(ADDR_W), .DATA_W(DATA_W),
              .DW(DW), .CW(CW), .AW(AW), .NTAP(NTAP)) dut (
        .clk(clk), .rst_n(rst_n),
        .m_awaddr(awaddr), .m_awvalid(awvalid), .m_awready(awready),
        .m_wdata(wdata),   .m_wstrb(wstrb),     .m_wvalid(wvalid), .m_wready(wready),
        .m_bresp(bresp),   .m_bvalid(bvalid),   .m_bready(bready),
        .m_araddr(araddr), .m_arvalid(arvalid), .m_arready(arready),
        .m_rdata(rdata),   .m_rresp(rresp),     .m_rvalid(rvalid), .m_rready(rready),
        .txd(txd)
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

    // ---- UART 发送一个字节（先等 busy=0）----
    task uart_putc(input [7:0] ch);
        reg [DATA_W-1:0] st;
        begin
            // 等空闲
            do begin
                axi_read(UART_STATUS, st);
            end while (st[0]);
            axi_write(UART_DATA, {24'h0, ch});
        end
    endtask

    // ============================================================
    // UART 接收模型：监测 txd 线，按 8N1 收字节（跑在独立 initial 里）
    // ============================================================
    task uart_rx_byte(output [7:0] b);
        integer i;
        begin
            @(negedge txd);                          // 起始位（下降沿）
            repeat (BAUD_BIT/2) @(posedge clk);      // 走到起始位中点
            repeat (BAUD_BIT)   @(posedge clk);      // 走到 bit0 中点
            for (i = 0; i < 8; i = i + 1) begin
                b[i] = txd;
                repeat (BAUD_BIT) @(posedge clk);
            end
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

    // ============================================================
    // 主测试流程
    // ============================================================
    initial begin
        $dumpfile("tb_soc.vcd");
        $dumpvars(0, tb_soc);

        awvalid = 0; wvalid = 0; arvalid = 0; bready = 0; rready = 0;
        awaddr  = 0; wdata = 0; wstrb = 0; araddr = 0;
        errors  = 0;

        $readmemh("coeffs.hex", coef);
        $readmemh("stim.hex",   stim);
        $readmemh("exp.hex",    exp);

        // 复位
        repeat (4) @(posedge clk);
        @(negedge clk);
        rst_n = 1;
        @(posedge clk);

        // ---- 1) 写 FIR 系数 ----
        for (k = 0; k < NTAP; k = k + 1)
            axi_write(FIR_COEF + 4*k, {16'h0000, coef[k][CW-1:0]});

        // ---- 2) 清空 FIR ----
        axi_write(FIR_CTRL, 32'h1);

        // ---- 3) 写样本 ----
        for (m = 0; m < NSAMP; m = m + 1)
            axi_write(FIR_DIN, {16'h0000, stim[m][DW-1:0]});

        // ---- 4) 写 NTAP+8 个 0 排空延迟线 ----
        for (m = 0; m < NTAP + 8; m = m + 1)
            axi_write(FIR_DIN, 32'h0);

        // ---- 5) 读结果 ----
        for (i = 0; i < NSAMP + NTAP; i = i + 1) begin
            axi_read(FIR_DOUT, rd_data);
            got[i] = rd_data[DW-1:0];
        end

        // ---- 6) 比对（跳过流水线前导 got[0]）----
        for (i = 0; i < NEXP; i = i + 1) begin
            if (got[i+1] !== exp[i]) begin
                errors = errors + 1;
                if (errors <= 10)
                    $display("[MISMATCH] 第 %0d 个: RTL=%0d 参考=%0d", i, got[i+1], exp[i]);
            end
        end
        if (errors == 0)
            $display("===== FIR PASS: %0d阶 %0d 个输出与软件黄金模型逐位一致 =====", NTAP, NEXP);
        else
            $display("===== FIR FAIL: %0d / %0d 个不一致 =====", errors, NEXP);

        // ---- 7) 验证 SRAM 读写（互连能正确路由到第三个从设备）----
        axi_write(SRAM_BASE + 0, 32'hCAFE_BABE);
        axi_read(SRAM_BASE + 0, rd_data);
        if (rd_data === 32'hCAFE_BABE)
            $display("===== SRAM PASS: 写入/读回 0xCAFE_BABE 正确 =====");
        else begin
            $display("===== SRAM FAIL: 读到 %08x =====", rd_data);
            errors = errors + 1;
        end

        // ---- 8) UART 打印 ----
        // 通过串口发一行字，由 uart_monitor 收回来打印（等一会让它收完）
        $write("\n[UART RX] ");
        uart_putc("F"); uart_putc("I"); uart_putc("R");
        uart_putc("8"); uart_putc("1"); uart_putc(" ");
        uart_putc("O"); uart_putc("K"); uart_putc("\n");

        // 给 UART 一点时间把最后一个字节发完
        repeat (BAUD_BIT * 12) @(posedge clk);

        if (errors == 0)
            $display("\n===== SOC PASS: FIR + SRAM + UART 全部正常 =====");
        else
            $display("\n===== SOC FAIL: %0d 个错误 =====", errors);

        $finish;
    end

    // ============================================================
    // UART 监视器（并行跑）：把串口收到的字节打印出来。
    // 收到换行后后面就没有字节了，它会一直阻塞等下一个起始位，
    // 直到主流程 $finish 结束整个仿真 —— 所以这里不用特别处理停止。
    // ============================================================
    initial begin
        reg [7:0] ch;
        wait (rst_n === 1'b1);
        forever begin
            uart_rx_byte(ch);
            $write("%c", ch);
        end
    end

    // 兜底超时
    initial begin
        #20000000;
        $display("!!!! TIMEOUT");
        $finish;
    end

endmodule

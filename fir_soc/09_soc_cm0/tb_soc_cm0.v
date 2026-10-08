// ============================================================
// 实验 09 的 testbench —— 真 Cortex-M0 跑 C 程序控制 FIR
//
// 这个 TB 不扮演 CPU 了，它只做三件事：
//   1. 给时钟 + 复位
//   2. 让 soc_cm0_top 里的真 Cortex-M0 从 RAM(0x0) 启动，执行 image.hex 里的程序
//   3. 监测 UART 串口线，把 M0 打印出来的滤波结果收下来
//
// 收到的字节同时打印到终端 + 写进 uart_capture.txt，
// 之后用 verify.py 和黄金模型 expected.txt 逐位比对。
// ============================================================
`timescale 1ns/1ps

module tb_soc_cm0;

    localparam BAUD_BIT = 108;      // 100MHz / 921600（与 soc_cm0_top 的仿真波特率一致）

    reg  ACLK    = 0;
    reg  ARESETn = 0;
    wire uart_txd;

    soc_cm0_top dut (
        .ACLK(ACLK), .ARESETn(ARESETn), .uart_txd(uart_txd)
    );

    always #5 ACLK = ~ACLK;         // 100 MHz

    // ---- 复位 + 总时长 ----
    integer uart_fd;
    initial begin
        // 注意：不要 $dumpvars(0)，M0 核有上千个信号，会把 VCD 撑到几百 MB 并拖慢仿真。
        // 需要看波形时，只 dump 顶层几个关键信号即可。
        uart_fd = $fopen("uart_capture.txt", "w");

        repeat (20) @(posedge ACLK);
        @(negedge ACLK);            // 在时钟低电平释放复位（与 CMSDK 例程一致）
        ARESETn = 1'b1;
        $display("reset released at %0t", $time);

        // 给 M0 足够时间执行完程序（FIR 处理 + UART 打印），留一点余量
        #5000000;                   // 5 ms 兜底
        $display("!!!! TIMEOUT at %0t", $time);
        $fclose(uart_fd);
        $finish;
    end

    // ---- UART 接收模型（8N1）----
    task uart_rx_byte(output [7:0] b);
        integer i;
        begin
            @(negedge uart_txd);                // 起始位
            repeat (BAUD_BIT/2) @(posedge ACLK);
            repeat (BAUD_BIT)   @(posedge ACLK);
            for (i = 0; i < 8; i = i + 1) begin
                b[i] = uart_txd;
                repeat (BAUD_BIT) @(posedge ACLK);
            end
        end
    endtask

    // ---- UART 监视器 ----
    initial begin
        reg [7:0] ch;
        wait (ARESETn === 1'b1);
        forever begin
            uart_rx_byte(ch);
            $write("%c", ch);
            $fwrite(uart_fd, "%c", ch);
            $fflush(uart_fd);
        end
    end

endmodule

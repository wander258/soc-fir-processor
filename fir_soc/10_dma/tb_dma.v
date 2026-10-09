// ============================================================
// 实验 10 的 testbench —— 6 通道 DMA 独立验证（不依赖慢速 M0 核）
//
// 用一个"应答器"扮演 AXI 从设备：
//   读 -> 返回"地址本身"作为数据（方便核对）；
//   写 -> 记录写地址和写数据。
// 然后配置 DMA 通道 0 搬 4 个字（SRC=0x100 -> DST=0x200，地址自增），
// 检查 DMA 是否真的按顺序读了 0x100/0x104/... 又按顺序写了 0x200/0x204/...
// ============================================================
`timescale 1ns/1ps

module tb_dma;

    localparam ADDR_W = 32;
    localparam DATA_W = 32;

    reg clk = 0; reg rst_n = 0;
    always #5 clk = ~clk;

    // ---- DMA 实例 ----
    // AXI-Lite 从口（配置）
    reg  [ADDR_W-1:0] cfg_awaddr, cfg_araddr;
    reg               cfg_awvalid, cfg_arvalid, cfg_wvalid, cfg_bready, cfg_rready;
    reg  [DATA_W-1:0] cfg_wdata;
    reg  [DATA_W/8-1:0] cfg_wstrb;
    wire              cfg_awready, cfg_arready, cfg_wready, cfg_bvalid, cfg_rvalid;
    wire [1:0]        cfg_bresp, cfg_rresp;
    wire [DATA_W-1:0] cfg_rdata;

    // AXI4 主口（搬数据）
    wire             AW_VALID, AW_READY, W_VALID, W_READY, W_LAST, B_VALID, B_READY;
    wire [2:0]       AW_SIZE, AR_SIZE;
    wire [1:0]       AW_BURST, AR_BURST, B_RESP, R_RESP;
    wire [7:0]       AW_LEN, AR_LEN;
    wire [ADDR_W-1:0] AW_ADDR, AR_ADDR;
    wire [DATA_W-1:0] W_DATA, R_DATA;
    wire             AR_VALID, AR_READY, R_VALID, R_READY, R_LAST;
    wire             irq_dma;

    dma #(.ADDR_W(ADDR_W), .DATA_W(DATA_W), .NCH(6)) u_dma (
        .clk(clk), .rst_n(rst_n),
        .awaddr(cfg_awaddr), .awvalid(cfg_awvalid), .awready(cfg_awready),
        .wdata(cfg_wdata), .wstrb(cfg_wstrb), .wvalid(cfg_wvalid), .wready(cfg_wready),
        .bresp(cfg_bresp), .bvalid(cfg_bvalid), .bready(cfg_bready),
        .araddr(cfg_araddr), .arvalid(cfg_arvalid), .arready(cfg_arready),
        .rdata(cfg_rdata), .rresp(cfg_rresp), .rvalid(cfg_rvalid), .rready(cfg_rready),
        .AW_VALID(AW_VALID), .AW_READY(AW_READY), .AW_SIZE(AW_SIZE), .AW_BURST(AW_BURST),
        .AW_LEN(AW_LEN), .AW_ADDR(AW_ADDR),
        .W_VALID(W_VALID), .W_READY(W_READY), .W_LAST(W_LAST), .W_DATA(W_DATA),
        .B_VALID(B_VALID), .B_READY(B_READY), .B_RESP(B_RESP),
        .AR_VALID(AR_VALID), .AR_READY(AR_READY), .AR_SIZE(AR_SIZE), .AR_BURST(AR_BURST),
        .AR_LEN(AR_LEN), .AR_ADDR(AR_ADDR),
        .R_VALID(R_VALID), .R_READY(R_READY), .R_LAST(R_LAST), .R_DATA(R_DATA), .R_RESP(R_RESP),
        .irq(irq_dma)
    );

    // ---- 应答器：读返回地址，写记录 ----
    reg  [ADDR_W-1:0] rd_addr;
    reg               rd_pend;
    reg  [DATA_W-1:0] wr_cap_data [0:15];
    reg  [ADDR_W-1:0] wr_cap_addr [0:15];
    integer           wr_cnt;

    assign AR_READY = !rd_pend;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin rd_addr <= 0; rd_pend <= 0; end
        else begin
            if (AR_VALID && AR_READY) begin rd_addr <= AR_ADDR; rd_pend <= 1; end
            else if (R_VALID && R_READY) rd_pend <= 0;
        end
    end
    assign R_VALID = rd_pend;
    assign R_LAST  = rd_pend;
    assign R_DATA  = {16'h0, rd_addr[15:0]};   // 返回地址作为数据
    assign R_RESP  = 2'b00;

    // 写响应（应答器）
    assign AW_READY = 1;
    assign W_READY  = 1;
    assign B_VALID  = 1;
    assign B_RESP   = 2'b00;
    always @(posedge clk) begin
        if (rst_n && W_VALID && W_READY) begin
            wr_cap_data[wr_cnt] <= W_DATA;
            wr_cap_addr[wr_cnt] <= AW_ADDR;
            wr_cnt <= wr_cnt + 1;
        end
    end

    // ============================================================
    // BFM：配置 DMA（AXI-Lite）
    // ============================================================
    reg [DATA_W-1:0] rd_d;
    task cfg_write(input [ADDR_W-1:0] a, input [DATA_W-1:0] d);
        begin
            cfg_awaddr = a; cfg_awvalid = 1; cfg_wdata = d; cfg_wstrb = 4'hF; cfg_wvalid = 1;
            wait (cfg_awready && cfg_wready); @(posedge clk);
            cfg_awvalid <= 0; cfg_wvalid <= 0;
            cfg_bready = 1; wait (cfg_bvalid); @(posedge clk); cfg_bready <= 0;
        end
    endtask
    task cfg_read(input [ADDR_W-1:0] a, output [DATA_W-1:0] d);
        begin
            cfg_araddr = a; cfg_arvalid = 1;
            wait (cfg_arready); @(posedge clk); cfg_arvalid <= 0;
            cfg_rready = 1; wait (cfg_rvalid); @(posedge clk); d = cfg_rdata; cfg_rready <= 0;
        end
    endtask

    integer errors;
    integer chk;
    reg [ADDR_W-1:0] exp_addr;
    reg [DATA_W-1:0] exp_data;
    initial begin
        $dumpfile("tb_dma.vcd"); $dumpvars(0, tb_dma);
        cfg_awvalid=0; cfg_wvalid=0; cfg_bready=0; cfg_arvalid=0; cfg_rready=0;
        wr_cnt = 0; errors = 0;

        repeat (4) @(posedge clk); @(negedge clk); rst_n = 1; @(posedge clk);

        // 配置通道 0：SRC=0x100, DST=0x200, LEN=4, START+SRC_INC+DST_INC
        cfg_write(32'h000, 32'h100);   // SRC
        cfg_write(32'h004, 32'h200);   // DST
        cfg_write(32'h008, 32'h004);   // LEN = 4 字
        cfg_write(32'h00C, 32'h007);   // CTRL = START|SRC_INC|DST_INC

        // 等 DMA 传完（读 DONE）
        wait (irq_dma);
        repeat (4) @(posedge clk);

        // 核对：写了 4 个字，地址 0x200/204/208/20C，数据 0x100/104/108/10C
        $display("DMA 写了 %0d 个字", wr_cnt);
        for (chk = 0; chk < 4; chk = chk + 1) begin
            exp_addr = 32'h200 + (chk * 4);
            exp_data = {16'h0, 16'h100} + (chk * 4);
            if (wr_cap_addr[chk] !== exp_addr) begin
                errors = errors + 1;
                $display("[FAIL] 写地址[%0d] = %h，期望 %h", chk, wr_cap_addr[chk], exp_addr);
            end
            if (wr_cap_data[chk] !== exp_data) begin
                errors = errors + 1;
                $display("[FAIL] 写数据[%0d] = %h，期望 %h", chk, wr_cap_data[chk], exp_data);
            end
        end
        if (wr_cnt != 4) begin errors = errors + 1; $display("[FAIL] 写字数 = %0d，期望 4", wr_cnt); end

        if (errors == 0)
            $display("===== PASS: DMA 6 通道（通道0）单拍搬运正确 =====");
        else
            $display("===== FAIL: %0d 个错误 =====", errors);

        $finish;
    end

endmodule

// ============================================================
// tb_dma_ic.v —— DMA × AXI 互连 集成验证（阶段3 集成验收）
//
// 【验证目标】docs/阶段3-三人分工.md §7 集成验收里缺的那条：
//   「接进阶段 2 的互连后，CPU 和 DMA 同时访问也不出错」
//
// 【拓扑】（与 docs/任务四 1.3 一致）
//   CPU BFM（主 ID=0）  ──► axi_ic.s0
//   DMA 数据口（主 ID=1） ──► axi_ic.s1
//   axi_ic.m0 = FIR      （未用，tie-off）
//   axi_ic.m1 = DMA 配置 ──► dma.s_axi（配置口）
//   axi_ic.m2 = SRAM     ──► 基址 0x2000_0000 的存储器模型
//   axi_ic.m3 = ROM      （未用，tie-off）
//   axi_ic.m4 = AXI→APB  （未用，tie-off）
//
// 【重点验证】
//   · 配置通路：CPU 经互连（s0→m1）写 DMA 寄存器
//   · 数据通路：DMA 经互连（s1→m2）读写 SRAM（地址译码 + ID[0] 路由回选）
//   · CPU 与 DMA 两个主设备同时经互连访问不冲突
//
// 【运行】（从仓库根目录）
//   iverilog -g2012 -Wall -o sim.out \
//       RTL/dma.v RTL/dma_regs.v RTL/dma_engine.v RTL/sync_fifo.v RTL/axi_arbiter.v RTL/axi_ic.v \
//       TB/axi_mem_model.v TB/axi_protocol_checker.v TB/axi_id_contract_check.v TB/tb_dma_ic.v
//   vvp sim.out
// ============================================================
`timescale 1ns/1ps



// ------------------------------------------------------------
// 顶层测试台
// ------------------------------------------------------------
module tb_dma_ic;

    localparam ADDR_W = 32;
    localparam DATA_W = 32;
    localparam ID_W   = 4;
    localparam LEN_W  = 8;
    localparam NCH    = 6;

    localparam DMA_BASE = 32'h4000_1000;
    localparam SRAM_BASE= 32'h2000_0000;

    reg clk   = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;

    // ============================================================
    // CPU 主口（接 axi_ic.s0，主 ID=0）
    // ============================================================
    reg  [ID_W-1:0]   c_awid = 0;
    reg  [ADDR_W-1:0] c_awaddr = 0;
    reg  [LEN_W-1:0]  c_awlen = 0;
    reg  [2:0]        c_awsize = 3'd2;
    reg  [1:0]        c_awburst = 2'b01;
    reg               c_awvalid = 0;
    wire              c_awready;
    reg  [DATA_W-1:0] c_wdata = 0;
    reg  [3:0]        c_wstrb = 4'hF;
    reg               c_wlast = 0;
    reg               c_wvalid = 0;
    wire              c_wready;
    wire [ID_W-1:0]   c_bid;
    wire [1:0]        c_bresp;
    wire              c_bvalid;
    reg               c_bready = 0;
    reg  [ID_W-1:0]   c_arid = 0;
    reg  [ADDR_W-1:0] c_araddr = 0;
    reg  [LEN_W-1:0]  c_arlen = 0;
    reg  [2:0]        c_arsize = 3'd2;
    reg  [1:0]        c_arburst = 2'b01;
    reg               c_arvalid = 0;
    wire              c_arready;
    wire [ID_W-1:0]   c_rid;
    wire [DATA_W-1:0] c_rdata;
    wire [1:0]        c_rresp;
    wire              c_rlast;
    wire              c_rvalid;
    reg               c_rready = 0;

    // ============================================================
    // DMA 数据口（dma.m_axi == axi_ic.s1）
    // ============================================================
    wire [ID_W-1:0]   m_awid, m_arid, m_bid, m_rid;
    wire [ADDR_W-1:0] m_awaddr, m_araddr;
    wire [LEN_W-1:0]  m_awlen, m_arlen;
    wire [2:0]        m_awsize, m_arsize;
    wire [1:0]        m_awburst, m_arburst, m_bresp, m_rresp;
    wire              m_awvalid, m_awready, m_arvalid, m_arready;
    wire [DATA_W-1:0] m_wdata, m_rdata;
    wire [3:0]        m_wstrb;
    wire              m_wlast, m_wvalid, m_wready;
    wire              m_bvalid, m_bready;
    wire              m_rlast, m_rvalid, m_rready;

    // ============================================================
    // DMA 配置口（dma.s_axi == axi_ic.m1）
    // ============================================================
    wire [ID_W-1:0]   s_awid, s_arid, s_bid, s_rid;
    wire [ADDR_W-1:0] s_awaddr, s_araddr;
    wire [LEN_W-1:0]  s_awlen, s_arlen;
    wire [2:0]        s_awsize, s_arsize;
    wire [1:0]        s_awburst, s_arburst, s_bresp, s_rresp;
    wire              s_awvalid, s_awready, s_arvalid, s_arready;
    wire [DATA_W-1:0] s_wdata, s_rdata;
    wire [3:0]        s_wstrb;
    wire              s_wlast, s_wvalid, s_wready;
    wire              s_bvalid, s_bready;
    wire              s_rlast, s_rvalid, s_rready;

    // ============================================================
    // SRAM（axi_ic.m2）
    // ============================================================
    wire [ID_W-1:0]   sram_awid, sram_arid, sram_bid, sram_rid;
    wire [ADDR_W-1:0] sram_awaddr, sram_araddr;
    wire [LEN_W-1:0]  sram_awlen, sram_arlen;
    wire [2:0]        sram_awsize, sram_arsize;
    wire [1:0]        sram_awburst, sram_arburst, sram_bresp, sram_rresp;
    wire              sram_awvalid, sram_awready, sram_arvalid, sram_arready;
    wire [DATA_W-1:0] sram_wdata, sram_rdata;
    wire [3:0]        sram_wstrb;
    wire              sram_wlast, sram_wvalid, sram_wready;
    wire              sram_bvalid, sram_bready;
    wire              sram_rlast, sram_rvalid, sram_rready;

    // ============================================================
    // 中断
    // ============================================================
    wire [NCH-1:0] irq_done;
    wire           irq_err;

    // ============================================================
    // DUT：6 通道 DMA
    // ============================================================
    dma #(.ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W), .LEN_W(LEN_W), .NCH(NCH)) u_dut (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awid(s_awid), .s_axi_awaddr(s_awaddr), .s_axi_awlen(s_awlen),
        .s_axi_awsize(s_awsize), .s_axi_awburst(s_awburst),
        .s_axi_awvalid(s_awvalid), .s_axi_awready(s_awready),
        .s_axi_wdata(s_wdata), .s_axi_wstrb(s_wstrb), .s_axi_wlast(s_wlast),
        .s_axi_wvalid(s_wvalid), .s_axi_wready(s_wready),
        .s_axi_bid(s_bid), .s_axi_bresp(s_bresp), .s_axi_bvalid(s_bvalid), .s_axi_bready(s_bready),
        .s_axi_arid(s_arid), .s_axi_araddr(s_araddr), .s_axi_arlen(s_arlen),
        .s_axi_arsize(s_arsize), .s_axi_arburst(s_arburst),
        .s_axi_arvalid(s_arvalid), .s_axi_arready(s_arready),
        .s_axi_rid(s_rid), .s_axi_rdata(s_rdata), .s_axi_rresp(s_rresp),
        .s_axi_rlast(s_rlast), .s_axi_rvalid(s_rvalid), .s_axi_rready(s_rready),
        .m_axi_awid(m_awid), .m_axi_awaddr(m_awaddr), .m_axi_awlen(m_awlen),
        .m_axi_awsize(m_awsize), .m_axi_awburst(m_awburst),
        .m_axi_awvalid(m_awvalid), .m_axi_awready(m_awready),
        .m_axi_wdata(m_wdata), .m_axi_wstrb(m_wstrb), .m_axi_wlast(m_wlast),
        .m_axi_wvalid(m_wvalid), .m_axi_wready(m_wready),
        .m_axi_bid(m_bid), .m_axi_bresp(m_bresp), .m_axi_bvalid(m_bvalid), .m_axi_bready(m_bready),
        .m_axi_arid(m_arid), .m_axi_araddr(m_araddr), .m_axi_arlen(m_arlen),
        .m_axi_arsize(m_arsize), .m_axi_arburst(m_arburst),
        .m_axi_arvalid(m_arvalid), .m_axi_arready(m_arready),
        .m_axi_rid(m_rid), .m_axi_rdata(m_rdata), .m_axi_rresp(m_rresp),
        .m_axi_rlast(m_rlast), .m_axi_rvalid(m_rvalid), .m_axi_rready(m_rready),
        .irq_done(irq_done), .irq_err(irq_err)
    );

    // ============================================================
    // AXI 互连（2 主 5 从）
    // ============================================================
    axi_ic #(.DATA_W(DATA_W), .ADDR_W(ADDR_W), .ID_W(ID_W), .N_MASTER(2), .N_SLAVE(5)) u_ic (
        .clk(clk), .rst_n(rst_n),
        // s0 = CPU
        .s0_axi_awid(c_awid), .s0_axi_awaddr(c_awaddr), .s0_axi_awlen(c_awlen),
        .s0_axi_awsize(c_awsize), .s0_axi_awburst(c_awburst),
        .s0_axi_awvalid(c_awvalid), .s0_axi_awready(c_awready),
        .s0_axi_wdata(c_wdata), .s0_axi_wstrb(c_wstrb), .s0_axi_wlast(c_wlast),
        .s0_axi_wvalid(c_wvalid), .s0_axi_wready(c_wready),
        .s0_axi_bid(c_bid), .s0_axi_bresp(c_bresp), .s0_axi_bvalid(c_bvalid), .s0_axi_bready(c_bready),
        .s0_axi_arid(c_arid), .s0_axi_araddr(c_araddr), .s0_axi_arlen(c_arlen),
        .s0_axi_arsize(c_arsize), .s0_axi_arburst(c_arburst),
        .s0_axi_arvalid(c_arvalid), .s0_axi_arready(c_arready),
        .s0_axi_rid(c_rid), .s0_axi_rdata(c_rdata), .s0_axi_rresp(c_rresp),
        .s0_axi_rlast(c_rlast), .s0_axi_rvalid(c_rvalid), .s0_axi_rready(c_rready),
        // s1 = DMA 数据口
        .s1_axi_awid(m_awid), .s1_axi_awaddr(m_awaddr), .s1_axi_awlen(m_awlen),
        .s1_axi_awsize(m_awsize), .s1_axi_awburst(m_awburst),
        .s1_axi_awvalid(m_awvalid), .s1_axi_awready(m_awready),
        .s1_axi_wdata(m_wdata), .s1_axi_wstrb(m_wstrb), .s1_axi_wlast(m_wlast),
        .s1_axi_wvalid(m_wvalid), .s1_axi_wready(m_wready),
        .s1_axi_bid(m_bid), .s1_axi_bresp(m_bresp), .s1_axi_bvalid(m_bvalid), .s1_axi_bready(m_bready),
        .s1_axi_arid(m_arid), .s1_axi_araddr(m_araddr), .s1_axi_arlen(m_arlen),
        .s1_axi_arsize(m_arsize), .s1_axi_arburst(m_arburst),
        .s1_axi_arvalid(m_arvalid), .s1_axi_arready(m_arready),
        .s1_axi_rid(m_rid), .s1_axi_rdata(m_rdata), .s1_axi_rresp(m_rresp),
        .s1_axi_rlast(m_rlast), .s1_axi_rvalid(m_rvalid), .s1_axi_rready(m_rready),
        // m0 = FIR（未用）
        .m0_axi_awid(), .m0_axi_awaddr(), .m0_axi_awlen(), .m0_axi_awsize(), .m0_axi_awburst(),
        .m0_axi_awvalid(), .m0_axi_awready(1'b1),
        .m0_axi_wdata(), .m0_axi_wstrb(), .m0_axi_wlast(), .m0_axi_wvalid(), .m0_axi_wready(1'b1),
        .m0_axi_bid(4'd0), .m0_axi_bresp(2'b00), .m0_axi_bvalid(1'b0), .m0_axi_bready(),
        .m0_axi_arid(), .m0_axi_araddr(), .m0_axi_arlen(), .m0_axi_arsize(), .m0_axi_arburst(),
        .m0_axi_arvalid(), .m0_axi_arready(1'b1),
        .m0_axi_rid(4'd0), .m0_axi_rdata(32'd0), .m0_axi_rresp(2'b00), .m0_axi_rlast(1'b0), .m0_axi_rvalid(1'b0), .m0_axi_rready(),
        // m1 = DMA 配置口
        .m1_axi_awid(s_awid), .m1_axi_awaddr(s_awaddr), .m1_axi_awlen(s_awlen),
        .m1_axi_awsize(s_awsize), .m1_axi_awburst(s_awburst),
        .m1_axi_awvalid(s_awvalid), .m1_axi_awready(s_awready),
        .m1_axi_wdata(s_wdata), .m1_axi_wstrb(s_wstrb), .m1_axi_wlast(s_wlast),
        .m1_axi_wvalid(s_wvalid), .m1_axi_wready(s_wready),
        .m1_axi_bid(s_bid), .m1_axi_bresp(s_bresp), .m1_axi_bvalid(s_bvalid), .m1_axi_bready(s_bready),
        .m1_axi_arid(s_arid), .m1_axi_araddr(s_araddr), .m1_axi_arlen(s_arlen),
        .m1_axi_arsize(s_arsize), .m1_axi_arburst(s_arburst),
        .m1_axi_arvalid(s_arvalid), .m1_axi_arready(s_arready),
        .m1_axi_rid(s_rid), .m1_axi_rdata(s_rdata), .m1_axi_rresp(s_rresp),
        .m1_axi_rlast(s_rlast), .m1_axi_rvalid(s_rvalid), .m1_axi_rready(s_rready),
        // m2 = SRAM
        .m2_axi_awid(sram_awid), .m2_axi_awaddr(sram_awaddr), .m2_axi_awlen(sram_awlen),
        .m2_axi_awsize(sram_awsize), .m2_axi_awburst(sram_awburst),
        .m2_axi_awvalid(sram_awvalid), .m2_axi_awready(sram_awready),
        .m2_axi_wdata(sram_wdata), .m2_axi_wstrb(sram_wstrb), .m2_axi_wlast(sram_wlast),
        .m2_axi_wvalid(sram_wvalid), .m2_axi_wready(sram_wready),
        .m2_axi_bid(sram_bid), .m2_axi_bresp(sram_bresp), .m2_axi_bvalid(sram_bvalid), .m2_axi_bready(sram_bready),
        .m2_axi_arid(sram_arid), .m2_axi_araddr(sram_araddr), .m2_axi_arlen(sram_arlen),
        .m2_axi_arsize(sram_arsize), .m2_axi_arburst(sram_arburst),
        .m2_axi_arvalid(sram_arvalid), .m2_axi_arready(sram_arready),
        .m2_axi_rid(sram_rid), .m2_axi_rdata(sram_rdata), .m2_axi_rresp(sram_rresp),
        .m2_axi_rlast(sram_rlast), .m2_axi_rvalid(sram_rvalid), .m2_axi_rready(sram_rready),
        // m3 = ROM（未用）
        .m3_axi_awid(), .m3_axi_awaddr(), .m3_axi_awlen(), .m3_axi_awsize(), .m3_axi_awburst(),
        .m3_axi_awvalid(), .m3_axi_awready(1'b1),
        .m3_axi_wdata(), .m3_axi_wstrb(), .m3_axi_wlast(), .m3_axi_wvalid(), .m3_axi_wready(1'b1),
        .m3_axi_bid(4'd0), .m3_axi_bresp(2'b00), .m3_axi_bvalid(1'b0), .m3_axi_bready(),
        .m3_axi_arid(), .m3_axi_araddr(), .m3_axi_arlen(), .m3_axi_arsize(), .m3_axi_arburst(),
        .m3_axi_arvalid(), .m3_axi_arready(1'b1),
        .m3_axi_rid(4'd0), .m3_axi_rdata(32'd0), .m3_axi_rresp(2'b00), .m3_axi_rlast(1'b0), .m3_axi_rvalid(1'b0), .m3_axi_rready(),
        // m4 = AXI→APB（未用）
        .m4_axi_awid(), .m4_axi_awaddr(), .m4_axi_awlen(), .m4_axi_awsize(), .m4_axi_awburst(),
        .m4_axi_awvalid(), .m4_axi_awready(1'b1),
        .m4_axi_wdata(), .m4_axi_wstrb(), .m4_axi_wlast(), .m4_axi_wvalid(), .m4_axi_wready(1'b1),
        .m4_axi_bid(4'd0), .m4_axi_bresp(2'b00), .m4_axi_bvalid(1'b0), .m4_axi_bready(),
        .m4_axi_arid(), .m4_axi_araddr(), .m4_axi_arlen(), .m4_axi_arsize(), .m4_axi_arburst(),
        .m4_axi_arvalid(), .m4_axi_arready(1'b1),
        .m4_axi_rid(4'd0), .m4_axi_rdata(32'd0), .m4_axi_rresp(2'b00), .m4_axi_rlast(1'b0), .m4_axi_rvalid(1'b0), .m4_axi_rready()
    );

    // ============================================================
    // SRAM 模型（基址 0x2000_0000）
    // ============================================================
    axi_mem_model #(.ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W),
                    .BASE(SRAM_BASE), .MEM_BYTES(65536)) u_mem (
        .clk(clk), .rst_n(rst_n),
        .awid(sram_awid), .awaddr(sram_awaddr), .awlen(sram_awlen), .awsize(sram_awsize),
        .awburst(sram_awburst), .awvalid(sram_awvalid), .awready(sram_awready),
        .wdata(sram_wdata), .wstrb(sram_wstrb), .wlast(sram_wlast),
        .wvalid(sram_wvalid), .wready(sram_wready),
        .bid(sram_bid), .bresp(sram_bresp), .bvalid(sram_bvalid), .bready(sram_bready),
        .arid(sram_arid), .araddr(sram_araddr), .arlen(sram_arlen), .arsize(sram_arsize),
        .arburst(sram_arburst), .arvalid(sram_arvalid), .arready(sram_arready),
        .rid(sram_rid), .rdata(sram_rdata), .rresp(sram_rresp), .rlast(sram_rlast),
        .rvalid(sram_rvalid), .rready(sram_rready),
        .err_addr(32'hFFFF_FFFF)      // 本测试不注入错误
    );

    // ============================================================
    // 检查器（DMA 数据口 s1：协议 + 契约C）
    // ============================================================
    wire [31:0] err_proto_s1, err_id_s1;

    axi_protocol_checker #(
        .ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W), .LEN_W(LEN_W), .NAME("s1_dma")
    ) u_chk_s1 (
        .clk(clk), .rst_n(rst_n),
        .awid(m_awid), .awaddr(m_awaddr), .awlen(m_awlen), .awsize(m_awsize), .awburst(m_awburst),
        .awvalid(m_awvalid), .awready(m_awready),
        .wdata(m_wdata), .wstrb(m_wstrb), .wlast(m_wlast), .wvalid(m_wvalid), .wready(m_wready),
        .bid(m_bid), .bresp(m_bresp), .bvalid(m_bvalid), .bready(m_bready),
        .arid(m_arid), .araddr(m_araddr), .arlen(m_arlen), .arsize(m_arsize), .arburst(m_arburst),
        .arvalid(m_arvalid), .arready(m_arready),
        .rid(m_rid), .rdata(m_rdata), .rresp(m_rresp), .rlast(m_rlast), .rvalid(m_rvalid), .rready(m_rready),
        .error_count(err_proto_s1)
    );

    axi_id_contract_check #(.ID_W(ID_W), .NCH(NCH), .NAME("s1_dma")) u_id_chk (
        .clk(clk), .rst_n(rst_n),
        .awid(m_awid), .awvalid(m_awvalid), .awready(m_awready),
        .bid(m_bid), .bvalid(m_bvalid), .bready(m_bready),
        .arid(m_arid), .arvalid(m_arvalid), .arready(m_arready),
        .rid(m_rid), .rvalid(m_rvalid), .rready(m_rready),
        .error_count(err_id_s1)
    );

    // ============================================================
    // 统计
    // ============================================================
    integer errors = 0;
    integer checks = 0;

    task chk;
        input [31:0]  got;
        input [31:0]  exp;
        input [255:0] name;
        begin
            checks = checks + 1;
            if (got !== exp) begin
                errors = errors + 1;
                $display("  [FAIL] %0s : got=0x%08X  期望=0x%08X", name, got, exp);
            end
        end
    endtask

    // ---- CPU 经互连写（s0，主 ID=0）----
    task cpu_write;
        input [ADDR_W-1:0] a;
        input [DATA_W-1:0] d;
        begin
            @(negedge clk);
            c_awid = 4'd0; c_awaddr = a; c_awlen = 8'd0; c_awsize = 3'd2; c_awburst = 2'b01;
            c_awvalid = 1'b1;
            c_wdata = d; c_wstrb = 4'hF; c_wlast = 1'b1; c_wvalid = 1'b1;
            c_bready = 1'b1;
            while (!(c_awvalid && c_awready)) @(negedge clk);
            @(negedge clk); c_awvalid = 1'b0;
            while (!(c_wvalid && c_wready)) @(negedge clk);
            @(negedge clk); c_wvalid = 1'b0; c_wlast = 1'b0;
            while (!(c_bvalid && c_bready)) @(negedge clk);
            if (c_bresp !== 2'b00) begin
                errors = errors + 1;
                $display("  [FAIL] CPU 写 0x%08X 返回 BRESP=0b%0b", a, c_bresp);
            end
            @(negedge clk); c_bready = 1'b0;
        end
    endtask

    // ---- CPU 经互连读（s0）----
    task cpu_read;
        input  [ADDR_W-1:0] a;
        output [DATA_W-1:0] d;
        begin
            @(negedge clk);
            c_arid = 4'd0; c_araddr = a; c_arlen = 8'd0; c_arsize = 3'd2; c_arburst = 2'b01;
            c_arvalid = 1'b1;
            c_rready = 1'b1;
            while (!(c_arvalid && c_arready)) @(negedge clk);
            @(negedge clk); c_arvalid = 1'b0;
            while (!(c_rvalid && c_rready)) @(negedge clk);
            d = c_rdata;
            if (c_rresp !== 2'b00) begin
                errors = errors + 1;
                $display("  [FAIL] CPU 读 0x%08X 返回 RRESP=0b%0b", a, c_rresp);
            end
            @(negedge clk); c_rready = 1'b0;
        end
    endtask

    // ---- 等待通道 done（电平）----
    task wait_done;
        input [3:0] ch;
        integer guard;
        begin
            guard = 0;
            while (irq_done[ch] !== 1'b1 && guard < 20000) begin
                @(negedge clk);
                guard = guard + 1;
            end
            repeat (4) @(negedge clk);
        end
    endtask

    integer i;
    reg [31:0] rd;

    // ============================================================
    initial begin
        $dumpfile("tb_dma_ic.vcd");
        $dumpvars(0, tb_dma_ic);

        repeat (6) @(posedge clk);
        @(negedge clk); rst_n = 1;
        repeat (4) @(posedge clk);

        $display("");
        $display("========== DMA × AXI 互连 集成验证 ==========");

        // ----------------------------------------------------
        // [1] CPU 直接经互连读写 SRAM（验证 s0→m2 通路）
        // ----------------------------------------------------
        $display("[1] CPU 直接经互连读写 SRAM");
        cpu_write(SRAM_BASE + 32'h0000, 32'hCAFE_0001);
        cpu_read (SRAM_BASE + 32'h0000, rd);
        chk(rd, 32'hCAFE_0001, "CPU 经互连读写 SRAM");

        // ----------------------------------------------------
        // [2] CPU 经互连配置 DMA，DMA 经互连搬 SRAM→SRAM
        //     源 0x2000_0000，目的 0x2000_1000，搬 4 字
        // ----------------------------------------------------
        $display("[2] DMA 经互连搬 SRAM→SRAM（4 字）");
        for (i = 0; i < 4; i = i + 1)
            cpu_write(SRAM_BASE + 4*i, 32'hDEAD_0000 + i);       // 预填源

        cpu_write(DMA_BASE + 32'h00, SRAM_BASE + 32'h0000);      // ch0 SRC
        cpu_write(DMA_BASE + 32'h04, SRAM_BASE + 32'h1000);      // ch0 DST
        cpu_write(DMA_BASE + 32'h08, 32'd4);                     // ch0 LEN
        cpu_write(DMA_BASE + 32'h0C, 32'h0000_0007);             // ch0 CTRL=START|SRC_INC|DST_INC
        wait_done(4'd0);

        for (i = 0; i < 4; i = i + 1) begin
            cpu_read(SRAM_BASE + 32'h1000 + 4*i, rd);
            chk(rd, 32'hDEAD_0000 + i, "DMA 经互连搬运结果");
        end
        chk({31'd0, irq_done[0]}, 32'd1, "irq_done[0] 拉高");
        chk({31'd0, irq_err}, 32'd0, "irq_err=0");

        // ----------------------------------------------------
        // [3] CPU 与 DMA 同时访问：DMA 搬 4 字期间，CPU 读 SRAM
        // ----------------------------------------------------
        $display("[3] CPU 与 DMA 同时访问互连");
        for (i = 0; i < 4; i = i + 1)
            cpu_write(SRAM_BASE + 32'h2000 + 4*i, 32'h5A5A_0000 + i);   // 预填源2
        // 用一个 DMA 不会碰的地址放 CPU 的观察值
        cpu_write(SRAM_BASE + 32'h4000, 32'hCAFE_0001);
        cpu_write(DMA_BASE + 32'h00, SRAM_BASE + 32'h2000);             // ch0 SRC
        cpu_write(DMA_BASE + 32'h04, SRAM_BASE + 32'h3000);             // ch0 DST
        cpu_write(DMA_BASE + 32'h08, 32'd4);                            // ch0 LEN
        cpu_write(DMA_BASE + 32'h0C, 32'h0000_0007);                    // START
        // DMA 启动后 CPU 立刻去读 SRAM（验证两个主设备仲裁无死锁）
        cpu_read(SRAM_BASE + 32'h4000, rd);
        chk(rd, 32'hCAFE_0001, "并发时 CPU 读 SRAM 不受影响");
        wait_done(4'd0);
        for (i = 0; i < 4; i = i + 1) begin
            cpu_read(SRAM_BASE + 32'h3000 + 4*i, rd);
            chk(rd, 32'h5A5A_0000 + i, "并发期间 DMA 搬运结果");
        end

        // ----------------------------------------------------
        // [4] 检查器汇总
        // ----------------------------------------------------
        repeat (10) @(negedge clk);
        $display("[4] 检查器汇总");
        $display("      DMA 数据口(s1) AXI 协议违规 : %0d", err_proto_s1);
        $display("      DMA 数据口(s1) 契约C违规  : %0d", err_id_s1);
        checks = checks + 2;
        if (err_proto_s1 !== 0) begin errors = errors + 1; $display("  [FAIL] DMA 数据口有 AXI 协议违规"); end
        if (err_id_s1    !== 0) begin errors = errors + 1; $display("  [FAIL] DMA 数据口违反契约C"); end

        // ----------------------------------------------------
        $display("");
        $display("============================================");
        if (errors == 0)
            $display("===== PASS: %0d 项检查全部通过，DMA×互连 零违规 =====", checks);
        else
            $display("===== FAIL: %0d 项检查中 %0d 项失败 =====", checks, errors);
        $display("============================================");
        $finish;
    end

    initial begin
        #3000000;
        $display("!!!! TIMEOUT：仿真超时");
        $finish;
    end

endmodule

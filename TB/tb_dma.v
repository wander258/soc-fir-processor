// ============================================================
// tb_dma.v —— 6 通道 DMA 控制器 系统级验证（阶段3 分工 C）
//
// 【验证对象】RTL/dma.v（A 的顶层：dma_regs + 6×dma_engine + 6→1 仲裁 + 中断）
//
// 【对手】
//   · 配置口（AXI4 从口）：本测试台自己当主设备，用 axi_write / axi_read 任务驱动
//   · 数据口（AXI4 主口）：接 TB/axi_mem_model.v（公共件，64KB 存储器）
//
// 【挂的检查器】（阶段2 与阶段3 的成果，全程零违规才算过）
//   · axi_protocol_checker  ×2  —— 配置口 + 数据口，14 条 AXI4 协议规则
//   · axi_id_contract_check ×1  —— 数据口，契约C（ID = {CH[2:0], 1'b1}）
//
// 【覆盖】对应 docs/阶段3-三人分工.md C 的验收清单
//   [1] 寄存器读写（CTRL 的 START 自清、状态位回读）
//   [2] 单拍搬运（LEN=1）
//   [3] INCR 突发搬运（LEN=4）
//   [4] DST_INC=0：固定目的地址（模拟 UART / FIR 的 DIN 寄存器）
//   [5] SRC_INC=0：固定源地址（模拟 UART / FIR 的 DOUT 寄存器）
//   [6] 6 通道并发启动（仲裁不能饿死任何一个）
//   [7] 中断：逐通道 irq_done + irq_err
//   [8] 错误响应：SLVERR -> irq_err
//
// 【运行】（从仓库根目录）
//   iverilog -g2012 -Wall -o sim.out \
//       RTL/dma.v RTL/dma_regs.v RTL/dma_engine.v RTL/sync_fifo.v RTL/axi_arbiter.v \
//       TB/axi_mem_model.v TB/axi_protocol_checker.v TB/axi_id_contract_check.v \
//       TB/tb_dma.v
//   vvp sim.out
//
// ⚠️ 控制台中文乱码（Windows cmd 默认 GBK）执行 chcp 65001
// ============================================================
`timescale 1ns/1ps

module tb_dma;

    localparam ADDR_W = 32;
    localparam DATA_W = 32;
    localparam ID_W   = 4;
    localparam LEN_W  = 8;
    localparam NCH    = 6;

    localparam DMA_BASE  = 32'h4000_1000;   // 配置口基址（任务三 3.2）
    // ⚠️ 两个基址都必须落在存储器模型的范围里（MEM_BYTES = 65536 = 64KB）
    //    源从 0 开始，目的放中间，两者不重叠
    localparam SRC_BASE  = 32'h0000_0000;   // 源缓冲区（0 ~ 8KB）
    localparam DST_BASE  = 32'h0000_8000;   // 目的缓冲区（32KB 起）
    localparam CH_STRIDE = 32'h0000_0100;   // 每通道间隔

    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;                   // 100 MHz

    // ============================================================
    // 配置口（AXI4 从口）—— 本测试台当主设备
    // ============================================================
    reg  [ID_W-1:0]   s_awid    = 0;
    reg  [ADDR_W-1:0] s_awaddr  = 0;
    reg  [LEN_W-1:0]  s_awlen   = 0;
    reg  [2:0]        s_awsize  = 3'd2;
    reg  [1:0]        s_awburst = 2'b01;
    reg               s_awvalid = 0;
    wire              s_awready;
    reg  [DATA_W-1:0] s_wdata   = 0;
    reg  [3:0]        s_wstrb   = 4'hF;
    reg               s_wlast   = 0;
    reg               s_wvalid  = 0;
    wire              s_wready;
    wire [ID_W-1:0]   s_bid;
    wire [1:0]        s_bresp;
    wire              s_bvalid;
    reg               s_bready  = 0;
    reg  [ID_W-1:0]   s_arid    = 0;
    reg  [ADDR_W-1:0] s_araddr  = 0;
    reg  [LEN_W-1:0]  s_arlen   = 0;
    reg  [2:0]        s_arsize  = 3'd2;
    reg  [1:0]        s_arburst = 2'b01;
    reg               s_arvalid = 0;
    wire              s_arready;
    wire [ID_W-1:0]   s_rid;
    wire [DATA_W-1:0] s_rdata;
    wire [1:0]        s_rresp;
    wire              s_rlast;
    wire              s_rvalid;
    reg               s_rready  = 0;

    // ============================================================
    // 数据口（AXI4 主口）—— 接存储器模型
    // ============================================================
    wire [ID_W-1:0]   m_awid;
    wire [ADDR_W-1:0] m_awaddr;
    wire [LEN_W-1:0]  m_awlen;
    wire [2:0]        m_awsize;
    wire [1:0]        m_awburst;
    wire              m_awvalid, m_awready;
    wire [DATA_W-1:0] m_wdata;
    wire [3:0]        m_wstrb;
    wire              m_wlast, m_wvalid, m_wready;
    wire [ID_W-1:0]   m_bid;
    wire [1:0]        m_bresp;
    wire              m_bvalid, m_bready;
    wire [ID_W-1:0]   m_arid;
    wire [ADDR_W-1:0] m_araddr;
    wire [LEN_W-1:0]  m_arlen;
    wire [2:0]        m_arsize;
    wire [1:0]        m_arburst;
    wire              m_arvalid, m_arready;
    wire [ID_W-1:0]   m_rid;
    wire [DATA_W-1:0] m_rdata;
    wire [1:0]        m_rresp;
    wire              m_rlast, m_rvalid, m_rready;

    wire [NCH-1:0]    irq_done;
    wire              irq_err;

    // 错误注入地址（给存储器模型）：默认给一个永不命中的值
    reg [ADDR_W-1:0]  mem_err_addr = 32'hFFFF_FFFF;

    // ============================================================
    // DUT
    // ============================================================
    dma #(.ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W),
          .LEN_W(LEN_W), .NCH(NCH), .CHAIN_EN(0)) dut (
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
    // 数据口接存储器模型（64 KB，公共件）
    // ============================================================
    axi_mem_model #(.ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W),
                    .MEM_BYTES(65536)) u_mem (
        .clk(clk), .rst_n(rst_n),
        .awid(m_awid), .awaddr(m_awaddr), .awlen(m_awlen), .awsize(m_awsize),
        .awburst(m_awburst), .awvalid(m_awvalid), .awready(m_awready),
        .wdata(m_wdata), .wstrb(m_wstrb), .wlast(m_wlast),
        .wvalid(m_wvalid), .wready(m_wready),
        .bid(m_bid), .bresp(m_bresp), .bvalid(m_bvalid), .bready(m_bready),
        .arid(m_arid), .araddr(m_araddr), .arlen(m_arlen), .arsize(m_arsize),
        .arburst(m_arburst), .arvalid(m_arvalid), .arready(m_arready),
        .rid(m_rid), .rdata(m_rdata), .rresp(m_rresp), .rlast(m_rlast),
        .rvalid(m_rvalid), .rready(m_rready),
        .err_addr(mem_err_addr)
    );

    // ============================================================
    // 检查器
    // ============================================================
    wire [31:0] err_proto_s, err_proto_m, err_id_m;

    axi_protocol_checker #(
        .ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W), .LEN_W(LEN_W),
        .NAME("dma_s"), .ALLOW_WRAP(1)
    ) u_chk_s (
        .clk(clk), .rst_n(rst_n),
        .awid(s_awid), .awaddr(s_awaddr), .awlen(s_awlen), .awsize(s_awsize),
        .awburst(s_awburst), .awvalid(s_awvalid), .awready(s_awready),
        .wdata(s_wdata), .wstrb(s_wstrb), .wlast(s_wlast),
        .wvalid(s_wvalid), .wready(s_wready),
        .bid(s_bid), .bresp(s_bresp), .bvalid(s_bvalid), .bready(s_bready),
        .arid(s_arid), .araddr(s_araddr), .arlen(s_arlen), .arsize(s_arsize),
        .arburst(s_arburst), .arvalid(s_arvalid), .arready(s_arready),
        .rid(s_rid), .rdata(s_rdata), .rresp(s_rresp), .rlast(s_rlast),
        .rvalid(s_rvalid), .rready(s_rready),
        .error_count(err_proto_s)
    );

    axi_protocol_checker #(
        .ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W), .LEN_W(LEN_W),
        .NAME("dma_m"), .ALLOW_WRAP(1)
    ) u_chk_m (
        .clk(clk), .rst_n(rst_n),
        .awid(m_awid), .awaddr(m_awaddr), .awlen(m_awlen), .awsize(m_awsize),
        .awburst(m_awburst), .awvalid(m_awvalid), .awready(m_awready),
        .wdata(m_wdata), .wstrb(m_wstrb), .wlast(m_wlast),
        .wvalid(m_wvalid), .wready(m_wready),
        .bid(m_bid), .bresp(m_bresp), .bvalid(m_bvalid), .bready(m_bready),
        .arid(m_arid), .araddr(m_araddr), .arlen(m_arlen), .arsize(m_arsize),
        .arburst(m_arburst), .arvalid(m_arvalid), .arready(m_arready),
        .rid(m_rid), .rdata(m_rdata), .rresp(m_rresp), .rlast(m_rlast),
        .rvalid(m_rvalid), .rready(m_rready),
        .error_count(err_proto_m)
    );

    axi_id_contract_check #(.ID_W(ID_W), .NCH(NCH), .NAME("dma_m")) u_id_chk (
        .clk(clk), .rst_n(rst_n),
        .awid(m_awid), .awvalid(m_awvalid), .awready(m_awready),
        .bid(m_bid),   .bvalid(m_bvalid),   .bready(m_bready),
        .arid(m_arid), .arvalid(m_arvalid), .arready(m_arready),
        .rid(m_rid),   .rvalid(m_rvalid),   .rready(m_rready),
        .error_count(err_id_m)
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

    // ============================================================
    // 配置口 BFM：单拍写 / 单拍读
    // ============================================================
    task axi_write;
        input [ADDR_W-1:0] a;
        input [DATA_W-1:0] d;
        begin
            @(negedge clk);
            s_awid = 4'd0; s_awaddr = a; s_awlen = 8'd0;
            s_awsize = 3'd2; s_awburst = 2'b01; s_awvalid = 1'b1;
            s_wdata = d; s_wstrb = 4'hF; s_wlast = 1'b1; s_wvalid = 1'b1;
            s_bready = 1'b1;
            while (!(s_awvalid && s_awready)) @(negedge clk);
            @(negedge clk); s_awvalid = 1'b0;

            while (!(s_wvalid && s_wready)) @(negedge clk);
            @(negedge clk); s_wvalid = 1'b0; s_wlast = 1'b0;

            while (!(s_bvalid && s_bready)) @(negedge clk);
            @(negedge clk); s_bready = 1'b0;
        end
    endtask

    task axi_read;
        input  [ADDR_W-1:0] a;
        output [DATA_W-1:0] d;
        begin
            @(negedge clk);
            s_arid = 4'd0; s_araddr = a; s_arlen = 8'd0;
            s_arsize = 3'd2; s_arburst = 2'b01; s_arvalid = 1'b1;
            s_rready = 1'b1;
            while (!(s_arvalid && s_arready)) @(negedge clk);
            @(negedge clk); s_arvalid = 1'b0;

            while (!(s_rvalid && s_rready)) @(negedge clk);
            d = s_rdata;
            @(negedge clk); s_rready = 1'b0;
        end
    endtask

    // ============================================================
    // 配置一个通道并启动它
    // ============================================================
    task cfg_ch;
        input [2:0]    ch;
        input [31:0]   src, dst, len;
        input          src_inc, dst_inc;
        reg   [31:0]   base, ctrl;
        begin
            base = DMA_BASE + ch * 32'h10;
            axi_write(base + 32'h00, src);
            axi_write(base + 32'h04, dst);
            axi_write(base + 32'h08, len);
            // CTRL：bit0 START=1（写后自清）/ bit1 SRC_INC / bit2 DST_INC
            ctrl = {29'd0, dst_inc, src_inc, 1'b1};
            axi_write(base + 32'h0C, ctrl);
        end
    endtask

    // ============================================================
    // 存储器预置 / 检查（层次化引用 u_mem.mem）
    // ============================================================
    task mem_fill;
        input [31:0]  base;
        input integer n;
        input [31:0]  seed;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) begin
                u_mem.mem[base + i*4 + 0] = seed[7:0]   ^ i[7:0];
                u_mem.mem[base + i*4 + 1] = seed[15:8]  ^ i[7:0];
                u_mem.mem[base + i*4 + 2] = seed[23:16] ^ i[7:0];
                u_mem.mem[base + i*4 + 3] = seed[31:24] ^ i[7:0];
            end
        end
    endtask

    task mem_check;
        input [31:0]  base;
        input integer n;
        input [31:0]  seed;
        input [255:0] name;
        integer i;
        reg [31:0] got, exp;
        begin
            for (i = 0; i < n; i = i + 1) begin
                got = {u_mem.mem[base+i*4+3], u_mem.mem[base+i*4+2],
                       u_mem.mem[base+i*4+1], u_mem.mem[base+i*4+0]};
                exp = {seed[31:24]^i[7:0], seed[23:16]^i[7:0],
                       seed[15:8]^i[7:0],  seed[7:0]^i[7:0]};
                checks = checks + 1;
                if (got !== exp) begin
                    errors = errors + 1;
                    $display("  [FAIL] %0s 第 %0d 个字 : got=0x%08X 期望=0x%08X", name, i, got, exp);
                end
            end
        end
    endtask

    // 检查从 base 开始的 n 个字是否【全部等于】同一个值
    // （用于 SRC_INC=0 / DST_INC=0 这类"固定地址"场景）
    task mem_check_same;
        input [31:0]  base;
        input integer n;
        input [31:0]  val;
        input [255:0] name;
        integer j;
        reg [31:0] got;
        begin
            for (j = 0; j < n; j = j + 1) begin
                got = {u_mem.mem[base+j*4+3], u_mem.mem[base+j*4+2],
                       u_mem.mem[base+j*4+1], u_mem.mem[base+j*4+0]};
                checks = checks + 1;
                if (got !== val) begin
                    errors = errors + 1;
                    $display("  [FAIL] %0s 第 %0d 个字 : got=0x%08X 期望=0x%08X", name, j, got, val);
                end
            end
        end
    endtask

    // 等某个通道的搬运结束（busy 落）
    task wait_idle;
        input [2:0] ch;
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

    integer i, k;
    reg [31:0] rd;
    reg [31:0] src_a, dst_a;

    // ============================================================
    initial begin
        $dumpfile("tb_dma.vcd");
        $dumpvars(0, tb_dma);

        repeat (6) @(posedge clk);
        @(negedge clk); rst_n = 1;
        repeat (4) @(posedge clk);

        $display("");
        $display("========== 6 通道 DMA 系统级验证 ==========");

        // ----------------------------------------------------
        // [1] 寄存器读写：CTRL 的 START 自清 + 状态位可读
        // ----------------------------------------------------
        $display("[1] 寄存器读写（CTRL 写 START 后自清，状态位可读）");
        axi_write(DMA_BASE + 32'h0C, 32'h0000_0007);   // START + SRC_INC + DST_INC
        repeat (4) @(negedge clk);
        axi_read(DMA_BASE + 32'h0C, rd);
        chk(rd[0],    1'b0, "CTRL[0] START 写后自清");
        chk(rd[1],    1'b1, "CTRL[1] SRC_INC 保持");
        chk(rd[2],    1'b1, "CTRL[2] DST_INC 保持");

        // 第 2 通道也写一次，确认 6 套寄存器互相独立
        axi_write(DMA_BASE + 32'h10 + 32'h0C, 32'h0000_0001);   // 只有 START
        repeat (4) @(negedge clk);
        axi_read(DMA_BASE + 32'h10 + 32'h0C, rd);
        chk(rd[1], 1'b0, "通道1 的 SRC_INC 未被通道0 影响");

        // ----------------------------------------------------
        // [2] 单拍搬运（LEN=1）
        // ----------------------------------------------------
        $display("[2] 单拍搬运（LEN=1）");
        src_a = SRC_BASE + 0*CH_STRIDE;
        dst_a = DST_BASE + 0*CH_STRIDE;
        mem_fill(src_a, 1, 32'hA1B2_C3D4);
        cfg_ch(3'd0, src_a, dst_a, 32'd1, 1'b1, 1'b1);
        wait_idle(3'd0);
        mem_check(dst_a, 1, 32'hA1B2_C3D4, "单拍搬运");
        chk(irq_done[0], 1'b1, "通道0 irq_done 拉高");

        // ----------------------------------------------------
        // [3] INCR 突发搬运（LEN=4）
        // ----------------------------------------------------
        $display("[3] INCR 突发搬运（LEN=4）");
        src_a = SRC_BASE + 1*CH_STRIDE;
        dst_a = DST_BASE + 1*CH_STRIDE;
        mem_fill(src_a, 4, 32'h1122_3344);
        cfg_ch(3'd1, src_a, dst_a, 32'd4, 1'b1, 1'b1);
        wait_idle(3'd1);
        mem_check(dst_a, 4, 32'h1122_3344, "INCR 突发搬运");

        // ----------------------------------------------------
        // [4] DST_INC=0：固定目的地址（模拟 UART DATA / FIR DIN）
        //     4 个字都写到同一个地址 → 最后留下的是第 4 个字
        // ----------------------------------------------------
        $display("[4] DST_INC=0 固定目的地址（模拟 UART / FIR 的 DIN）");
        src_a = SRC_BASE + 2*CH_STRIDE;
        dst_a = DST_BASE + 2*CH_STRIDE;
        mem_fill(src_a, 4, 32'h5566_7788);
        // 先把目的地址清成已知值
        u_mem.mem[dst_a+0] = 8'h00; u_mem.mem[dst_a+1] = 8'h00;
        u_mem.mem[dst_a+2] = 8'h00; u_mem.mem[dst_a+3] = 8'h00;
        cfg_ch(3'd2, src_a, dst_a, 32'd4, 1'b1, 1'b0);
        wait_idle(3'd2);
        rd = {u_mem.mem[dst_a+3], u_mem.mem[dst_a+2], u_mem.mem[dst_a+1], u_mem.mem[dst_a+0]};
        // 期望是 mem_fill 的第 3 个字（i=3，每个字节 ^3）：
        //   0x55^3=0x56, 0x66^3=0x65, 0x77^3=0x74, 0x88^3=0x8B
        chk(rd, 32'h5665_748B, "固定地址写：应留下最后一个字");

        // ----------------------------------------------------
        // [5] SRC_INC=0：固定源地址（模拟 UART RXDATA / FIR DOUT）
        //     4 次都读同一个地址 → 目的地 4 个字应该完全一样
        // ----------------------------------------------------
        $display("[5] SRC_INC=0 固定源地址（模拟 UART / FIR 的 DOUT）");
        src_a = SRC_BASE + 3*CH_STRIDE;
        dst_a = DST_BASE + 3*CH_STRIDE;
        mem_fill(src_a, 1, 32'hDEAD_BEEF);
        cfg_ch(3'd3, src_a, dst_a, 32'd4, 1'b0, 1'b1);
        wait_idle(3'd3);
        // 源地址固定 → 4 次都读同一个字 → 目的地的 4 个字应该完全相同
        mem_check_same(dst_a, 4, 32'hDEAD_BEEF, "固定地址读：4 个字应相同");

        // ----------------------------------------------------
        // [6] 6 通道并发
        // ----------------------------------------------------
        $display("[6] 6 通道并发启动（仲裁不能饿死任何一个）");
        for (i = 0; i < 6; i = i + 1) begin
            src_a = SRC_BASE + (i + 8) * CH_STRIDE;
            dst_a = DST_BASE + (i + 8) * CH_STRIDE;
            mem_fill(src_a, 8, 32'h0100_0000 + i);
            // 只写配置，不启动
            axi_write(DMA_BASE + i*32'h10 + 32'h00, src_a);
            axi_write(DMA_BASE + i*32'h10 + 32'h04, dst_a);
            axi_write(DMA_BASE + i*32'h10 + 32'h08, 32'd8);
        end
        // 一次性把 6 个通道全部启动
        for (i = 0; i < 6; i = i + 1)
            axi_write(DMA_BASE + i*32'h10 + 32'h0C, 32'h0000_0007);
        for (i = 0; i < 6; i = i + 1) wait_idle(i[2:0]);
        for (i = 0; i < 6; i = i + 1) begin
            dst_a = DST_BASE + (i + 8) * CH_STRIDE;
            mem_check(dst_a, 8, 32'h0100_0000 + i, "并发通道");
        end
        chk({26'd0, irq_done}, 6'b111111, "6 个通道的 irq_done 都拉高");

        // ----------------------------------------------------
        // [7] 错误响应 → irq_err
        // ----------------------------------------------------
        $display("[7] 错误注入（源地址读回 SLVERR）-> irq_err 拉高");
        src_a = SRC_BASE + 20*CH_STRIDE;
        dst_a = DST_BASE + 20*CH_STRIDE;
        mem_err_addr = src_a;                       // 让源地址的读事务报错
        cfg_ch(3'd4, src_a, dst_a, 32'd2, 1'b1, 1'b1);
        // 等 err 出现
        k = 0;
        while (irq_err !== 1'b1 && k < 20000) begin
            @(negedge clk);
            k = k + 1;
        end
        repeat (4) @(negedge clk);
        chk(irq_err, 1'b1, "出错后 irq_err 拉高");
        mem_err_addr = 32'hFFFF_FFFF;               // 关掉错误注入
        axi_read(DMA_BASE + 4*32'h10 + 32'h0C, rd);
        chk(rd[29], 1'b1, "通道4 的 CTRL[29] ERR 置位");

        // ----------------------------------------------------
        // [8] 协议检查器汇总
        // ----------------------------------------------------
        repeat (20) @(negedge clk);
        $display("[8] 协议检查器汇总");
        $display("      配置口 AXI 协议违规 : %0d", err_proto_s);
        $display("      数据口 AXI 协议违规 : %0d", err_proto_m);
        $display("      数据口 ID 契约违规  : %0d", err_id_m);
        checks = checks + 3;
        if (err_proto_s !== 0) begin errors = errors + 1; $display("  [FAIL] 配置口有 AXI 协议违规"); end
        if (err_proto_m !== 0) begin errors = errors + 1; $display("  [FAIL] 数据口有 AXI 协议违规"); end
        if (err_id_m    !== 0) begin errors = errors + 1; $display("  [FAIL] 数据口违反契约C（ID 编码）"); end

        // ----------------------------------------------------
        $display("");
        $display("============================================");
        if (errors == 0)
            $display("===== PASS: %0d 项检查全部通过，AXI 协议与契约C 零违规 =====", checks);
        else
            $display("===== FAIL: %0d 项检查中 %0d 项失败 =====", checks, errors);
        $display("============================================");
        $finish;
    end

    initial begin
        #3000000;
        $display("!!!! TIMEOUT：仿真超时，测试未正常结束");
        $finish;
    end

endmodule

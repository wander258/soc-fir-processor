// ============================================================
// tb_dma_self.v —— DMA 顶层自测（阶段3 分工 A 的最小自测）
//
// 覆盖 docs/阶段3-任务A交接文档.md §5 的最小集：
//   [1] 配置口写 4 寄存器 → 读回 CTRL 校验 DONE/BUSY/ERR/INC 映射
//   [2] 写 CTRL[0]=1 → 观察 cfg_ctrl[0][0] 产一拍脉冲
//   [3] 单通道 SRAM→SRAM 搬 4 字 → 轮询 CTRL 等 DONE → irq_done[0]=1, irq_err=0
//   [4] LEN=0 = 传 0 个字 → 立即 DONE、不产生 AXI 事务
//   另挂 axi_protocol_checker（主口 SIDE=1 / 从口 SIDE=0）全程零违规
//
// 运行：
//   iverilog -g2012 -Wall -o sim.out RTL/dma.v RTL/dma_regs.v RTL/dma_engine.v \
//             RTL/sync_fifo.v RTL/axi_arbiter.v TB/axi_protocol_checker.v TB/tb_dma_self.v
//   vvp sim.out
// ============================================================
`timescale 1ns/1ps

// ------------------------------------------------------------
// 简单 AXI4 从设备存储器模型（当 DMA 数据口的对手，地址 64KB）
// ------------------------------------------------------------
module axi_sram_model #(
    parameter MEM_BYTES = 65536
)(
    input  wire          clk,
    input  wire          rst_n,
    input  wire [3:0]    awid,
    input  wire [31:0]   awaddr,
    input  wire [7:0]    awlen,
    input  wire [2:0]    awsize,
    input  wire [1:0]    awburst,
    input  wire          awvalid,
    output wire          awready,
    input  wire [31:0]   wdata,
    input  wire [3:0]    wstrb,
    input  wire          wlast,
    input  wire          wvalid,
    output wire          wready,
    output wire [3:0]    bid,
    output wire [1:0]    bresp,
    output wire          bvalid,
    input  wire          bready,
    input  wire [3:0]    arid,
    input  wire [31:0]   araddr,
    input  wire [7:0]    arlen,
    input  wire [2:0]    arsize,
    input  wire [1:0]    arburst,
    input  wire          arvalid,
    output wire          arready,
    output wire [3:0]    rid,
    output wire [31:0]   rdata,
    output wire [1:0]    rresp,
    output wire          rlast,
    output wire          rvalid,
    input  wire          rready
);
    reg [7:0] mem [0:MEM_BYTES-1];

    // ---- 写侧 ----
    reg        w_busy;
    reg [3:0]  w_id;
    reg [31:0] w_addr;
    reg [7:0]  w_beat;
    reg [2:0]  w_size;
    reg [1:0]  w_burst;
    reg        bvalid_r;

    assign awready = !w_busy;
    assign wready  = w_busy;
    assign bvalid  = bvalid_r;
    assign bid     = w_id;
    assign bresp   = 2'b00;

    always @(posedge clk or negedge rst_n) begin
        integer i;
        if (!rst_n) begin
            w_busy   <= 1'b0;
            bvalid_r <= 1'b0;
            for (i = 0; i < MEM_BYTES; i = i + 1) mem[i] <= 8'h00;
        end
        else begin
            if (awvalid && awready) begin
                w_busy  <= 1'b1;
                w_id    <= awid;
                w_addr  <= awaddr;
                w_size  <= awsize;
                w_burst <= awburst;
                w_beat  <= 8'd0;
            end
            if (w_busy && wvalid && wready) begin
                for (i = 0; i < 4; i = i + 1)
                    if (wstrb[i]) mem[w_addr + (w_beat << w_size) + i] <= wdata[8*i +: 8];
                if (wlast) begin
                    w_busy   <= 1'b0;
                    bvalid_r <= 1'b1;
                end
                else w_beat <= w_beat + 8'd1;
            end
            if (bvalid_r && bready) bvalid_r <= 1'b0;
        end
    end

    // ---- 读侧 ----
    reg        r_busy;
    reg [3:0]  r_id;
    reg [31:0] r_addr;
    reg [7:0]  r_beat, r_len;
    reg [2:0]  r_size;
    reg [1:0]  r_burst;

    wire [31:0] r_addr_cur = (r_burst == 2'b00) ? r_addr : (r_addr + (r_beat << r_size));

    assign arready = !r_busy;
    assign rvalid  = r_busy;
    assign rid     = r_id;
    assign rresp   = 2'b00;
    assign rlast   = (r_beat == r_len);
    assign rdata   = {mem[r_addr_cur+3], mem[r_addr_cur+2], mem[r_addr_cur+1], mem[r_addr_cur+0]};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_busy <= 1'b0;
        end
        else begin
            if (arvalid && arready) begin
                r_busy  <= 1'b1;
                r_id    <= arid;
                r_addr  <= araddr;
                r_len   <= arlen;
                r_size  <= arsize;
                r_burst <= arburst;
                r_beat  <= 8'd0;
            end
            if (r_busy && rvalid && rready) begin
                if (rlast) r_busy <= 1'b0;
                else       r_beat <= r_beat + 8'd1;
            end
        end
    end

endmodule


// ------------------------------------------------------------
// 顶层测试台
// ------------------------------------------------------------
module tb_dma_self;

    reg clk   = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;

    // ---- 配置口（s_axi，TB 当主设备）----
    reg  [3:0]  s_awid;
    reg  [31:0] s_awaddr;
    reg  [7:0]  s_awlen;
    reg  [2:0]  s_awsize;
    reg  [1:0]  s_awburst;
    reg         s_awvalid;
    wire        s_awready;
    reg  [31:0] s_wdata;
    reg  [3:0]  s_wstrb;
    reg         s_wlast;
    reg         s_wvalid;
    wire        s_wready;
    wire [3:0]  s_bid;
    wire [1:0]  s_bresp;
    wire        s_bvalid;
    reg         s_bready;
    reg  [3:0]  s_arid;
    reg  [31:0] s_araddr;
    reg  [7:0]  s_arlen;
    reg  [2:0]  s_arsize;
    reg  [1:0]  s_arburst;
    reg         s_arvalid;
    wire        s_arready;
    wire [3:0]  s_rid;
    wire [31:0] s_rdata;
    wire [1:0]  s_rresp;
    wire        s_rlast;
    wire        s_rvalid;
    reg         s_rready;

    // ---- 数据口（m_axi，连存储器模型）----
    wire [3:0]  m_awid;
    wire [31:0] m_awaddr;
    wire [7:0]  m_awlen;
    wire [2:0]  m_awsize;
    wire [1:0]  m_awburst;
    wire        m_awvalid;
    wire        m_awready;
    wire [31:0] m_wdata;
    wire [3:0]  m_wstrb;
    wire        m_wlast;
    wire        m_wvalid;
    wire        m_wready;
    wire [3:0]  m_bid;
    wire [1:0]  m_bresp;
    wire        m_bvalid;
    wire        m_bready;
    wire [3:0]  m_arid;
    wire [31:0] m_araddr;
    wire [7:0]  m_arlen;
    wire [2:0]  m_arsize;
    wire [1:0]  m_arburst;
    wire        m_arvalid;
    wire        m_arready;
    wire [3:0]  m_rid;
    wire [31:0] m_rdata;
    wire [1:0]  m_rresp;
    wire        m_rlast;
    wire        m_rvalid;
    wire        m_rready;

    wire [5:0] irq_done;
    wire       irq_err;

    dma #(.ADDR_W(32), .DATA_W(32), .ID_W(4), .LEN_W(8), .NCH(6)) u_dut (
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

    axi_sram_model #(.MEM_BYTES(65536)) u_mem (
        .clk(clk), .rst_n(rst_n),
        .awid(m_awid), .awaddr(m_awaddr), .awlen(m_awlen), .awsize(m_awsize), .awburst(m_awburst),
        .awvalid(m_awvalid), .awready(m_awready),
        .wdata(m_wdata), .wstrb(m_wstrb), .wlast(m_wlast), .wvalid(m_wvalid), .wready(m_wready),
        .bid(m_bid), .bresp(m_bresp), .bvalid(m_bvalid), .bready(m_bready),
        .arid(m_arid), .araddr(m_araddr), .arlen(m_arlen), .arsize(m_arsize), .arburst(m_arburst),
        .arvalid(m_arvalid), .arready(m_arready),
        .rid(m_rid), .rdata(m_rdata), .rresp(m_rresp), .rlast(m_rlast), .rvalid(m_rvalid), .rready(m_rready)
    );

    // ---- AXI 协议检查器：数据口（SIDE=1）----
    wire [31:0] chk_m_err;
    axi_protocol_checker #(
        .ADDR_W(32), .DATA_W(32), .ID_W(4), .LEN_W(8), .NAME("dma_m"), .SIDE(1)
    ) u_chk_m (
        .clk(clk), .rst_n(rst_n),
        .awid(m_awid), .awaddr(m_awaddr), .awlen(m_awlen), .awsize(m_awsize), .awburst(m_awburst),
        .awvalid(m_awvalid), .awready(m_awready),
        .wdata(m_wdata), .wstrb(m_wstrb), .wlast(m_wlast), .wvalid(m_wvalid), .wready(m_wready),
        .bid(m_bid), .bresp(m_bresp), .bvalid(m_bvalid), .bready(m_bready),
        .arid(m_arid), .araddr(m_araddr), .arlen(m_arlen), .arsize(m_arsize), .arburst(m_arburst),
        .arvalid(m_arvalid), .arready(m_arready),
        .rid(m_rid), .rdata(m_rdata), .rresp(m_rresp), .rlast(m_rlast), .rvalid(m_rvalid), .rready(m_rready),
        .error_count(chk_m_err)
    );

    // ---- AXI 协议检查器：配置口（SIDE=0）----
    wire [31:0] chk_s_err;
    axi_protocol_checker #(
        .ADDR_W(32), .DATA_W(32), .ID_W(4), .LEN_W(8), .NAME("dma_s"), .SIDE(0)
    ) u_chk_s (
        .clk(clk), .rst_n(rst_n),
        .awid(s_awid), .awaddr(s_awaddr), .awlen(s_awlen), .awsize(s_awsize), .awburst(s_awburst),
        .awvalid(s_awvalid), .awready(s_awready),
        .wdata(s_wdata), .wstrb(s_wstrb), .wlast(s_wlast), .wvalid(s_wvalid), .wready(s_wready),
        .bid(s_bid), .bresp(s_bresp), .bvalid(s_bvalid), .bready(s_bready),
        .arid(s_arid), .araddr(s_araddr), .arlen(s_arlen), .arsize(s_arsize), .arburst(s_arburst),
        .arvalid(s_arvalid), .arready(s_arready),
        .rid(s_rid), .rdata(s_rdata), .rresp(s_rresp), .rlast(s_rlast), .rvalid(s_rvalid), .rready(s_rready),
        .error_count(chk_s_err)
    );

    // ---- START 一拍脉冲计数（观察 ch0 的 cfg_ctrl[0]）----
    reg [7:0] pulse_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) pulse_cnt <= 8'd0;
        else if (u_dut.cfg_ctrl[0]) pulse_cnt <= pulse_cnt + 8'd1;
    end

    // ============================================================
    // 统计与检查
    // ============================================================
    integer errors = 0;
    integer checks = 0;

    task chk;
        input [31:0]   got;
        input [31:0]   exp;
        input [255:0]  name;
        begin
            checks = checks + 1;
            if (got !== exp) begin
                errors = errors + 1;
                $display("  [FAIL] %0s : got=0x%08X  期望=0x%08X", name, got, exp);
            end
        end
    endtask

    // ---- 配置口写（单拍）----
    // 约定：激励在下降沿改变；握手在上升沿完成；握手后的下个下降沿再撤信号，
    // 避免在同一拍用阻塞赋值撤 ready/valid 造成协议检查器误判或握手竞态。
    task cfg_write;
        input [31:0] addr;
        input [31:0] data;
        output [1:0] resp;
        begin
            @(negedge clk);
            s_awid = 4'd0; s_awaddr = addr; s_awlen = 8'd0; s_awsize = 3'd2; s_awburst = 2'b01;
            s_awvalid = 1'b1;
            while (s_awready !== 1'b1) @(posedge clk);
            @(posedge clk);
            @(negedge clk);
            s_awvalid = 1'b0;

            @(negedge clk);
            s_wdata = data; s_wstrb = 4'hF; s_wlast = 1'b1; s_wvalid = 1'b1;
            while (s_wready !== 1'b1) @(posedge clk);
            @(posedge clk);
            @(negedge clk);
            s_wvalid = 1'b0;

            @(negedge clk);
            s_bready = 1'b1;
            while (s_bvalid !== 1'b1) @(posedge clk);
            resp = s_bresp;
            @(posedge clk);
            @(negedge clk);
            s_bready = 1'b0;
        end
    endtask

    // ---- 配置口读（单拍）----
    task cfg_read;
        input  [31:0] addr;
        output [31:0] data;
        output [1:0]  resp;
        begin
            @(negedge clk);
            s_arid = 4'd0; s_araddr = addr; s_arlen = 8'd0; s_arsize = 3'd2; s_arburst = 2'b01;
            s_arvalid = 1'b1;
            while (s_arready !== 1'b1) @(posedge clk);
            @(posedge clk);
            @(negedge clk);
            s_arvalid = 1'b0;

            @(negedge clk);
            s_rready = 1'b1;
            while (s_rvalid !== 1'b1) @(posedge clk);
            data = s_rdata; resp = s_rresp;
            @(posedge clk);
            @(negedge clk);
            s_rready = 1'b0;
        end
    endtask

    // ---- 预填/检查存储器模型 ----
    task preload;
        input [31:0] addr;
        input [31:0] val;
        begin
            u_mem.mem[addr+0] = val[7:0];
            u_mem.mem[addr+1] = val[15:8];
            u_mem.mem[addr+2] = val[23:16];
            u_mem.mem[addr+3] = val[31:24];
        end
    endtask

    task chk_mem;
        input [31:0]  addr;
        input [31:0]  exp;
        input [255:0] name;
        begin
            chk({u_mem.mem[addr+3], u_mem.mem[addr+2], u_mem.mem[addr+1], u_mem.mem[addr+0]},
                exp, name);
        end
    endtask

    // ---- 轮询通道 ch 的 CTRL，等 DONE（bit31）----
    task wait_done;
        input  [3:0] ch;
        integer t;
        reg [31:0] rd;
        reg [1:0]  rp;
        reg found;
        begin
            t = 0; rd = 0; found = 0;
            while (t < 20000 && !found) begin
                cfg_read(32'h4000_1000 + (ch << 4) + 32'h0C, rd, rp);
                if (rd[31]) found = 1;
                else        t = t + 1;
            end
            if (!found) begin
                errors = errors + 1;
                $display("  [FAIL] 通道%0d 等待 DONE 超时", ch);
            end
        end
    endtask

    // ============================================================
    // 测试序列
    // ============================================================
    reg [31:0] rd;
    reg [1:0]  rp;
    integer i, j;

    initial begin
        $dumpfile("tb_dma_self.vcd");
        $dumpvars(0, tb_dma_self);

        s_awid=0; s_awaddr=0; s_awlen=0; s_awsize=0; s_awburst=0; s_awvalid=0;
        s_wdata=0; s_wstrb=0; s_wlast=0; s_wvalid=0; s_bready=0;
        s_arid=0; s_araddr=0; s_arlen=0; s_arsize=0; s_arburst=0; s_arvalid=0; s_rready=0;

        rst_n = 0;
        repeat (5) @(posedge clk);
        @(negedge clk); rst_n = 1;
        repeat (3) @(posedge clk);

        $display("");
        $display("========== DMA 顶层自测 ==========");

        // ----------------------------------------------------
        // [1] 配置通路：写 4 寄存器 + 读回 CTRL 校验映射
        // ----------------------------------------------------
        $display("[1] 配置通路 / CTRL 读回映射");
        cfg_write(32'h4000_1000 + 32'h00, 32'h0000_1000, rp);  // ch0 SRC
        cfg_write(32'h4000_1000 + 32'h04, 32'h0000_2000, rp);  // ch0 DST
        cfg_write(32'h4000_1000 + 32'h08, 32'd4,        rp);  // ch0 LEN
        cfg_write(32'h4000_1000 + 32'h0C, 32'h0000_0006, rp);  // ch0 CTRL = SRC_INC|DST_INC（不启动）

        cfg_read(32'h4000_1000 + 32'h0C, rd, rp);
        chk({31'd0, rp}, 32'd0, "读 CTRL 响应应为 OKAY");
        chk(rd[31:29], 3'b000, "初始 DONE/BUSY/ERR = 000");
        chk(rd[2:1], 2'b11, "SRC_INC/DST_INC 读回 = 11");
        chk({31'd0, rd[0]}, 32'd0, "START 读回恒 0");

        // 读 SRC 应 SLVERR（只读限制）
        cfg_read(32'h4000_1000 + 32'h00, rd, rp);
        chk({31'd0, rp}, 32'd2, "读 SRC 应 SLVERR");

        // 非法区读（通道 6）应 SLVERR
        cfg_read(32'h4000_1060, rd, rp);
        chk({31'd0, rp}, 32'd2, "读非法地址应 SLVERR");

        // ----------------------------------------------------
        // [2] 预填源数据 + START 一拍脉冲（写 CTRL[0]=1）
        // ----------------------------------------------------
        $display("[2] 预填源数据 + START 一拍脉冲");
        for (i = 0; i < 4; i = i + 1)
            preload(32'h0000_1000 + 4*i, 32'hA0 + i);
        @(negedge clk);
        pulse_cnt = 8'd0;
        cfg_write(32'h4000_1000 + 32'h0C, 32'h0000_0007, rp);  // START|SRC_INC|DST_INC
        @(negedge clk);
        chk({24'd0, pulse_cnt}, 32'd1, "cfg_ctrl[0][0] 恰好产一拍脉冲");

        // ----------------------------------------------------
        // [3] 单通道 SRAM→SRAM 搬 4 字
        // ----------------------------------------------------
        $display("[3] 单通道 SRAM→SRAM 搬 4 字");
        // SRC/DST/LEN/CTRL 已在 [1] 配好，[2] 的 CTRL 写已触发 START
        wait_done(4'd0);
        chk({31'd0, irq_done[0]}, 32'd1, "irq_done[0]=1");
        chk({31'd0, irq_err}, 32'd0, "irq_err=0");
        for (i = 0; i < 4; i = i + 1)
            chk_mem(32'h0000_2000 + 4*i, 32'hA0 + i, "搬运结果");
        // 读回 CTRL：DONE=1
        cfg_read(32'h4000_1000 + 32'h0C, rd, rp);
        chk({31'd0, rd[31]}, 32'd1, "搬运后 CTRL[31] DONE=1");
        chk({31'd0, rd[30]}, 32'd0, "搬运后 CTRL[30] BUSY=0");

        // ----------------------------------------------------
        // [4] LEN=0 = 传 0 个字 → 立即 DONE、无 AXI 事务
        // ----------------------------------------------------
        $display("[4] LEN=0 立即 DONE");
        cfg_write(32'h4000_1000 + 32'h10, 32'h0000_3000, rp);  // ch1 SRC
        cfg_write(32'h4000_1000 + 32'h14, 32'h0000_4000, rp);  // ch1 DST
        cfg_write(32'h4000_1000 + 32'h18, 32'd0,        rp);  // ch1 LEN=0
        cfg_write(32'h4000_1000 + 32'h1C, 32'h0000_0001, rp);  // ch1 CTRL = START
        wait_done(4'd1);
        cfg_read(32'h4000_1000 + 32'h1C, rd, rp);
        chk({31'd0, rd[31]}, 32'd1, "LEN=0 后 DONE=1");
        chk({31'd0, rd[30]}, 32'd0, "LEN=0 后 BUSY=0");
        chk({31'd0, irq_done[1]}, 32'd1, "ch1 irq_done=1");

        // ----------------------------------------------------
        // [5] 6 通道并发：源/目的各不同，验证 6→1 仲裁 + ID[3:1] 回选
        // ----------------------------------------------------
        $display("[5] 6 通道并发");
        for (i = 0; i < 6; i = i + 1) begin
            cfg_write(32'h4000_1000 + (i << 4) + 32'h00, 32'h0000_4000 + i*32'h100, rp); // SRC
            cfg_write(32'h4000_1000 + (i << 4) + 32'h04, 32'h0000_6000 + i*32'h100, rp); // DST
            cfg_write(32'h4000_1000 + (i << 4) + 32'h08, 32'd8, rp);                    // LEN=8
            for (j = 0; j < 8; j = j + 1)
                preload(32'h0000_4000 + i*32'h100 + 4*j, (i << 8) + j);
        end
        // 启动 6 个通道（预填全部完成后才启动）
        for (i = 0; i < 6; i = i + 1)
            cfg_write(32'h4000_1000 + (i << 4) + 32'h0C, 32'h0000_0007, rp); // START|SRC_INC|DST_INC
        for (i = 0; i < 6; i = i + 1) wait_done(4'(i));
        chk({26'd0, irq_done}, 32'h3F, "6 通道 irq_done 全 1");
        chk({31'd0, irq_err}, 32'd0, "irq_err=0");
        for (i = 0; i < 6; i = i + 1)
            for (j = 0; j < 8; j = j + 1)
                chk_mem(32'h0000_6000 + i*32'h100 + 4*j, (i << 8) + j, "6ch 搬运");

        // ----------------------------------------------------
        repeat (10) @(posedge clk);
        $display("");
        $display("============================================");
        chk(chk_m_err, 32'd0, "axi_protocol_checker(m) error_count");
        chk(chk_s_err, 32'd0, "axi_protocol_checker(s) error_count");
        if (errors == 0)
            $display("===== PASS: %0d 项检查全部通过，AXI 协议零违规 =====", checks);
        else
            $display("===== FAIL: %0d 项检查中 %0d 项失败 =====", checks, errors);
        $display("============================================");
        $finish;
    end

    // 超时保护
    initial begin
        #4000000;
        $display("!!!! TIMEOUT：仿真超时");
        $finish;
    end

endmodule

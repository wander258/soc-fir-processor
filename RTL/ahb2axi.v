// ============================================================
// ahb2axi.v —— AHB-Lite 从口 → AXI4 主口 协议桥（阶段2 分工 B）
//
// ============================================================
// 【接口契约】docs/任务四_模块接口信号清单.md 1.2 节（对外端口）
// ============================================================
//   AHB-Lite 从口（接 Cortex-M0，HSEL 恒 1 或来自译码）：
//     HADDR/HTRANS/HWRITE/HSIZE/HBURST/HPROT/HWDATA/HSEL   （入）
//     HRDATA/HREADY/HRESP                                 （出）
//   AXI4 主口（接 AXI 互连 s0 口，主设备 ID=0）：
//     AW/W/B/AR/R 五通道，awid/arid 恒 0
//
//   ⚠️ HRESP 位宽：任务四 1.2 表里写 "HRESP out 2"，但 AHB-Lite 与
//      Cortex-M0 DesignStart 的 HRESP 都是 1 位（0=OKAY，1=ERROR），
//      这里按 1 位实现（与 M0 的 hresp_i 对齐）。
//   ⚠️ HREADY：任务四只列 HREADY（出）。AHB 从设备标准里还有 HREADY（入）
//      = 全系统"上一拍是否完成"。本桥是 M0 唯一 AHB 从设备，系统 HREADY
//      就是自身 HREADY 的回环，故内部用 hready_sys = HREADY 代替。
//
// ============================================================
// 【AHB-Lite → AXI 翻译】
// ============================================================
//   写：地址期锁存 HADDR → AXI AW；数据期 HWDATA → AXI W；B 响应 → HRESP
//   读：地址期锁存 HADDR → AXI AR；R 数据 → HRDATA；R 响应 → HRESP
//
//   HSIZE → AWSIZE/ARSIZE（两者编码相同，直接透传）：
//     000=字节 / 001=半字 / 010=字（M0 只用这三种）
//
//   HBURST → AXI 突发（本桥统一映射成 INCR，长度封顶 16 拍，与赛题包桥一致）：
//     SINGLE(000)        → INCR, LEN=0
//     INCR(001)          → INCR, LEN=15（不定长，按 16 拍封顶）
//     WRAP4/INCR4        → INCR, LEN=3
//     WRAP8/INCR8        → INCR, LEN=7
//     WRAP16/INCR16      → INCR, LEN=15
//     （M0 实际只发 SINGLE 和短 INCR；WRAP 映射成等长 INCR，避免下游 SLVERR）
//
//   WSTRB（本模块最容易错的地方，由 HSIZE + 当前拍地址低两位生成）：
//     字节   HSIZE=0 → 0001 << addr[1:0]
//     半字   HSIZE=1 → 0011 << addr[1:0]   （半字地址 bit0 必须为 0）
//     字     HSIZE>=2 → 1111
//   写数据：HWDATA 直接透传。Cortex-M0 窄写会把数据复制到所有 byte lane，
//   地址选中的 lane 上一定有正确数据，配合 WSTRB 只写有效 lane。
//   读数据：R_DATA 直接透传。AXI 从设备窄读时数据本就落在地址选中的 lane 上，
//   M0 按 HADDR[1:0] 取对应 lane，无需桥再做搬移。
//
// ============================================================
// 【VALID/READY 铁律】
// ============================================================
//   AXI 主口的 VALID 都是寄存器输出，握手完成前不撤销；READY 独立于 VALID。
//   桥内部无组合环（地址锁存、数据/响应都由寄存器打拍）。
//
// ============================================================
// 【验证】TB/tb_ahb2axi.v
// ============================================================
//   三种 HSIZE 的读写落到正确 byte lane / INCR 突发地址递增 / WLAST、RLAST /
//   AWID/ARID=0 / 错误贯通（AXI SLVERR → AHB HRESP=1）/ 长时间随机无死锁。
// ============================================================
`timescale 1ns/1ps

module ahb2axi #(
    parameter ADDR_W = 32,
    parameter DATA_W = 32,
    parameter ID_W   = 4
)(
    input  wire                 clk,
    input  wire                 rst_n,

    // ---- AHB-Lite 从口（任务四 1.2 / 0.4，接 Cortex-M0）----
    input  wire                 HSEL,
    input  wire [ADDR_W-1:0]    HADDR,
    input  wire [1:0]           HTRANS,
    input  wire                 HWRITE,
    input  wire [2:0]           HSIZE,
    input  wire [2:0]           HBURST,
    input  wire [3:0]           HPROT,
    input  wire [DATA_W-1:0]    HWDATA,
    output wire [DATA_W-1:0]    HRDATA,
    output wire                 HREADY,
    output wire                 HRESP,

    // ---- AXI4 主口（任务四 0.3，主设备 ID=0）----
    output wire [ID_W-1:0]      m_axi_awid,
    output wire [ADDR_W-1:0]    m_axi_awaddr,
    output wire [7:0]           m_axi_awlen,
    output wire [2:0]           m_axi_awsize,
    output wire [1:0]           m_axi_awburst,
    output wire                 m_axi_awvalid,
    input  wire                 m_axi_awready,
    output wire [DATA_W-1:0]    m_axi_wdata,
    output wire [DATA_W/8-1:0]  m_axi_wstrb,
    output wire                 m_axi_wlast,
    output wire                 m_axi_wvalid,
    input  wire                 m_axi_wready,
    input  wire [ID_W-1:0]      m_axi_bid,
    input  wire [1:0]           m_axi_bresp,
    input  wire                 m_axi_bvalid,
    output wire                 m_axi_bready,
    output wire [ID_W-1:0]      m_axi_arid,
    output wire [ADDR_W-1:0]    m_axi_araddr,
    output wire [7:0]           m_axi_arlen,
    output wire [2:0]           m_axi_arsize,
    output wire [1:0]           m_axi_arburst,
    output wire                 m_axi_arvalid,
    input  wire                 m_axi_arready,
    input  wire [ID_W-1:0]      m_axi_rid,
    input  wire [DATA_W-1:0]    m_axi_rdata,
    input  wire [1:0]           m_axi_rresp,
    input  wire                 m_axi_rlast,
    input  wire                 m_axi_rvalid,
    output wire                 m_axi_rready
);

    // ============================================================
    // 0. 常量
    // ============================================================
    localparam HTRANS_IDLE   = 2'b00;
    localparam HTRANS_BUSY   = 2'b01;
    localparam HTRANS_NONSEQ = 2'b10;
    localparam HTRANS_SEQ    = 2'b11;

    localparam HBURST_SINGLE = 3'b000;
    localparam HBURST_INCR   = 3'b001;
    localparam HBURST_WRAP4  = 3'b010;
    localparam HBURST_INCR4  = 3'b011;
    localparam HBURST_WRAP8  = 3'b100;
    localparam HBURST_INCR8  = 3'b101;
    localparam HBURST_WRAP16 = 3'b110;
    localparam HBURST_INCR16 = 3'b111;

    localparam AXBURST_INCR  = 2'b01;

    // ============================================================
    // 1. 内部寄存器 / 线网（全部先声明，供下方使用）
    // ============================================================
    // AHB 地址期状态机
    localparam STA_IDLE = 1'b0;
    localparam STA_ADDR = 1'b1;
    reg sta_cur, sta_next;

    // AHB 数据期状态机
    localparam STD_IDLE  = 2'd0;
    localparam STD_WDATA = 2'd1;
    localparam STD_WRESP = 2'd2;
    localparam STD_RDATA = 2'd3;
    reg [1:0] std_cur, std_next;

    // AXI 写地址 AW
    localparam AW_IDLE = 2'd0;
    localparam AW_REQ  = 2'd1;
    localparam AW_DONE = 2'd2;
    reg [1:0] aw_cur, aw_next;

    // AXI 写数据/响应 W/B
    localparam WB_IDLE  = 2'd0;
    localparam WB_DATA  = 2'd1;
    localparam WB_BURST = 2'd2;   // 拍间空档：WVALID 拉低一拍，让主设备放下一拍数据
    localparam WB_RESP  = 2'd3;
    reg [1:0] wb_cur, wb_next;

    // AXI 读地址 AR
    localparam AR_IDLE = 2'd0;
    localparam AR_REQ  = 2'd1;
    localparam AR_DONE = 2'd2;
    reg [1:0] ar_cur, ar_next;

    // AXI 读数据 R
    localparam R_IDLE  = 2'd0;
    localparam R_DATA  = 2'd1;
    localparam R_BURST = 2'd2;   // 拍间空档：RREADY 拉低一拍，HREADY 才会在拍间回落
    reg [1:0] r_cur, r_next;

    // 突发参数锁存
    reg [ADDR_W-1:0] b_addr;
    reg [2:0]        b_size;
    reg [7:0]        b_len;

    // 拍计数
    reg [7:0] w_beat;
    reg [7:0] r_beat;

    // HREADY / HRESP
    reg        hready_r;
    reg        hresp_r;
    reg        w_ack_reg;

    // 握手与标志线网
    wire                hready_sys;
    wire                start_burst;
    wire                w_data_req;
    wire                r_data_req;
    wire                w_ack;
    wire                b_ack;
    wire                r_ack;
    wire [ADDR_W-1:0]   w_addr;
    wire                r_done;
    wire                b_err;
    wire                r_err;

    // ============================================================
    // 2. 基础线网
    // ============================================================
    // 单从设备：系统 HREADY = 自身 HREADY 回环
    assign hready_sys = hready_r;

    // 突发起点（NONSEQ 且系统就绪，且必须处于 IDLE —— 防止完成那一拍重复触发）
    assign start_burst = HSEL && hready_sys && (HTRANS == HTRANS_NONSEQ)
                       && (sta_cur == STA_IDLE);

    // 突发首拍的方向请求（单拍脉冲，方向用 HWRITE 现场值）
    assign w_data_req = HWRITE && start_burst;
    assign r_data_req = !HWRITE && start_burst;

    // AXI 握手
    assign w_ack = m_axi_wvalid && m_axi_wready;
    assign b_ack = m_axi_bready && m_axi_bvalid;
    assign r_ack = m_axi_rready && m_axi_rvalid;

    // 当前 W 拍的地址（AW 起始地址 + 已握手拍数 × 步长），用于算 WSTRB
    assign w_addr = b_addr + ({{(ADDR_W-8){1'b0}}, w_beat} << b_size);

    // 读突发结束标志（最后一拍握手）
    assign r_done      = r_ack && (r_beat == b_len);

    // 响应错误
    assign b_err = b_ack && m_axi_bresp[1];
    assign r_err = r_ack && m_axi_rresp[1];

    // ============================================================
    // 3. 组合逻辑 · 次态
    // ============================================================
    // ---- AHB 地址期状态机 ----
    always @(*) begin
        sta_next = sta_cur;
        case (sta_cur)
            STA_IDLE : if (start_burst)              sta_next = STA_ADDR;
            STA_ADDR : if (HTRANS == HTRANS_IDLE)    sta_next = STA_IDLE;
            default  :                               sta_next = STA_IDLE;
        endcase
    end

    // ---- AHB 数据期状态机 ----
    always @(*) begin
        std_next = std_cur;
        case (std_cur)
            STD_IDLE: begin
                if (w_data_req)                 std_next = STD_WDATA;
                else if (r_data_req)            std_next = STD_RDATA;
            end
            STD_WDATA: begin
                if (w_ack && (w_beat == b_len)) std_next = STD_WRESP;
            end
            STD_WRESP: begin
                if (b_ack)                      std_next = STD_IDLE;
            end
            STD_RDATA: begin
                if (r_ack && (r_beat == b_len)) std_next = STD_IDLE;
            end
            default: std_next = STD_IDLE;
        endcase
    end

    // ---- AXI AW 状态机 ----
    always @(*) begin
        aw_next = aw_cur;
        case (aw_cur)
            AW_IDLE: if (w_data_req)      aw_next = AW_REQ;
            AW_REQ : if (m_axi_awready)   aw_next = AW_DONE;
            AW_DONE: if (b_ack)           aw_next = AW_IDLE;
            default:                      aw_next = AW_IDLE;
        endcase
    end

    // ---- AXI W/B 状态机 ----
    always @(*) begin
        wb_next = wb_cur;
        case (wb_cur)
            WB_IDLE: if (w_data_req)               wb_next = WB_DATA;
            WB_DATA: if (w_ack) begin
                         if (w_beat >= b_len)      wb_next = WB_RESP;
                         else                      wb_next = WB_BURST;
                     end
            WB_BURST:                              wb_next = WB_DATA;
            WB_RESP: if (b_ack) begin
                         if (w_data_req)           wb_next = WB_DATA;
                         else                      wb_next = WB_IDLE;
                     end
            default:                               wb_next = WB_IDLE;
        endcase
    end

    // ---- AXI AR 状态机 ----
    always @(*) begin
        ar_next = ar_cur;
        case (ar_cur)
            AR_IDLE: if (r_data_req)      ar_next = AR_REQ;
            AR_REQ : if (m_axi_arready)   ar_next = AR_DONE;
            AR_DONE: if (r_done)          ar_next = AR_IDLE;
            default:                      ar_next = AR_IDLE;
        endcase
    end

    // ---- AXI R 状态机 ----
    always @(*) begin
        r_next = r_cur;
        case (r_cur)
            R_IDLE : if (r_data_req)           r_next = R_DATA;
            R_DATA : if (r_ack) begin
                         if (r_beat >= b_len)  r_next = R_IDLE;
                         else                  r_next = R_BURST;
                     end
            R_BURST:                           r_next = R_DATA;
            default:                           r_next = R_IDLE;
        endcase
    end

    // ---- HREADY ----
    always @(*) begin
        if (!rst_n)                    hready_r = 1'b1;
        else if (std_cur == STD_WDATA) hready_r = w_ack_reg;   // 每拍 W 握手后放行
        else if (std_cur == STD_WRESP) hready_r = 1'b0;        // 等 B 响应（错误贯通）
        else if (std_cur == STD_RDATA) hready_r = r_ack;       // R 握手后放行
        else                           hready_r = 1'b1;
    end

    // ============================================================
    // 4. 时序逻辑 · 状态寄存器与锁存
    // ============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sta_cur   <= STA_IDLE;
            b_addr    <= {ADDR_W{1'b0}};
            b_size    <= 3'd2;
            b_len     <= 8'd0;
            std_cur   <= STD_IDLE;
            aw_cur    <= AW_IDLE;
            wb_cur    <= WB_IDLE;
            w_beat    <= 8'd0;
            ar_cur    <= AR_IDLE;
            r_cur     <= R_IDLE;
            r_beat    <= 8'd0;
            hresp_r   <= 1'b0;
            w_ack_reg <= 1'b0;
        end
        else begin
            sta_cur <= sta_next;
            std_cur <= std_next;
            aw_cur  <= aw_next;
            wb_cur  <= wb_next;
            ar_cur  <= ar_next;
            r_cur   <= r_next;

            // 突发参数锁存（仅突发首拍）
            if (start_burst) begin
                b_addr  <= HADDR;
                b_size  <= HSIZE;
                b_len   <= len_of(HBURST);
            end

            // W 拍计数：突发起点归 0，握手一次 +1
            if (w_data_req && wb_cur == WB_IDLE)  w_beat <= 8'd0;
            else if (w_ack)                        w_beat <= w_beat + 8'd1;

            // R 拍计数：突发起点归 0，握手一次 +1
            if (r_data_req && r_cur == R_IDLE)     r_beat <= 8'd0;
            else if (r_ack)                        r_beat <= r_beat + 8'd1;

            // W 握手延迟一拍（写数据期完成时序）
            w_ack_reg <= w_ack;

            // HRESP：写响应错误 / 读响应错误 贯通
            if (std_cur == STD_WRESP && b_ack)      hresp_r <= b_err;
            else if (std_cur == STD_RDATA && r_ack) hresp_r <= r_err;
        end
    end

    // ============================================================
    // 5. 输出
    // ============================================================
    // ---- HBURST → AXI AWLEN（统一 INCR，长度封顶 16）----
    function [7:0] len_of;
        input [2:0] burst;
        begin
            case (burst)
                HBURST_INCR, HBURST_INCR16, HBURST_WRAP16 : len_of = 8'd15;
                HBURST_INCR4,  HBURST_WRAP4              : len_of = 8'd3;
                HBURST_INCR8,  HBURST_WRAP8              : len_of = 8'd7;
                default                                   : len_of = 8'd0;   // SINGLE
            endcase
        end
    endfunction

    // ---- WSTRB：HSIZE + 当前拍地址低两位 ----
    function [DATA_W/8-1:0] wstrb_of;
        input [2:0] sz;
        input [1:0] off;
        begin
            case (sz)
                3'd0   : wstrb_of = 4'b0001 << off;
                3'd1   : wstrb_of = 4'b0011 << off;
                default: wstrb_of = 4'b1111;
            endcase
        end
    endfunction

    // ---- AHB 输出 ----
    assign HREADY = hready_r;
    assign HRESP  = hresp_r;
    assign HRDATA = m_axi_rdata;   // AXI 窄读数据已在地址选中 lane，透传即可

    // ---- AXI 写地址 ----
    assign m_axi_awid    = {ID_W{1'b0}};
    assign m_axi_awaddr  = b_addr;
    assign m_axi_awlen   = b_len;
    assign m_axi_awsize  = b_size;
    assign m_axi_awburst = AXBURST_INCR;
    assign m_axi_awvalid = (aw_cur == AW_REQ);

    // ---- AXI 写数据/响应 ----
    assign m_axi_wdata   = HWDATA;
    assign m_axi_wstrb   = wstrb_of(b_size, w_addr[1:0]);
    assign m_axi_wlast   = (wb_cur == WB_DATA) && (w_beat == b_len);
    assign m_axi_wvalid  = (wb_cur == WB_DATA);
    assign m_axi_bready  = (wb_cur == WB_RESP);

    // ---- AXI 读地址 ----
    assign m_axi_arid    = {ID_W{1'b0}};
    assign m_axi_araddr  = b_addr;
    assign m_axi_arlen   = b_len;
    assign m_axi_arsize  = b_size;
    assign m_axi_arburst = AXBURST_INCR;
    assign m_axi_arvalid = (ar_cur == AR_REQ);

    // ---- AXI 读数据 ----
    assign m_axi_rready  = (r_cur == R_DATA);

endmodule

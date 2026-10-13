// ============================================================
// axi_id_contract_check.v —— 契约C（AXI ID 编码）的自动检查器
//
// ============================================================
// 【契约C 是什么】（docs/阶段3-三人分工.md §2.3，已冻结）
// ============================================================
//   DMA 的 AXI4 主口 ID 编码：
//       m_axi_awid = { CH[2:0], 1'b1 }
//       m_axi_arid = { CH[2:0], 1'b1 }
//
//   · 最低位恒为 1  —— 标记"这条事务来自 DMA"
//                      （依据 docs/任务四 1.3 节：DMA 数据口主设备 ID=1）
//   · 高位 = 通道号（0 ~ 5）
//
// ============================================================
// 【为什么这条契约必须"冻"】
// ============================================================
//   它跨阶段：阶段 2 的 AXI 互连靠 ID 区分"这条事务是 CPU 发的还是 DMA 发的"。
//   如果哪天有人改了编码（比如把通道号挪到低位），互连不会报错，
//   只会把数据路由到错误的从设备 —— 【不报错的错误最难查】。
//
//   所以除了写进文档，还要把它变成【仿真里能自动检查的东西】。
//
// ============================================================
// 【怎么用】
// ============================================================
//   挂在 DMA 的 AXI4 主口上，信号并联（只读不写，不影响功能）：
//
//       axi_id_contract_check #(.NAME("dma_m")) u_id_chk (
//           .clk(clk), .rst_n(rst_n),
//           .awid(m_axi_awid), .awvalid(m_axi_awvalid), .awready(m_axi_awready),
//           .bid (m_axi_bid),  .bvalid (m_axi_bvalid),  .bready (m_axi_bready),
//           .arid(m_axi_arid), .arvalid(m_axi_arvalid), .arready(m_axi_arready),
//           .rid (m_axi_rid),  .rvalid (m_axi_rvalid),  .rready (m_axi_rready),
//           .error_count(id_contract_errors)
//       );
//
//   跑完看 error_count：0 = 契约守住了。
//
// ============================================================
// 【检查的规则】
// ============================================================
//   C1  AWID 最低位必须是 DMA_TAG（默认 1）
//   C2  ARID 最低位必须是 DMA_TAG
//   C3  AWID 的通道号（高位）必须在 0 ~ NCH-1 范围内
//   C4  ARID 的通道号必须在 0 ~ NCH-1 范围内
//
//   注：BID/RID 与 AWID/ARID 的【顺序和取值】匹配由
//       TB/axi_protocol_checker.v 的 R10 负责，本模块不重复。
//
// 【控制台编码】中文报错在 Windows cmd（GBK）会乱码，执行 chcp 65001 切 UTF-8。
//              规则号 C1~C4 是 ASCII，乱码时也能定位。
// ============================================================
`timescale 1ns/1ps

module axi_id_contract_check #(
    parameter ID_W       = 4,
    parameter NCH        = 6,        // 通道数
    parameter DMA_TAG    = 1'b1,     // ID 最低位的固定值
    parameter NAME       = "DMA",
    parameter MAX_REPORT = 10
)(
    input  wire             clk,
    input  wire             rst_n,

    input  wire [ID_W-1:0]  awid,
    input  wire             awvalid,
    input  wire             awready,

    input  wire [ID_W-1:0]  bid,
    input  wire             bvalid,
    input  wire             bready,

    input  wire [ID_W-1:0]  arid,
    input  wire             arvalid,
    input  wire             arready,

    input  wire [ID_W-1:0]  rid,
    input  wire             rvalid,
    input  wire             rready,

    output reg  [31:0]      error_count
);

    // 通道号 = ID 的高位（去掉最低的 tag 位）
    localparam CH_W = ID_W - 1;

    wire [CH_W-1:0] aw_ch = awid[ID_W-1:1];
    wire [CH_W-1:0] ar_ch = arid[ID_W-1:1];

    task err;
        input [8*8-1:0]  rule;
        input [8*72-1:0] msg;
        begin
            error_count = error_count + 1;
            if (error_count <= MAX_REPORT)
                $display("  [%0t] [%0s] 违反契约C %0s : %0s", $time, NAME, rule, msg);
        end
    endtask

    // ============================================================
    // 只在 VALID 拉高时检查（握不握手都要查：一旦 VALID 有效，
    // 这一拍携带的 ID 就必须合法）
    // ============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            error_count = 0;
        end
        else begin
            // ---- C1：AWID 最低位 ----
            if (awvalid && (awid[0] !== DMA_TAG))
                err("C1", "AWID 最低位不是 DMA_TAG（应为 1，标记来自 DMA）");

            // ---- C2：ARID 最低位 ----
            if (arvalid && (arid[0] !== DMA_TAG))
                err("C2", "ARID 最低位不是 DMA_TAG（应为 1，标记来自 DMA）");

            // ---- C3：AWID 通道号越界 ----
            if (awvalid && (aw_ch >= NCH))
                err("C3", "AWID 的通道号超出范围（应 < NCH）");

            // ---- C4：ARID 通道号越界 ----
            if (arvalid && (ar_ch >= NCH))
                err("C4", "ARID 的通道号超出范围（应 < NCH）");
        end
    end

endmodule

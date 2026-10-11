`timescale 1ns / 1ps

module ahb2axi4_fifo #(
    parameter DATA_WIDTH = 32,
    parameter FIFO_DEPTH = 256    )
(
    input                      clk,
    input                      rst_n,

    input   [DATA_WIDTH-1:0]   data_i,
    output  [DATA_WIDTH-1:0]   data_o,

    input                      wr_valid_i,
    input                      rd_valid_i,

    output                     almost_empty_o,
    output                     empty_o,
    output                     almost_full_o,
    output                     full_o
);

    localparam ADDR_WIDTH = $clog2(FIFO_DEPTH);   // 调用系统函数clog2
    genvar addr;

    // ------------------ Internal signals ------------------
    wire    [ADDR_WIDTH:0]        wr_addr_inc;
    wire    [ADDR_WIDTH-1:0]      wr_addr_map;
    wire    [ADDR_WIDTH:0]        rd_addr_inc;
    wire    [ADDR_WIDTH-1:0]      rd_addr_map;
    wire    [DATA_WIDTH-1:0]      buffer_nxt  [0:FIFO_DEPTH-1];

    reg     [DATA_WIDTH-1:0]      buffer      [0:FIFO_DEPTH-1];
    reg     [ADDR_WIDTH:0]        wr_addr;
    reg     [ADDR_WIDTH:0]        rd_addr;
    // ------------------------------------------------------

    assign wr_addr_inc  = wr_addr + 1'b1;
    assign rd_addr_inc  = rd_addr + 1'b1;
    assign wr_addr_map  = wr_addr[ADDR_WIDTH-1:0];
    assign rd_addr_map  = rd_addr[ADDR_WIDTH-1:0];

    assign empty_o        = (wr_addr == rd_addr);
    assign almost_empty_o = (rd_addr_inc == wr_addr);
    assign full_o         = (wr_addr_map == rd_addr_map) & (wr_addr[ADDR_WIDTH] ^ rd_addr[ADDR_WIDTH]);
    assign almost_full_o  = (wr_addr_map + 1'b1 == rd_addr_map);

    // generate块的作用与优势是模块重复例化（for）和模块选择性例化(if、case)。
    // 输入数据到buffer_nxt当前地址处
    generate
    for (addr = 0; addr < FIFO_DEPTH; addr = addr + 1) begin
        assign buffer_nxt[addr] = (wr_addr_map == addr) ? data_i : buffer[addr];
    end
    endgenerate

    // 输出buffer当前地址处的数据
    assign data_o = buffer[rd_addr_map];

    // 写有效且FIFO不满时则在时钟上升沿采样buffer_nxt的所有数据到buffer
    generate
    for (addr = 0; addr < FIFO_DEPTH; addr = addr + 1) begin
        always @(posedge clk) begin
            if (!rst_n) begin
                buffer[addr] <= {DATA_WIDTH{1'b0}};
            end
            else if (wr_valid_i & !full_o) begin
                buffer[addr] <= buffer_nxt[addr];
            end
        end
    end
    endgenerate

    // FIFO非满则更新写指针
    always @(posedge clk) begin
        if (!rst_n) begin
            wr_addr <= 1'b0;
        end
        else if (wr_valid_i & !full_o) begin
            wr_addr <= wr_addr_inc;
        end
    end

    // FIFO非空则更新读指针
    always @(posedge clk) begin
        if (!rst_n) begin
            rd_addr <= 0;
        end
        else if (rd_valid_i & !empty_o) begin
            rd_addr <= rd_addr_inc;
        end
    end
    // -----------------------------------------------------


endmodule
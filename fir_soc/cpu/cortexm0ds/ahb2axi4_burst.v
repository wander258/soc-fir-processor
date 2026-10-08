`timescale 1ns / 1ps
`include "ahb_axi_define.v"

module ahb2axi4_burst #(
  // Configurable settings
  parameter ADDR_WIDTH      = 32,
  parameter DATA_WIDTH      = 32
)(
  input wire           HCLK,
  input wire           HRESETn,
  input wire  [2:0]    HSIZE,
  input wire  [2:0]    HBURST,
  input wire           HREADY,
  input wire  [1:0]    HTRANS,

  output reg  [2:0]    BC_WSIZE,
  output reg  [1:0]    BC_WBURST,
  output reg  [7:0]    BC_WLEN,
  output reg  [2:0]    BC_RSIZE,
  output reg  [1:0]    BC_RBURST,
  output reg  [7:0]    BC_RLEN
);
  reg  [1:0]  BC_WBURST_next ;
  reg  [7:0]  BC_WLEN_next   ;
  reg  [1:0]  BC_RBURST_next ;
  reg  [7:0]  BC_RLEN_next   ;

  wire HBURST_to_AxBURST_SINGLE   = (HBURST == `SINGLE);
  wire HBURST_to_AxBURST_INCR     = (HBURST == `INCR)  || (HBURST == `INCR4) || (HBURST == `INCR8) || (HBURST == `INCR16);
  wire HBURST_to_AxBURST_WRAP     = (HBURST == `WRAP4) || (HBURST == `WRAP8) || (HBURST == `WRAP16);
  wire HBURST_to_AxLEN_undefined  = (HBURST == `INCR);
  wire HBURST_to_AxLEN_1          = (HBURST == `SINGLE);
  wire HBURST_to_AxLEN_4          = (HBURST == `INCR4) || (HBURST == `WRAP4);
  wire HBURST_to_AxLEN_8          = (HBURST == `INCR8) || (HBURST == `WRAP8);
  wire HBURST_to_AxLEN_16         = (HBURST == `INCR16)|| (HBURST == `WRAP16);

  always @(*) begin
    BC_WLEN_next   = 8'b00000000;
    BC_RLEN_next   = 8'b00000000;
    BC_WBURST_next = `RESERVED_AXI;
    BC_RBURST_next = `RESERVED_AXI;

    if (HREADY && (HTRANS[1] == 1'b1)) begin
      if (HBURST_to_AxBURST_SINGLE) begin
        BC_WBURST_next = `FIXED_AXI;
        BC_RBURST_next = `FIXED_AXI;
      end
      else if (HBURST_to_AxBURST_INCR) begin
        BC_WBURST_next = `INCR_AXI;
        BC_RBURST_next = `INCR_AXI;
      end
      else if (HBURST_to_AxBURST_WRAP) begin
        BC_WBURST_next = `WRAP_AXI;
        BC_RBURST_next = `WRAP_AXI;
      end

      if (HBURST_to_AxLEN_1) begin
        BC_WLEN_next = 8'b00000000;
        BC_RLEN_next = 8'b00000000;
      end
      else if (HBURST_to_AxLEN_4) begin
        BC_WLEN_next = 8'b00000011;
        BC_RLEN_next = 8'b00000011;
      end
      else if (HBURST_to_AxLEN_8) begin
        BC_WLEN_next = 8'b00000111;
        BC_RLEN_next = 8'b00000111;
      end
      else if (HBURST_to_AxLEN_16 || HBURST_to_AxLEN_undefined) begin
        BC_WLEN_next = 8'b00001111;
        BC_RLEN_next = 8'b00001111;
      end
    end

  end

  always @(posedge HCLK or negedge HRESETn) begin
    if (~HRESETn) begin
      BC_WSIZE  <= `BYTE_4      ;					// 数据宽度为32bit
      BC_WBURST <= `INCR_AXI    ;					// 写数据传输方式INCR
      BC_WLEN   <= 8'b00000000  ;					// 写数据长度为1，Length = AxLEN + 1
      BC_RSIZE  <= `BYTE_4      ;					// 数据宽度为32bit
      BC_RBURST <= `FIXED_AXI   ;					// 读数据传输方式FIXED
      BC_RLEN   <= 8'b00000000  ;					// 读数据长度为1，Length = AxLEN + 1
    end
    else if(HREADY && (HTRANS[1] == 1'b1)) begin
      BC_WSIZE  <= HSIZE        ;
      BC_WBURST <= BC_WBURST_next ;
      BC_WLEN   <= BC_WLEN_next   ;
      BC_RSIZE  <= HSIZE        ;
      BC_RBURST <= BC_RBURST_next ;
      BC_RLEN   <= BC_RLEN_next   ;
    end
  end
endmodule

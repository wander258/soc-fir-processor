`ifndef _AHB_AXI4_DEFINE_V_
`define _AHB_AXI4_DEFINE_V_
//-----------------------------------------------------------------------
//
//-----------------------------------------------------------------------
// HTRANS
`define IDLE            2'b00
`define BUSY            2'b01
`define NONSEQ          2'b10
`define SEQ             2'b11

// HBURST       
`define SINGLE          3'b000
`define INCR            3'b001
`define WRAP4           3'b010
`define INCR4           3'b011
`define WRAP8           3'b100
`define INCR8           3'b101
`define WRAP16          3'b110
`define INCR16          3'b111

// AHB Response signals
`define AHB_OKAY        1'b0
`define AHB_ERROR       1'b1

// SIZE       
`define BYTE_1          3'b000
`define BYTE_2          3'b001
`define BYTE_4          3'b010
`define BYTE_8          3'b011
`define BYTE_16         3'b100
`define BYTE_32         3'b101
`define BYTE_64         3'b110
`define BYTE_128        3'b111

// AXI BURST
`define FIXED_AXI       2'b00
`define INCR_AXI        2'b01
`define WRAP_AXI        2'b10
`define RESERVED_AXI    2'b11

// AXI4 Response signals
`define OKAY            2'b00
`define EXOKAY          2'b01
`define SLVERR          2'b10
`define DECERR          2'b11

`endif

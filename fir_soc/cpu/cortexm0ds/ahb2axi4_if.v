//---------------------------------------------------------------
// 请求（REQ）-应答（ACK）协议，信息：控制信息、地址信息、数据信息、响应信息
//             __    __    __    __    __    __    __    __
// CLK      __|  |__|  |__|  |__|  |__|  |__|  |__|  |__|  |__
//             _____
// BC_REQ   __|     |_________________________________________
//                         _____
// BC_ACK   ______________|     |_____________________________
//            __________________
// BC_ADDR  XX______________A___XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
//            __________________
// BC_WDATA XX______________DW__XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
//                         _____
// BC_RDATA XXXXXXXXXXXXXXX_DR__XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
//                         _____
// BC_RESP  XXXXXXXXXXXXXXX_RR__XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
// 
//---------------------------------------------------------------
`timescale 1ns / 1ps

module ahb2axi4_if #(
    // Configurable settings
    parameter ADDR_WIDTH      = 32,
    parameter DATA_WIDTH      = 32
)(
    // --------------------- AHB ---------------------
    input  wire                         HCLK,
    input  wire                         HRESETn,
	input 							    HSEL,			// 从设备选择（来自译码器）
    input  wire   [1:0]                 HTRANS,
    input  wire   [2:0]                 HSIZE,
    input  wire   [2:0]                 HBURST,
    input  wire                         HWRITE,
	input  							    HREADY,			// 准备好
    input  wire   [ADDR_WIDTH-1:0]      HADDR,
    input  wire   [DATA_WIDTH-1:0]      HWDATA,
    output wire                         HREADYOUT,
    output wire   [DATA_WIDTH-1:0]      HRDATA,
    output wire                         HRESP,

    // -----------------------------------------------
    input  wire                         ACLK,
    input  wire                         ARESETn,
    //----------------- AXI - Write -----------------
    output wire                         AW_VALID,
    input  wire                         AW_READY,
    output wire   [2:0]                 AW_SIZE,
    output wire   [1:0]                 AW_BURST,
    output wire   [7:0]                 AW_LEN,
    output wire   [ADDR_WIDTH-1:0]      AW_ADDR,
    output wire                         W_VALID,
    input  wire                         W_READY,
    output wire                         W_LAST,
    output wire   [DATA_WIDTH-1:0]      W_DATA,
    input  wire                         B_VALID,
    output wire                         B_READY,
    input  wire   [1:0]                 B_RESP,

    //----------------- AXI - Read ------------------
    output wire                         AR_VALID,
    input  wire                         AR_READY,
    output wire   [2:0]                 AR_SIZE,
    output wire   [1:0]                 AR_BURST,
    output wire   [7:0]                 AR_LEN,
    output wire   [ADDR_WIDTH-1:0]      AR_ADDR,
    input  wire                         R_VALID,
    output wire                         R_READY,
     input  wire                         R_LAST,
   input  wire   [DATA_WIDTH-1:0]      R_DATA,
    input  wire   [1:0]                 R_RESP
);

    // 内部信号
    //-----------------------------------------------------------
    // BC Interface
    wire						BC_WREQ;
    wire 						BC_WACK;
    wire 						BC_BACK;
    wire [2:0]                  BC_WSIZE;
    wire [1:0]                  BC_WBURST;
    wire [7:0]                  BC_WLEN;
    wire [ADDR_WIDTH-1:0]	    BC_WADDR;
    wire [DATA_WIDTH-1:0]	    BC_WDATA;
    wire 						BC_WRESP;
    wire						BC_RREQ;
    wire 						BC_RACK;
    wire [2:0]                  BC_RSIZE;
    wire [1:0]                  BC_RBURST;
    wire [7:0]                  BC_RLEN;
    wire [ADDR_WIDTH-1:0]	    BC_RADDR;
    wire [DATA_WIDTH-1:0]	    BC_RDATA;
    wire 						BC_RRESP;

    // 实例化
    ahb2axi4_ahb 
        #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH))
        u_ahb2axi4_ahb (
            .HCLK           (HCLK),
            .HRESETn        (HRESETn),
            .HSEL           (HSEL),
            .HADDR          (HADDR),
            .HTRANS         (HTRANS),
            .HSIZE          (HSIZE),
            .HBURST         (HBURST),
            .HWDATA         (HWDATA),
            .HWRITE         (HWRITE),
			.HREADY		    (HREADY),
            .HRDATA         (HRDATA),
            .HRESP          (HRESP),
            .HREADYOUT      (HREADYOUT),

            .BC_WREQ		(BC_WREQ),
            .BC_WACK		(BC_WACK),
            .BC_BACK        (BC_BACK),
            .BC_WADDR	    (BC_WADDR),
            .BC_WDATA	    (BC_WDATA),
            .BC_WRESP	    (BC_WRESP),
            .BC_RREQ		(BC_RREQ),
            .BC_RACK		(BC_RACK),
            .BC_RADDR	    (BC_RADDR),
            .BC_RDATA	    (BC_RDATA),
            .BC_RRESP	    (BC_RRESP)
       );

    ahb2axi4_burst 
        u_ahb2axi4_burst (
            .HCLK           (HCLK),
            .HRESETn        (HRESETn),
            .HTRANS         (HTRANS),
            .HSIZE          (HSIZE),
            .HBURST         (HBURST),
            .HREADY         (HREADY),
            .BC_WSIZE       (BC_WSIZE),
            .BC_WBURST      (BC_WBURST),
            .BC_WLEN        (BC_WLEN),
            .BC_RSIZE       (BC_RSIZE),
            .BC_RBURST      (BC_RBURST),
            .BC_RLEN        (BC_RLEN)
        );

    ahb2axi4_axi 
        #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH))
        u_ahb2axi4_axi (
            .ACLK           (ACLK),
            .ARESETn        (ARESETn),
            .AW_VALID       (AW_VALID),
            .AW_READY       (AW_READY),
            .AW_SIZE		(AW_SIZE),
            .AW_LEN		    (AW_LEN),
            .AW_BURST	    (AW_BURST),
            .AW_ADDR        (AW_ADDR),
            .W_VALID        (W_VALID),
            .W_READY        (W_READY),
            .W_LAST         (W_LAST),
            .W_DATA         (W_DATA),
            .B_VALID        (B_VALID),
            .B_READY        (B_READY),
            .B_RESP         (B_RESP),
            .AR_VALID       (AR_VALID),
            .AR_READY       (AR_READY),
            .AR_SIZE		(AR_SIZE),
            .AR_LEN		    (AR_LEN),
            .AR_BURST	    (AR_BURST),
            .AR_ADDR        (AR_ADDR),
            .R_VALID        (R_VALID),
            .R_READY        (R_READY),
            .R_LAST         (R_LAST),
            .R_DATA         (R_DATA),
            .R_RESP         (R_RESP),

            .BC_WREQ		(BC_WREQ),
            .BC_WACK		(BC_WACK),
            .BC_BACK        (BC_BACK),
            .BC_WSIZE       (BC_WSIZE),
            .BC_WBURST      (BC_WBURST),
            .BC_WLEN        (BC_WLEN),
            .BC_WADDR	    (BC_WADDR),
            .BC_WDATA	    (BC_WDATA),
            .BC_WRESP	    (BC_WRESP),
            .BC_RREQ		(BC_RREQ),
            .BC_RACK		(BC_RACK),
            .BC_RSIZE       (BC_RSIZE),
            .BC_RBURST      (BC_RBURST),
            .BC_RLEN        (BC_RLEN),
            .BC_RADDR	    (BC_RADDR),
            .BC_RDATA	    (BC_RDATA),
            .BC_RRESP	    (BC_RRESP)
        );
    
endmodule
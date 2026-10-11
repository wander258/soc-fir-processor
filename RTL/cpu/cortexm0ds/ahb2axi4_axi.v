`include "ahb_axi_define.v"

module ahb2axi4_axi #(
	parameter integer ADDR_WIDTH = 32,				// 地址位宽
	parameter integer DATA_WIDTH = 32				// 数据位宽
)(
	// 全局信号
	input wire 						ACLK,			// 时钟信号
	input wire						ARESETn,        // 复位信号
	// AXI-master interface
    // 写请求通道                                
	output wire  					AW_VALID, 		// 写请求有效
	input wire						AW_READY,       // 写请求就绪
    output wire [2:0]              	AW_SIZE,		// 写数据宽度
    output wire [1:0]            	AW_BURST,		// 写数据传输方式
    output wire [7:0]            	AW_LEN,			// 写数据长度
	output wire [ADDR_WIDTH-1:0]	AW_ADDR,        // 写地址
    // 写数据通道                                
	output wire  					W_VALID, 		// 写数据有效
	input wire						W_READY, 		// 写数据就绪
	output wire						W_LAST,			// 最后一拍写数据
	output wire [DATA_WIDTH-1:0]	W_DATA,         // 写数据
    // 写响应通道                                
	input wire						B_VALID,		// 写响应有效
	output wire  					B_READY,		// 写响应就绪
	input wire [1:0] 				B_RESP,         // 写响应信息
    // 读请求通道                                
	output wire  					AR_VALID,		// 读请求有效
	input wire						AR_READY,		// 读请求就绪
    output wire [2:0]            	AR_SIZE,		// 读数据宽度
    output wire [1:0]             	AR_BURST,		// 读数据传输方式
    output wire [7:0]				AR_LEN,			// 读数据长度
	output wire [ADDR_WIDTH-1:0]	AR_ADDR,        // 读地址
    // 读数据通道                                
	input wire			        	R_VALID,		// 读数据有效
	output wire  			    	R_READY,		// 读数据就绪
	input wire						R_LAST,			// 最后一拍读数据
	input wire [DATA_WIDTH-1:0]		R_DATA,         // 读数据
	input wire [1:0] 				R_RESP,         // 读响应信息

	// BC Interface
	input  wire						BC_WREQ,		// BC写请求
	output wire	 					BC_WACK,		// BC写数据应答
	output wire	 					BC_BACK,		// BC写响应应答
	input wire [2:0]    			BC_WSIZE,		// BC写数据宽度
	input wire [1:0]    			BC_WBURST,		// BC写数据传输方式
	input wire [7:0]    			BC_WLEN,		// BC写数据长度
	input  wire [ADDR_WIDTH-1:0]	BC_WADDR,		// BC写地址
	input  wire [DATA_WIDTH-1:0]	BC_WDATA,		// BC写数据
	output wire						BC_WRESP,		// BC写响应
	input  wire						BC_RREQ,		// BC读请求
	output wire 					BC_RACK,		// BC读数据应答
	input wire [2:0]    			BC_RSIZE,		// BC读数据宽度
	input wire [1:0]    			BC_RBURST,		// BC读数据传输方式
	input wire [7:0]    			BC_RLEN,		// BC读数据长度
	input  wire [ADDR_WIDTH-1:0]	BC_RADDR,		// BC读地址
	output wire [DATA_WIDTH-1:0]	BC_RDATA,		// BC读数据
	output wire						BC_RRESP		// BC读响应
);
	
	
	//---------------------<状态机参数>-------------------------------------
	localparam STWA_IDLE	= 3'b001;				// 写请求空闲
	localparam STWA_REQ		= 3'b010;				// 写请求
	localparam STWA_WAIT	= 3'b100;				// 写请求等待(请求数据同步)
	reg [2:0]               stwa_cur;
	reg [2:0]               stwa_next;

	
	//---------------------<状态机参数>-------------------------------------
	localparam STW_IDLE		= 4'b0001;				// 写操作空闲
	localparam STW_DATA		= 4'b0010;				// 写操作数据
	localparam STW_BURST	= 4'b0100;				// BURST写等待
	localparam STW_RESP		= 4'b1000;				// 写操作响应
	reg [3:0]               stw_cur;
	reg [3:0]               stw_next;

	//---------------------<状态机参数>-------------------------------------
	localparam STR_IDLE		= 4'b0001;				// 读操作空闲
	localparam STR_REQ		= 4'b0010;				// 读操作请求
	localparam STR_DATA		= 4'b0100;				// 读操作数据
	localparam STR_BURST	= 4'b1000;				// BURST读等待
	reg [3:0]               str_cur;
	reg [3:0]               str_next;

	//---------------------<局部变量定义>-------------------------------------
	reg [7:0]               w_beatCNT;				// BUSRT写操作拍数计数器
	reg [7:0]               r_beatCNT;				// BUSRT读操作拍数计数器


	//############################# 写操作 #################################
	//----------------------------------------------------------------------
	//--  写请求状态机第1段（状态迁移）
	//----------------------------------------------------------------------
	always @(posedge ACLK or negedge ARESETn) begin
		if(!ARESETn) begin
			stwa_cur <= STWA_IDLE;
		end
		else begin
			stwa_cur <= stwa_next;
		end
	end

	//----------------------------------------------------------------------
	//--  写请求状态机第2段（输入对状态的影响）
	//----------------------------------------------------------------------
	always @(*) begin
		stwa_next = stwa_cur;		// 默认保持当前状态，避免LATCH
		case(stwa_cur)
			STWA_IDLE: begin						// 写请求空闲
				if(BC_WREQ)
					stwa_next = STWA_REQ;
			end
			STWA_REQ: begin							// 写请求通道
				if(AW_READY) begin
					stwa_next = STWA_WAIT;
				end
			end
			STWA_WAIT: begin						// 写请求同步
				if(B_VALID & B_READY) begin			// 单拍写
					if(BC_WREQ)						// 流水传输
						stwa_next = STWA_REQ;
					else							// 非流水传输
						stwa_next = STWA_IDLE;
				end
			end
			default: stwa_next = STWA_IDLE;			// 防御性编程：异常状态恢复
		endcase
	end

	//----------------------------------------------------------------------
	//--   写请求状态机第3段（状态对输出的影响）
	//----------------------------------------------------------------------
	// AXI信号产生
	assign AW_VALID = (stwa_cur == STWA_REQ) ? 1'b1 : 1'b0;
	assign AW_SIZE  = BC_WSIZE;
	assign AW_BURST = BC_WBURST;
	assign AW_LEN   = BC_WLEN;
	assign AW_ADDR  = BC_WADDR;						// 输出写地址，BC已经寄存

	//----------------------------------------------------------------------
	//--   写数据响应状态机第1段（状态迁移）
	//----------------------------------------------------------------------
	always @(posedge ACLK or negedge ARESETn)begin
		if(!ARESETn)begin
			stw_cur <= STW_IDLE;
		end
		else begin
			stw_cur <= stw_next;
		end
	end

	//----------------------------------------------------------------------
	//--   写数据响应状态机第2段（输入对状态的影响）
	//----------------------------------------------------------------------
	always @(*) begin
		stw_next = stw_cur;			// 默认保持当前状态，避免LATCH
		case(stw_cur)
			STW_IDLE: begin
				if(BC_WREQ)							// 写操作启动
					stw_next = STW_DATA;
			end
			STW_DATA: begin							// 写数据通道
				if(W_READY) begin
					if(w_beatCNT >= AW_LEN) 		// 单拍或者BUSRT最后一拍
						stw_next = STW_RESP;
					else							// BUSRT写
						stw_next = STW_BURST;
				end
			end
			STW_BURST: begin						// BURST写
				stw_next = STW_DATA;
			end
			STW_RESP: begin							// 写响应通道
				if(B_VALID)begin
					if(BC_WREQ)						// 单拍流水
						stw_next = STW_DATA;
					else 							// 单拍非流水或者BUSRT最后一拍
						stw_next = STW_IDLE;
				end
			end
			default: stw_next = STW_IDLE;			// 防御性编程：异常状态恢复
		endcase
	end
	
	// BUSRT写操作拍数计数
	always @(posedge ACLK or negedge ARESETn)begin
		if(!ARESETn) begin
			w_beatCNT <= 'h0; 
		end
		else if((stw_cur == STW_DATA) ||(stw_cur == STW_BURST)) begin
			if((W_VALID & W_READY) && (w_beatCNT < AW_LEN)) 
				w_beatCNT <= w_beatCNT + 1;			// 完成一拍
		end
		else
			w_beatCNT <= 'h0;
	end

	//----------------------------------------------------------------------
	//--   写数据响应状态机第3段（状态对输出的影响）
	//----------------------------------------------------------------------
	// AXI信号产生
	assign W_VALID = (stw_cur == STW_DATA) ? 1'b1 : 1'b0;
	assign W_LAST = (w_beatCNT == AW_LEN) & W_VALID & W_READY;	// 最后一拍数据
	assign W_DATA = BC_WDATA;		// W_VALID有效则W_DATA必须有效，否则W_VALID往后延

	assign B_READY = (stw_cur == STW_RESP) ? 1'b1 : 1'b0;		// 写响应准备好

	// BC信号产生
	assign BC_WACK  = W_VALID & W_READY;
	assign BC_BACK  = B_VALID & B_READY;
	assign BC_WRESP = (stw_cur == STW_RESP) & B_VALID & B_RESP[1];	// BC写响应信息


	//############################# 读操作 #################################
	//----------------------------------------------------------------------
	//--   状态机第1段（状态迁移）
	//----------------------------------------------------------------------
	always @(posedge ACLK or negedge ARESETn) begin
		if(!ARESETn) begin
			str_cur <= STR_IDLE;
		end
		else begin
			str_cur <= str_next;
		end
	end

	//----------------------------------------------------------------------
	//--   状态机第2段（输入对状态的影响）
	//----------------------------------------------------------------------
	always @(*)begin
		str_next = str_cur;
		case(str_cur)
			STR_IDLE: begin							// 读空闲
				if(BC_RREQ)
					str_next = STR_REQ;
			end
			STR_REQ: begin							// 读请求通道
				if(AR_READY)
					str_next = STR_DATA;
			end
			STR_DATA: begin							// 读数据通道
				if(R_VALID)begin
					if(r_beatCNT < AR_LEN)			// BURST读
						str_next = STR_BURST;
					else if(BC_RREQ)				// 单拍流水
						str_next = STR_REQ;
					else							// 单拍或者BURST最后一拍
						str_next = STR_IDLE;
				end
			end
			STR_BURST: begin						// BURST读
				str_next = STR_DATA;
			end
			default: str_next = STR_IDLE;			// 防御性编程：异常状态恢复
		endcase
	end
	
	// BUSRT读操作拍数计数
	always @(posedge ACLK or negedge ARESETn) begin
		if(!ARESETn) begin
			r_beatCNT <= 'h0; 
		end
 		else if(str_next == STR_REQ) begin
			r_beatCNT <= 'h0;
		end
 		else if(str_next == STR_BURST) begin
			r_beatCNT <= r_beatCNT + 1;				// 完成一拍
		end
	end

	//----------------------------------------------------------------------
	//--   状态机第3段（状态对输出的影响）
	//----------------------------------------------------------------------
	// AXI信号产生
	assign AR_VALID = (str_cur == STR_REQ) ? 1'b1 : 1'b0;
	assign AR_SIZE  = BC_RSIZE;
	assign AR_BURST = BC_RBURST;
	assign AR_LEN   = BC_RLEN;
	assign AR_ADDR  = BC_RADDR;						// BC已经寄存

	assign R_READY = (str_cur == STR_DATA) ? 1'b1 : 1'b0;	// 读数据准备好

	// BC信号产生
	assign BC_RACK = R_VALID & R_READY;				// 读准备好
	assign BC_RDATA = R_DATA;						// 采样读数据
	assign BC_RRESP = (str_cur == STR_DATA) & R_VALID & R_RESP[1];		// 采样读响应信息

endmodule
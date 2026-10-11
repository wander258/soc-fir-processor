`include "ahb_axi_define.v"

module ahb2axi4_ahb# (
	parameter integer ADDR_WIDTH = 32,				// 地址宽度
	parameter integer DATA_WIDTH = 32				// 数据位宽
)(
	// 全局信号
	input wire						HCLK,			// 时钟信号
	input wire						HRESETn,		// 复位信号

	// AHB Slave Interface	
	input wire 						HSEL,			// 从设备选择（来自译码器）
	input wire [1:0]				HTRANS,			// 传输模式
	input wire [2:0]				HSIZE,			// 数据宽度
	input wire [2:0]				HBURST,			// 突发模式
	input wire 						HWRITE,			// 传输方向
	input wire [ADDR_WIDTH-1:0]		HADDR,			// 地址
	input wire [DATA_WIDTH-1:0]		HWDATA,			// 写数据
	input wire 						HREADY,			// 系统准备好（来自多路器）
	output reg						HREADYOUT,		// 从设备准备好(送往多路器)
	output wire[DATA_WIDTH-1:0]		HRDATA,			// 读数据
	output reg						HRESP,			// 响应信息

	// 从设备测试信号
	output wire						BC_WREQ,		// 请求
	input wire						BC_WACK,		// 应答
	input wire						BC_BACK,		// 应答
	output reg [ADDR_WIDTH-1:0] 	BC_WADDR,		// 写地址缓存
	output wire [DATA_WIDTH-1:0] 	BC_WDATA,		// 写寄存器缓存
	input wire						BC_WRESP,		// 写响应信息
	output wire						BC_RREQ,		// 请求
	input wire						BC_RACK,		// 应答
	output reg [ADDR_WIDTH-1:0] 	BC_RADDR,		// 读地址缓存
	input wire [DATA_WIDTH-1:0]		BC_RDATA,		// 读寄存器缓存
	input wire						BC_RRESP		// 读响应信息
);
	
	
	//---------------------<状态机参数>-------------------------------------
	localparam STA_IDLE		= 2'b01;				// 空闲
	localparam STA_ADDR		= 2'b10;				// 地址段
	reg [1:0]              	sta_cur;
	reg [1:0]              	sta_next;

	//---------------------<状态机参数>-------------------------------------
	localparam STD_IDLE		= 4'b0001;				// 空闲
	localparam STD_WDATA	= 4'b0010;				// 写数据段
	localparam STD_WRESP	= 4'b0100;				// 写响应
	localparam STD_RDATA	= 4'b1000;				// 读数据段
	reg [3:0]              	std_cur;
	reg [3:0]              	std_next;

	// 局部变量
	wire					w_dataREQ, r_dataREQ;

	//############################# 地址段传输操作 #################################
	//----------------------------------------------------------------------
	//--   状态机第1段（状态迁移）
	//----------------------------------------------------------------------
	always @(posedge HCLK or negedge HRESETn)begin
		if(~HRESETn)begin
			sta_cur <= STA_IDLE;
		end
		else begin
			sta_cur <= sta_next;
		end
	end

	//----------------------------------------------------------------------
	//--   状态机第2段（输入对状态的影响）
	//----------------------------------------------------------------------
	always @(*) begin
		sta_next = sta_cur;			// 默认保持当前状态，避免LATCH
		case(sta_cur)
			STA_IDLE: begin							// 空闲
				if((HSEL & HREADY) && (HTRANS == `NONSEQ))begin	// 事务启动
					sta_next = STA_ADDR;
				end
			end
			STA_ADDR: begin							// 写地址段
				if(HTRANS == `IDLE)begin			// 传输完毕
					sta_next = STA_IDLE;
				end
			end
			default: sta_next = STA_IDLE;			// 防御性编程：异常状态恢复
		endcase
	end

	//----------------------------------------------------------------------
	//--   状态机第3段（状态对输出的影响）
	//----------------------------------------------------------------------
	// BC地址信号产生（地址必须寄存，否则地址段结束新的地址段又来了）
	always @(posedge HCLK or negedge HRESETn)begin
		if(~HRESETn)begin
			BC_WADDR <= 'h04;
			BC_RADDR <= 'h04;
		end
		else if((sta_next == STA_ADDR) & HREADY)begin
			if(HWRITE)
				BC_WADDR <= HADDR;
			else
				BC_RADDR <= HADDR;
		end
	end

	// 数据段同步信号产生
	assign w_dataREQ = HWRITE & (sta_next == STA_ADDR); 	// 数据段同步请求
	assign r_dataREQ = (!HWRITE) & (sta_next == STA_ADDR); 	// 数据段同步请求


	//############################# 数据段传输操作 #################################
	//----------------------------------------------------------------------
	//--   状态机第1段（状态迁移）
	//----------------------------------------------------------------------
	always @(posedge HCLK or negedge HRESETn)begin
		if(~HRESETn)begin
			std_cur <= STD_IDLE;
		end
		else begin
			std_cur <= std_next;
		end
	end

	//----------------------------------------------------------------------
	//--   状态机第2段（输入对状态的影响）
	//----------------------------------------------------------------------
	always @(*) begin
		std_next = std_cur;			// 默认保持当前状态，避免LATCH
		case(std_cur)
			STD_IDLE: begin							// 空闲
				if(w_dataREQ)
					std_next = STD_WDATA;
				else if(r_dataREQ)
					std_next = STD_RDATA;
			end
			STD_WDATA: begin						// 写数据段
				if(BC_WACK)begin
					if((HTRANS == `IDLE) || ((HTRANS[1] == 1'b1) && (HBURST == `SINGLE)))
						std_next = STD_WRESP;
				end
			end
			STD_WRESP: begin						// 写响应
				if(BC_BACK) begin
					if(w_dataREQ)					// 继续写操作
						std_next = STD_WDATA;
					else if(r_dataREQ)				// 继续读操作
						std_next = STD_RDATA;
					else							// 传输完毕
						std_next = STD_IDLE;
				end
			end
			STD_RDATA: begin						// 读数据段
				if(BC_RACK)begin
					if(r_dataREQ)					// 继续读操作
						std_next = STD_RDATA;
					else if(w_dataREQ)				// 继续写操作
						std_next = STD_WDATA;
					else							// 传输完毕
						std_next = STD_IDLE;
				end
			end
			default: std_next = STD_IDLE;			// 防御性编程：异常状态恢复
		endcase
	end

	//----------------------------------------------------------------------
	//--   状态机第3段（状态对输出的影响）
	//----------------------------------------------------------------------
	// AHB信号产生
	reg 	BC_WACK_reg;
	always @(posedge HCLK or negedge HRESETn)begin
		if(!HRESETn)begin
			BC_WACK_reg <= 1'b0;
		end
		else begin
			BC_WACK_reg <= BC_WACK;					// 延迟一拍
		end
	end

	always @(*) begin
		if(~HRESETn)begin
			HREADYOUT <= 1'b1;
		end
		else if(std_cur == STD_WDATA) begin
			HREADYOUT <= BC_WACK_reg;				// 写数据完成
		end
		else if(std_cur == STD_RDATA) begin
			HREADYOUT <= BC_RACK;					// 读数据完成
		end
		else begin
			HREADYOUT <= 1'b1;						// 防御性编程：异常状态恢复
		end
	end

	assign HRDATA = BC_RDATA; 						// 输出读数据
	always @(posedge HCLK or negedge HRESETn)begin
		if(!HRESETn)begin
			HRESP <= 1'b0;
		end
		else if((std_next == STD_WRESP) & BC_BACK) begin
			HRESP <= BC_WRESP; 						// 输出写响应信息
		end
		else if((std_cur == STD_RDATA) & BC_RACK) begin
			HRESP <= BC_RRESP; 						// 输出读响应信息
		end
	end

	//BC数据信号产生
	assign BC_WREQ = HSEL & HREADY & (HTRANS[1] == 1'b1) & HWRITE;		// BC写请求
	assign BC_RREQ = HSEL & HREADY & (HTRANS[1] == 1'b1) & (~HWRITE);	// BC读请求
	assign BC_WDATA = HWDATA;						// 采样写数据

endmodule

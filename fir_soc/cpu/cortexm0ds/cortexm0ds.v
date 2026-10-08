//------------------------------------------------------------------------------
// The confidential and proprietary information contained in this file may
// only be used by a person authorised under and to the extent permitted
// by a subsisting licensing agreement from ARM Limited.
//
//            (C) COPYRIGHT 2010-2015  ARM Limited or its affiliates.
//                ALL RIGHTS RESERVED
//
// This entire notice must be reproduced on all copies of this file
// and copies of this file may only be made by a person if such person is
// permitted to do so under the terms of a subsisting license agreement
// from ARM Limited.
//
//  Version and Release Control Information:
//
//  File Revision       : $Revision: 275084 $
//  File Date           : $Date: 2014-03-27 15:09:11 +0000 (Thu, 27 Mar 2014) $
//
//  Release Information : Cortex-M0 DesignStart-r1p0-00rel0
//------------------------------------------------------------------------------
// Verilog-2001 (IEEE Std 1364-2001)
//------------------------------------------------------------------------------
//
//------------------------------------------------------------------------------
// Cortex-M0 DesignStart processor macro cell level
//------------------------------------------------------------------------------

module cortexm0ds (
    // CLOCK AND RESETS ------------------
    input  wire             ACLK,               // Clock
    input  wire             ARESETn,            // Asynchronous reset

    //----------------- AXI - Write -----------------
    output wire             AW_VALID,           // Write request valid
    input wire              AW_READY,           // Write request ready
    output wire [2:0]       AW_SIZE,            // Write data size
    output wire [1:0]       AW_BURST,           // Write burst type
    output wire [7:0]       AW_LEN,             // Write burst length
    output wire [31:0]      AW_ADDR,            // Write address
    output wire             W_VALID,            // Write data valid
    input wire              W_READY,            // Write data ready
    output wire             W_LAST,             // Write data last
    output wire [31:0]      W_DATA,             // Write data
    input wire              B_VALID,            // Write response valid
    output wire             B_READY,            // Write response ready
    input wire  [1:0]       B_RESP,             // Write response

    //----------------- AXI - Read ------------------
    output wire             AR_VALID,           // Read request valid
    input wire              AR_READY,           // Read request ready
    output wire [2:0]       AR_SIZE,            // Read data size
    output wire [1:0]       AR_BURST,           // Read burst type
    output wire [7:0]       AR_LEN,             // Read burst length
    output wire [31:0]      AR_ADDR,            // Read address
    input wire              R_VALID,            // Read data valid
    output wire             R_READY,            // Read data ready
    input wire              R_LAST,             // Read data last
    input wire  [31:0]      R_DATA,             // Read data
    input wire  [1:0]       R_RESP,             // Read response

    // MISCELLANEOUS ---------------------
    input  wire             NMI,                // Non-maskable interrupt input
    input  wire [31:0]      IRQ,                // Interrupt request inputs
    output wire             TXEV,               // Event output (SEV executed)
    input  wire             RXEV,               // Event input
    output wire             LOCKUP,             // Core is locked-up
    output wire             SYSRESETREQ,        // System reset request
    input  wire             STCLKEN,            // SysTick SCLK clock enable
    input  wire [25:0]      STCALIB,            // SysTick calibration register value

    // POWER MANAGEMENT ------------------
    output wire             SLEEPING            // Core and NVIC sleeping
    );

    //------------------------------------------------------------------------------
    // Declare visibility signals and some intermediate signals
    //------------------------------------------------------------------------------
    wire [31: 0]        cm0_r00;
    wire [31: 0]        cm0_r01;
    wire [31: 0]        cm0_r02;
    wire [31: 0]        cm0_r03;
    wire [31: 0]        cm0_r04;
    wire [31: 0]        cm0_r05;
    wire [31: 0]        cm0_r06;
    wire [31: 0]        cm0_r07;
    wire [31: 0]        cm0_r08;
    wire [31: 0]        cm0_r09;
    wire [31: 0]        cm0_r10;
    wire [31: 0]        cm0_r11;
    wire [31: 0]        cm0_r12;
    wire [31: 0]        cm0_msp;
    wire [31: 0]        cm0_psp;
    wire [31: 0]        cm0_r14;
    wire [31: 0]        cm0_pc;
    wire [31: 0]        cm0_xpsr;
    wire [31: 0]        cm0_control;
    wire [31: 0]        cm0_primask;

    wire [29: 0]        vis_msp;
    wire [29: 0]        vis_psp;
    wire [30: 0]        vis_pc;
    wire [ 3: 0]        vis_apsr;
    wire                vis_tbit;
    wire [ 5: 0]        vis_ipsr;
    wire                vis_control;
    wire                vis_primask;

    // ------------------------------------------------------------
    // AHB-LITE MASTER PORT
    // ------------------------------------------------------------
    wire                HCLK;
    wire                HRESETn;
    wire [ 1:0]         HTRANS;
    wire [ 2:0]         HBURST;
    wire                HMASTLOCK;
    wire [ 3:0]         HPROT;
    wire [ 2:0]         HSIZE;
    wire                HWRITE;
    wire [31:0]         HADDR;
    wire [31:0]         HWDATA;
    wire                HREADY;
    wire [31:0]         HRDATA;
    wire                HRESP;

   // ------------------------------------------------------------
   assign HCLK = ACLK;
   assign HRESETn = ARESETn;


    //------------------------------------------------------------------------------
    // Instantiate Cortex-M0 processor logic level
    //------------------------------------------------------------------------------

    cortexm0ds_logic u_logic (
        .hclk                 (HCLK),
        .hreset_n             (HRESETn),

        .haddr_o              (HADDR[31:0]),
        .hburst_o             (HBURST[2:0]),
        .hmastlock_o          (HMASTLOCK),
        .hprot_o              (HPROT[3:0]),
        .hsize_o              (HSIZE[2:0]),
        .htrans_o             (HTRANS[1:0]),
        .hwdata_o             (HWDATA[31:0]),
        .hwrite_o             (HWRITE),
        .hrdata_i             (HRDATA[31:0]),
        .hready_i             (HREADY),
        .hresp_i              (HRESP),

        .nmi_i                (NMI),
        .irq_i                (IRQ),
        .txev_o               (TXEV),
        .rxev_i               (RXEV),
        .lockup_o             (LOCKUP),
        .sys_reset_req_o      (SYSRESETREQ),
        .st_clk_en_i          (STCLKEN),
        .st_calib_i           (STCALIB),

        .sleeping_o           (SLEEPING),

        .vis_r0_o             (cm0_r00[31:0]),
        .vis_r1_o             (cm0_r01[31:0]),
        .vis_r2_o             (cm0_r02[31:0]),
        .vis_r3_o             (cm0_r03[31:0]),
        .vis_r4_o             (cm0_r04[31:0]),
        .vis_r5_o             (cm0_r05[31:0]),
        .vis_r6_o             (cm0_r06[31:0]),
        .vis_r7_o             (cm0_r07[31:0]),
        .vis_r8_o             (cm0_r08[31:0]),
        .vis_r9_o             (cm0_r09[31:0]),
        .vis_r10_o            (cm0_r10[31:0]),
        .vis_r11_o            (cm0_r11[31:0]),
        .vis_r12_o            (cm0_r12[31:0]),
        .vis_msp_o            (vis_msp[29:0]),
        .vis_psp_o            (vis_psp[29:0]),
        .vis_r14_o            (cm0_r14[31:0]),
        .vis_pc_o             (vis_pc[30:0]),
        .vis_apsr_o           (vis_apsr[3:0]),
        .vis_tbit_o           (vis_tbit),
        .vis_ipsr_o           (vis_ipsr[5:0]),
        .vis_control_o        (vis_control),
        .vis_primask_o        (vis_primask)
    );

    //------------------------------------------------------------------------------
    // Construct some visibility signals out of intermediate signals
    //------------------------------------------------------------------------------

    assign cm0_msp     = {vis_msp[29:0],2'd0};
    assign cm0_psp     = {vis_psp[29:0],2'd0};
    assign cm0_pc      = {vis_pc[30:0],1'b0};
    assign cm0_xpsr    = {vis_apsr[3:0],3'd0,vis_tbit,18'd0,vis_ipsr[5:0]};
    assign cm0_control = {30'd0,vis_control,1'b0};
    assign cm0_primask = {31'd0,vis_primask};


    // ------------------------------------------------------------
    // ABH slave <-> AXI master interface
    // ------------------------------------------------------------
    ahb2axi4_if 
     u_ahb2axi4_if
    (
        .HCLK               (ACLK),
        .HRESETn            (ARESETn),
        .ACLK               (ACLK),
        .ARESETn            (ARESETn),

        // --------------------- AHB ---------------------
        .HSEL               (1'b1),
        .HTRANS             (HTRANS[1:0]),
        .HSIZE              (HSIZE[2:0]),
        .HBURST             (HBURST[2:0]),
        .HWRITE             (HWRITE), 
        .HREADY             (HREADY),
        .HADDR              (HADDR[31:0]),
        .HWDATA             (HWDATA[31:0]),
        .HREADYOUT          (HREADY),
        .HRDATA             (HRDATA[31:0]),
        .HRESP              (HRESP),

        //---- AXI - Write -----------------
        .AW_VALID           (AW_VALID),
        .AW_READY           (AW_READY),
        .AW_SIZE            (AW_SIZE),
        .AW_BURST           (AW_BURST),
        .AW_LEN             (AW_LEN),
        .AW_ADDR            (AW_ADDR),
        .W_VALID            (W_VALID),
        .W_READY            (W_READY),
        .W_LAST             (W_LAST),
        .W_DATA             (W_DATA),
        .B_VALID            (B_VALID),
        .B_READY            (B_READY),
        .B_RESP             (B_RESP),

        //---- AXI - Read ------------------
        .AR_VALID           (AR_VALID),
        .AR_READY           (AR_READY),
        .AR_SIZE            (AR_SIZE),
        .AR_BURST           (AR_BURST),
        .AR_LEN             (AR_LEN),
        .AR_ADDR            (AR_ADDR),
        .R_VALID            (R_VALID),
        .R_READY            (R_READY),
        .R_LAST             (R_LAST),
        .R_DATA             (R_DATA),
        .R_RESP             (R_RESP)
    );

endmodule

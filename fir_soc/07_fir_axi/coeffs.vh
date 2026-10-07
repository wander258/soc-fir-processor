// ============================================================
// 本文件由 gen_fir_vectors.py 自动生成，不要手动修改
// 抽头数 NTAP = 9，系数位宽 CW = 16（Q1.15 定点）
// 对称性检查：h[k] == h[NTAP-1-k]（线性相位 FIR）
// ============================================================
localparam signed [CW-1:0] H0 = -16'sd134;
localparam signed [CW-1:0] H1 = 16'sd252;
localparam signed [CW-1:0] H2 = 16'sd2925;
localparam signed [CW-1:0] H3 = 16'sd7973;
localparam signed [CW-1:0] H4 = 16'sd10735;
localparam signed [CW-1:0] H5 = 16'sd7973;
localparam signed [CW-1:0] H6 = 16'sd2925;
localparam signed [CW-1:0] H7 = 16'sd252;
localparam signed [CW-1:0] H8 = -16'sd134;

assign h[0] = H0;
assign h[1] = H1;
assign h[2] = H2;
assign h[3] = H3;
assign h[4] = H4;
assign h[5] = H5;
assign h[6] = H6;
assign h[7] = H7;
assign h[8] = H8;

/* ============================================================
 * fir_regs.h —— SoC 寄存器映射（内存地图）
 *
 * 这份文件是"软硬件之间的合同"：C 代码和 Verilog 都照它来。
 * 地址必须和 rtl/axi_lite_xbar.v、rtl/fir_axi.v、rtl/uart_axi.v
 * 里定义的一字不差，否则 CPU 写的就是错的寄存器。
 *
 * 真系统里，Cortex-M0 就是通过读/写这些地址来控制 FIR 和 UART 的。
 * ============================================================ */
#ifndef FIR_REGS_H
#define FIR_REGS_H

#include <stdint.h>

/* ---- 三个外设的基地址（和 axi_lite_xbar.v 一致）---- */
#define FIR_BASE   0x00000000u   /* FIR 滤波器 */
#define UART_BASE  0x00001000u   /* UART */
#define SRAM_BASE  0x00002000u   /* 片上 SRAM */

/* ---- FIR 寄存器（相对 FIR_BASE，和 fir_axi.v 一致）---- */
#define FIR_CTRL   (FIR_BASE + 0x000u)   /* 写：[0] START=1 清空，准备新一轮 */
#define FIR_DIN    (FIR_BASE + 0x004u)   /* 写：低 16bit = 一个输入样本 */
#define FIR_DOUT   (FIR_BASE + 0x008u)   /* 读：低 16bit = 一个滤波结果 */
#define FIR_STATUS (FIR_BASE + 0x00Cu)   /* 读：[0]空 [1]满 [31:16]结果个数 */
#define FIR_COEF(k) (FIR_BASE + 0x100u + 4u*(k))  /* 写：第 k 个系数 */

#define FIR_CTRL_START  0x1u
#define FIR_STATUS_EMPTY 0x1u
#define FIR_STATUS_FULL  0x2u

/* ---- UART 寄存器（相对 UART_BASE，和 uart_axi.v 一致）---- */
#define UART_DATA   (UART_BASE + 0x000u)  /* 写：低 8bit = 要发送的字节 */
#define UART_STATUS (UART_BASE + 0x004u)  /* 读：[0] busy */

#define UART_STATUS_BUSY 0x1u

/* ---- 内存映射访问宏：把地址当成 volatile 指针去读写 ---- */
#define REG32(addr)  (*(volatile uint32_t *)(addr))

#endif /* FIR_REGS_H */

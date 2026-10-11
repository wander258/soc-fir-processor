/* ============================================================
 * fir_driver.h —— FIR + UART 的 C 驱动 API
 *
 * 这些函数就是赛题"软硬协同验证"里，跑在 Cortex-M0 上的驱动。
 * 在仿真里没有真 CPU，我们用测试台里的 BFM 把完全相同的寄存器操作
 * 重放了一遍，所以这份 C 代码就是"CPU 那边真正会执行的逻辑"。
 * ============================================================ */
#ifndef FIR_DRIVER_H
#define FIR_DRIVER_H

#include <stdint.h>

/* 写一个 FIR 系数（Q1.15） */
void fir_write_coeff(uint32_t idx, int16_t coef);

/* 清空 FIR：写 CTRL 的 START 位，准备处理新的一帧数据 */
void fir_reset(void);

/* 写入一个输入样本（Q1.15） */
void fir_write_sample(int16_t sample);

/* 读出一个滤波结果；没有结果时返回 0 */
int16_t fir_read_result(void);

/* 查询还有多少个结果可读 */
uint32_t fir_result_count(void);

/* UART 发送一个字节（会等 busy=0） */
void uart_putc(char ch);

/* UART 发送一串字符 */
void uart_puts(const char *s);

#endif /* FIR_DRIVER_H */

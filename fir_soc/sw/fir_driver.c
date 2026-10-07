/* ============================================================
 * fir_driver.c —— FIR + UART 的 C 驱动实现
 *
 * 每一个函数都只做一件事：读写某个寄存器地址。
 * 对照仿真测试台 tb_soc.v 里 BFM 做的 axi_write/axi_read，
 * 你会发现两边是一一对应的——这就是"软硬协同验证"的闭环。
 * ============================================================ */
#include "fir_regs.h"
#include "fir_driver.h"

void fir_write_coeff(uint32_t idx, int16_t coef)
{
    /* 系数是 16bit 有符号，写进 32bit 寄存器的低 16bit */
    REG32(FIR_COEF(idx)) = (uint32_t)(uint16_t)coef;
}

void fir_reset(void)
{
    REG32(FIR_CTRL) = FIR_CTRL_START;
}

void fir_write_sample(int16_t sample)
{
    REG32(FIR_DIN) = (uint32_t)(uint16_t)sample;
}

int16_t fir_read_result(void)
{
    /* 结果在低 16bit；转回有符号数 */
    return (int16_t)(uint16_t)REG32(FIR_DOUT);
}

uint32_t fir_result_count(void)
{
    /* 结果个数在 [31:16] */
    return (REG32(FIR_STATUS) >> 16) & 0xFFFFu;
}

void uart_putc(char ch)
{
    /* 等上一次发送结束（busy=0）再写下一个字节 */
    while (REG32(UART_STATUS) & UART_STATUS_BUSY)
        ;
    REG32(UART_DATA) = (uint32_t)(uint8_t)ch;
}

void uart_puts(const char *s)
{
    while (*s)
        uart_putc(*s++);
}

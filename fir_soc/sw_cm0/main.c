/* ============================================================
 * main.c —— 跑在 Cortex-M0 上的应用：用 C 控制 FIR 滤波器
 *
 * 做的事和之前 BFM 版(08_soc)一模一样，但这次是【真 CPU】在跑：
 *   1) 写 81 个系数    2) 清空 FIR    3) 喂样本    4) 排空
 *   5) 读结果          6) 串口打印
 *
 * 系数和激励由 sw_cm0/build.py 从 gen_fir_vectors.py 生成到 fir_data.h。
 * ============================================================ */
#include <stdint.h>
#include "fir_data.h"

/* ---- SoC 内存地图（和 soc_cm0_top.v 一致）---- */
#define FIR_BASE    0x40000000u
#define FIR_CTRL    (FIR_BASE + 0x000u)   /* [0] START=1 清空 */
#define FIR_DIN     (FIR_BASE + 0x004u)   /* 写样本 */
#define FIR_DOUT    (FIR_BASE + 0x008u)   /* 读结果 */
#define FIR_STATUS  (FIR_BASE + 0x00Cu)
#define FIR_COEF(k) (FIR_BASE + 0x100u + 4u*(k))
#define UART_BASE   0x40001000u
#define UART_DATA   (UART_BASE + 0x000u)
#define UART_STATUS (UART_BASE + 0x004u)  /* [0] busy */

#define REG32(a) (*(volatile uint32_t *)(a))

/* ---- 简单串口驱动 ---- */
static void uart_putc(char c)
{
    while (REG32(UART_STATUS) & 1u) ;     /* 等 busy=0 */
    REG32(UART_DATA) = (uint32_t)(uint8_t)c;
}
static void uart_puts(const char *s) { while (*s) uart_putc(*s++); }

/* ---- 打印 16bit 有符号数的 4 位十六进制（不用除法，M0 无除法器）---- */
static void print_hex4(uint16_t v)
{
    int i;
    for (i = 3; i >= 0; i--) {
        uint8_t nib = (uint8_t)((v >> (4 * i)) & 0xFu);
        uart_putc((char)(nib < 10 ? ('0' + nib) : ('A' + nib - 10)));
    }
}

int main(void)
{
    int i;

    /* 1) 写系数 */
    for (i = 0; i < NTAP; i++)
        REG32(FIR_COEF(i)) = (uint32_t)(uint16_t)h[i];

    /* 2) 清空 */
    REG32(FIR_CTRL) = 1u;

    /* 3) 喂样本 */
    for (i = 0; i < NSAMP; i++)
        REG32(FIR_DIN) = (uint32_t)(uint16_t)x[i];

    /* 4) 再喂 NTAP 个 0 排空延迟线 */
    for (i = 0; i < NTAP; i++)
        REG32(FIR_DIN) = 0u;

    /* 5) 读结果：丢掉第 1 个（流水线前导 0），打印后面 NEXP 个 */
    (void)REG32(FIR_DOUT);

    uart_puts("FIR_RESULT_BEGIN\n");
    for (i = 0; i < NSAMP + NTAP - 1; i++) {
        uint16_t y = (uint16_t)REG32(FIR_DOUT);
        print_hex4(y);
        uart_putc('\n');
    }
    uart_puts("FIR_RESULT_END\n");

    while (1) { }
    return 0;
}

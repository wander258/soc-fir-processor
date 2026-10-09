/* ============================================================
 * main.c —— 应用示例：CPU 怎么用 FIR + UART（软硬协同的"C"那一半）
 *
 * 这个文件跑在 Cortex-M0 上，干的事和仿真测试台 tb_soc.v 完全一样：
 *   配置系数 -> 清空 -> 喂样本 -> 读结果 -> 串口打印。
 *
 * 编译（真系统，需要 ARM 交叉编译器）：
 *   arm-none-eabi-gcc -mcpu=cortex-m0 -Os -I. main.c fir_driver.c -o fir.elf
 *
 * 这里用了 9 阶系数当例子（数组短、好读）；换成 81 阶只是把数组
 * 换成 gen_fir_vectors.py 生成的 81 个系数，其余代码一行不用改。
 * ============================================================ */
#include "fir_driver.h"
#include "fir_regs.h"

/* ---- 9 阶低通 FIR 系数（Q1.15，由 gen_fir_vectors.py 生成）----
 * 真实值 = 整数 / 32768。注意它是对称的（h[k]==h[NTAP-1-k]）。
 * 换成 81 阶：把 NTAP 改成 81，h[] 换成 81 个生成好的系数即可。 */
#define NTAP 9
static const int16_t h[NTAP] = {
     -134,   252,  2925,  7973, 10735,  7973,  2925,   252,  -134
};

/* ---- 测试激励：一个单位冲激（1.0）后面跟一串 0 ----
 * 冲激响应的输出应该正好就是系数本身，非常直观。 */
#define NSAMP 16
static const int16_t x[NSAMP] = {
    32767, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
};

int main(void)
{
    uint32_t i;

    /* 1) 配置系数 */
    for (i = 0; i < NTAP; i++)
        fir_write_coeff(i, h[i]);

    /* 2) 清空，准备新一轮 */
    fir_reset();

    /* 3) 喂入样本 */
    for (i = 0; i < NSAMP; i++)
        fir_write_sample(x[i]);

    /* 4) 再喂 NTAP 个 0，把延迟线里的样本"排空"，
     *    这样能拿到完整的卷积结果（样本数 + 抽头数 - 1 个） */
    for (i = 0; i < NTAP; i++)
        fir_write_sample(0);

    /* 5) 读结果并通过串口打印（省去流水线前导那一个 0） */
    uart_puts("\r\nFIR impulse response:\r\n");
    fir_read_result();                    /* 丢弃第 1 个（流水线前导 0） */

    for (i = 0; i < NSAMP + NTAP - 1; i++) {
        int16_t y = fir_read_result();
        /* 把结果按十进制打印（简化版，仅演示） */
        uart_puts(" ");
        if (y < 0) { uart_putc('-'); y = (int16_t)-y; }
        uart_putc((char)('0' + (y / 10000) % 10));
        uart_putc((char)('0' + (y / 1000)  % 10));
        uart_putc((char)('0' + (y / 100)   % 10));
        uart_putc((char)('0' + (y / 10)    % 10));
        uart_putc((char)('0' + (y % 10)));
    }
    uart_puts("\r\n");

    return 0;
}

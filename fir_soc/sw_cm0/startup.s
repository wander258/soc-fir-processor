/* ============================================================
 * startup.s —— Cortex-M0 启动代码 + 向量表
 *
 * Cortex-M0 上电后做的第一件事：
 *   从地址 0x0 读初始栈指针，从地址 0x4 读复位入口地址，然后跳过去。
 * 所以向量表的前两个"字"必须正好是 [栈指针, 复位入口]。
 * ============================================================ */
    .syntax unified
    .cpu cortex-m0
    .thumb

    .global _estack
    .global Reset_Handler

    .section .vectors, "a"   /* "a"=allocatable，确保向量表占用 0x0 起的地址 */
    .word _estack          /* 0x0: 初始栈指针 */
    .word Reset_Handler    /* 0x4: 复位入口 */
    .rept 46               /* 其余 46 个向量（本程序不用中断，统一填默认处理）*/
    .word Default_Handler
    .endr

    .section .text
    .thumb_func
    .type Reset_Handler, %function
Reset_Handler:
    bl main                /* 调用 C 的 main() */
    b .                    /* 死循环 */

    .thumb_func
Default_Handler:
    b .

    .end

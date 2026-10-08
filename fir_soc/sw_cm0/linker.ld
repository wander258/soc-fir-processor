/* ============================================================
 * linker.ld —— Cortex-M0 程序的链接脚本
 *
 * 把程序放进 0x00000000 开始的 64KB RAM：
 *   向量表(.vectors)放最前面，这样 0x0 是初始栈指针、0x4 是复位入口，
 *   这正是 Cortex-M0 上电后要读的前两个地址。
 * ============================================================ */
MEMORY
{
    RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 64K
}

_estack = ORIGIN(RAM) + LENGTH(RAM);   /* 栈顶 = 0x00010000 */

SECTIONS
{
    .vectors : { KEEP(*(.vectors)) } > RAM
    .text    : { *(.text*) } > RAM
    .rodata  : { *(.rodata*) } > RAM
    .data    : { *(.data*) } > RAM
    .bss     : { *(.bss*) *(COMMON) } > RAM
}

ENTRY(_start)

MEMORY
{
    instr_ram (rwx) : ORIGIN = 0x00000000, LENGTH = 64K
    data_ram  (rw)  : ORIGIN = 0x00010000, LENGTH = 64K
}

SECTIONS
{
    .text :
    {
        KEEP(*(.init))
        *(.text*)
        *(.rodata*)
    } > instr_ram

    .data : { *(.data*) } > data_ram

    .bss :
    {
        *(.bss*)
        *(COMMON)
    } > data_ram

    _stack_top = ORIGIN(data_ram) + LENGTH(data_ram);

    /DISCARD/ : { *(.eh_frame) *(.comment) }
}

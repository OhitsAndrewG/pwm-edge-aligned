/*
 * STM32F411CEUx_FLASH.ld - link into internal flash, run from internal SRAM.
 *
 * STM32F411CEU6: 512 KB flash at 0x08000000, 128 KB SRAM at 0x20000000.
 * The stack grows down from the top of RAM; the heap is unused (nothing here
 * calls malloc) but the guard below still checks there is room for both.
 */

ENTRY(Reset_Handler)

/* Top of RAM. Vector table entry 0, loaded into SP by the CPU at reset. */
_estack = ORIGIN(RAM) + LENGTH(RAM);

_Min_Heap_Size  = 0x200;   /* 512 B  - unused, reserved for a future printf  */
_Min_Stack_Size = 0x400;   /* 1 KB   - plenty: no recursion, one shallow ISR */

MEMORY
{
  RAM   (xrw) : ORIGIN = 0x20000000, LENGTH = 128K
  FLASH (rx)  : ORIGIN = 0x08000000, LENGTH = 512K
}

SECTIONS
{
  /* Must be first: the CPU fetches the initial SP and PC from 0x08000000. */
  .isr_vector :
  {
    . = ALIGN(4);
    KEEP(*(.isr_vector))   /* KEEP - nothing references it, so --gc-sections
                            * would otherwise discard the whole table */
    . = ALIGN(4);
  } >FLASH

  .text :
  {
    . = ALIGN(4);
    *(.text)
    *(.text*)
    *(.glue_7)             /* ARM/Thumb interworking veneers */
    *(.glue_7t)
    *(.eh_frame)

    KEEP (*(.init))
    KEEP (*(.fini))

    . = ALIGN(4);
    _etext = .;            /* end of code; the .data image follows */
  } >FLASH

  .rodata :
  {
    . = ALIGN(4);
    *(.rodata)
    *(.rodata*)
    . = ALIGN(4);
  } >FLASH

  /* Exception-unwinding tables. Unused by C, but the linker warns if the
   * .ARM.exidx section has no home. */
  .ARM.extab : {
    . = ALIGN(4);
    *(.ARM.extab* .gnu.linkonce.armextab.*)
    . = ALIGN(4);
  } >FLASH

  .ARM : {
    . = ALIGN(4);
    __exidx_start = .;
    *(.ARM.exidx*)
    __exidx_end = .;
    . = ALIGN(4);
  } >FLASH

  .preinit_array :
  {
    . = ALIGN(4);
    PROVIDE_HIDDEN (__preinit_array_start = .);
    KEEP (*(.preinit_array*))
    PROVIDE_HIDDEN (__preinit_array_end = .);
    . = ALIGN(4);
  } >FLASH

  .init_array :
  {
    . = ALIGN(4);
    PROVIDE_HIDDEN (__init_array_start = .);
    KEEP (*(SORT(.init_array.*)))
    KEEP (*(.init_array*))
    PROVIDE_HIDDEN (__init_array_end = .);
    . = ALIGN(4);
  } >FLASH

  .fini_array :
  {
    . = ALIGN(4);
    PROVIDE_HIDDEN (__fini_array_start = .);
    KEEP (*(SORT(.fini_array.*)))
    KEEP (*(.fini_array*))
    PROVIDE_HIDDEN (__fini_array_end = .);
    . = ALIGN(4);
  } >FLASH

  /* Address in FLASH of the initialiser image that Reset_Handler copies. */
  _sidata = LOADADDR(.data);

  /* Initialised data: lives in RAM at run time (>RAM), stored in flash
   * (AT> FLASH). The startup code copies _sidata -> [_sdata, _edata). */
  .data :
  {
    . = ALIGN(4);
    _sdata = .;
    *(.data)
    *(.data*)
    . = ALIGN(4);
    _edata = .;
  } >RAM AT> FLASH

  /* Zero-initialised data. Occupies no space in flash; Reset_Handler clears
   * [_sbss, _ebss). */
  . = ALIGN(4);
  .bss :
  {
    _sbss = .;
    __bss_start__ = _sbss;
    *(.bss)
    *(.bss*)
    *(COMMON)
    . = ALIGN(4);
    _ebss = .;
    __bss_end__ = _ebss;
  } >RAM

  /* Link-time check that heap + stack still fit in what is left of RAM.
   * Cheaper to catch here than as a stack overflow at 3 a.m. */
  ._user_heap_stack :
  {
    . = ALIGN(8);
    PROVIDE ( end = . );
    PROVIDE ( _end = . );
    . = . + _Min_Heap_Size;
    . = . + _Min_Stack_Size;
    . = ALIGN(8);
  } >RAM

  .ARM.attributes 0 : { *(.ARM.attributes) }
}

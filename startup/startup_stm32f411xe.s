/**
 * startup_stm32f411xe.s - minimal Cortex-M4 startup for the STM32F411CEU6.
 *
 * Responsibilities, in order:
 *   1. Provide the vector table (the CPU fetches the initial SP and PC from
 *      the first two words of flash at reset - no code runs before that).
 *   2. Copy initialised data from flash to RAM.
 *   3. Zero the .bss section.
 *   4. Call SystemInit() (enables the FPU - see main.c).
 *   5. Call main(), and trap if it ever returns.
 *
 * Every interrupt vector is a weak alias to Default_Handler, so defining a
 * handler anywhere in C (e.g. SysTick_Handler in main.c) automatically
 * overrides it with no registration step.
 */

  .syntax unified
  .cpu cortex-m4
  .fpu fpv4-sp-d16
  .thumb

.global g_pfnVectors
.global Default_Handler

/* Symbols supplied by the linker script. */
.word _sidata      /* start of the .data initialiser image in flash */
.word _sdata       /* start of .data in RAM                         */
.word _edata       /* end of .data in RAM                           */
.word _sbss        /* start of .bss                                 */
.word _ebss        /* end of .bss                                   */

  .section .text.Reset_Handler
  .weak Reset_Handler
  .type Reset_Handler, %function
Reset_Handler:
  /* ------------------------------------------------------------------
   * By the time this label is reached the CPU has ALREADY, in hardware:
   *   - loaded SP (r13) from vector table word 0  -> _estack = 0x20020000
   *   - loaded PC (r15) from vector table word 1  -> this address
   * So the stack works from the very first instruction.
   *
   * Nothing else has happened. No C runtime has run, globals are not
   * initialised, and .bss holds whatever random bits SRAM powered up with.
   * The four steps below ARE the C runtime for this project.
   * ------------------------------------------------------------------ */

  /* --- Step 1: copy .data from flash into RAM -------------------------
   * An initialised global (int foo = 42;) has to be writable, so it lives
   * in RAM - but its starting value has to survive power-off, so it is
   * stored in flash. Something must copy one to the other. That is us.
   *
   * Two different LDR forms appear below:
   *   ldr rX, =sym      load the ADDRESS of sym  (assembler pseudo-op:
   *                     the 32-bit constant is placed in a nearby literal
   *                     pool and fetched PC-relative, because a 32-bit
   *                     instruction cannot hold a 32-bit constant inline)
   *   ldr rX, [rA, rB]  load the VALUE stored at address (rA + rB)
   */
  ldr   r0, =_sdata       /* r0 = destination: start of .data in RAM      */
  ldr   r1, =_edata       /* r1 = end of .data in RAM (loop stop value)   */
  ldr   r2, =_sidata      /* r2 = source: the .data image held in flash   */
  movs  r3, #0            /* r3 = byte offset, counts up 0,4,8,...        */
  b     LoopCopyDataInit  /* test BEFORE the first copy, so a zero-length
                           * .data section copies nothing at all          */

CopyDataInit:
  ldr   r4, [r2, r3]      /* r4 = one 32-bit word of flash at (r2 + r3)   */
  str   r4, [r0, r3]      /* STR = store: write that word to RAM (r0+r3)  */
  adds  r3, r3, #4        /* advance by one word; "s" also sets flags     */

LoopCopyDataInit:
  adds  r4, r0, r3        /* r4 = address we would write next             */
  cmp   r4, r1            /* compare against _edata                       */
  bcc   CopyDataInit      /* BCC = Branch if Carry Clear = "branch if
                           * unsigned less-than". Loops while r4 < r1.    */

  /* --- Step 2: zero .bss ---------------------------------------------
   * C guarantees uninitialised statics read as 0. No hardware does that -
   * SRAM comes up with garbage - so the guarantee is only true because
   * these six instructions make it true.
   */
  ldr   r2, =_sbss        /* r2 = cursor, walks through .bss              */
  ldr   r4, =_ebss        /* r4 = end of .bss                             */
  movs  r3, #0            /* r3 = the value being written: zero           */
  b     LoopFillZerobss   /* again, test first                            */

FillZerobss:
  str   r3, [r2]          /* write 0 to the word at r2                    */
  adds  r2, r2, #4        /* next word                                    */

LoopFillZerobss:
  cmp   r2, r4            /* reached _ebss?                               */
  bcc   FillZerobss       /* loop while r2 < r4                           */

  /* --- Step 3: enable the FPU ----------------------------------------
   * Must happen before ANY floating-point instruction executes. This build
   * uses -mfloat-abi=hard, so the compiler emits VFP instructions freely,
   * and the FPU is disabled out of reset - the first one would UsageFault.
   *
   * BL = Branch with Link: jump, and save the return address in LR (r14)
   * so that SystemInit's closing "bx lr" lands back on the next line.
   */
  bl    SystemInit

  /* --- Step 4: hand over to C ----------------------------------------- */
  bl    main

  /* main() is typed to return int, but on bare metal it must never return -
   * there is no operating system to return TO. If it somehow does, park
   * here so a debugger shows an obvious stop, rather than letting the CPU
   * run on into whatever bytes happen to follow in flash.
   */
LoopForever:
  b     LoopForever       /* branch to self: deliberate infinite loop     */

  .size Reset_Handler, .-Reset_Handler

/**
 * Default_Handler - catch-all for every exception nobody implemented.
 *
 * Every vector below is a weak alias to this symbol, so an unexpected
 * interrupt lands here instead of running off into unmapped memory.
 * An infinite loop is deliberate: it freezes the CPU at an address the
 * debugger can show you, and the stacked PC on the stack tells you what
 * faulted. A "return" here would silently resume a broken program.
 */
  .section .text.Default_Handler,"ax",%progbits
  .type Default_Handler, %function
Default_Handler:
Infinite_Loop:
  b     Infinite_Loop     /* spin forever - break here in gdb to catch it */
  .size Default_Handler, .-Default_Handler

/******************************************************************************
 * The vector table. Placed at 0x08000000 by the linker script (section
 * .isr_vector). Entry 0 is the initial stack pointer, entry 1 the reset
 * vector; the rest follow the STM32F411xE interrupt map.
 ******************************************************************************/
  .section .isr_vector,"a",%progbits
  .type g_pfnVectors, %object

g_pfnVectors:
  .word _estack                     /* 0x00 initial SP (top of RAM)          */
  .word Reset_Handler               /* 0x04 reset                            */
  .word NMI_Handler
  .word HardFault_Handler
  .word MemManage_Handler
  .word BusFault_Handler
  .word UsageFault_Handler
  .word 0
  .word 0
  .word 0
  .word 0
  .word SVC_Handler
  .word DebugMon_Handler
  .word 0
  .word PendSV_Handler
  .word SysTick_Handler             /* our 1 kHz tick                        */

  /* External interrupts, IRQ 0 upward. */
  .word WWDG_IRQHandler                     /*  0 */
  .word PVD_IRQHandler                      /*  1 */
  .word TAMP_STAMP_IRQHandler               /*  2 */
  .word RTC_WKUP_IRQHandler                 /*  3 */
  .word FLASH_IRQHandler                    /*  4 */
  .word RCC_IRQHandler                      /*  5 */
  .word EXTI0_IRQHandler                    /*  6 */
  .word EXTI1_IRQHandler                    /*  7 */
  .word EXTI2_IRQHandler                    /*  8 */
  .word EXTI3_IRQHandler                    /*  9 */
  .word EXTI4_IRQHandler                    /* 10 */
  .word DMA1_Stream0_IRQHandler             /* 11 */
  .word DMA1_Stream1_IRQHandler             /* 12 */
  .word DMA1_Stream2_IRQHandler             /* 13 */
  .word DMA1_Stream3_IRQHandler             /* 14 */
  .word DMA1_Stream4_IRQHandler             /* 15 */
  .word DMA1_Stream5_IRQHandler             /* 16 */
  .word DMA1_Stream6_IRQHandler             /* 17 */
  .word ADC_IRQHandler                      /* 18 */
  .word 0                                   /* 19 reserved (no CAN1 on F411) */
  .word 0                                   /* 20 reserved                   */
  .word 0                                   /* 21 reserved                   */
  .word 0                                   /* 22 reserved                   */
  .word EXTI9_5_IRQHandler                  /* 23 */
  .word TIM1_BRK_TIM9_IRQHandler            /* 24 */
  .word TIM1_UP_TIM10_IRQHandler            /* 25 */
  .word TIM1_TRG_COM_TIM11_IRQHandler       /* 26 */
  .word TIM1_CC_IRQHandler                  /* 27 */
  .word TIM2_IRQHandler                     /* 28 (unused - no timer IRQ)    */
  .word TIM3_IRQHandler                     /* 29 */
  .word TIM4_IRQHandler                     /* 30 */
  .word I2C1_EV_IRQHandler                  /* 31 */
  .word I2C1_ER_IRQHandler                  /* 32 */
  .word I2C2_EV_IRQHandler                  /* 33 */
  .word I2C2_ER_IRQHandler                  /* 34 */
  .word SPI1_IRQHandler                     /* 35 */
  .word SPI2_IRQHandler                     /* 36 */
  .word USART1_IRQHandler                   /* 37 */
  .word USART2_IRQHandler                   /* 38 */
  .word 0                                   /* 39 reserved (no USART3)       */
  .word EXTI15_10_IRQHandler                /* 40 */
  .word RTC_Alarm_IRQHandler                /* 41 */
  .word OTG_FS_WKUP_IRQHandler              /* 42 */
  .word 0                                   /* 43 reserved                   */
  .word 0                                   /* 44 reserved                   */
  .word 0                                   /* 45 reserved                   */
  .word 0                                   /* 46 reserved                   */
  .word DMA1_Stream7_IRQHandler             /* 47 */
  .word 0                                   /* 48 reserved (no FSMC)         */
  .word SDIO_IRQHandler                     /* 49 */
  .word TIM5_IRQHandler                     /* 50 */
  .word SPI3_IRQHandler                     /* 51 */
  .word 0                                   /* 52 reserved                   */
  .word 0                                   /* 53 reserved                   */
  .word 0                                   /* 54 reserved                   */
  .word 0                                   /* 55 reserved                   */
  .word DMA2_Stream0_IRQHandler             /* 56 */
  .word DMA2_Stream1_IRQHandler             /* 57 */
  .word DMA2_Stream2_IRQHandler             /* 58 */
  .word DMA2_Stream3_IRQHandler             /* 59 */
  .word DMA2_Stream4_IRQHandler             /* 60 */
  .word 0                                   /* 61 reserved                   */
  .word 0                                   /* 62 reserved                   */
  .word 0                                   /* 63 reserved                   */
  .word 0                                   /* 64 reserved                   */
  .word 0                                   /* 65 reserved                   */
  .word 0                                   /* 66 reserved                   */
  .word OTG_FS_IRQHandler                   /* 67 */
  .word DMA2_Stream5_IRQHandler             /* 68 */
  .word DMA2_Stream6_IRQHandler             /* 69 */
  .word DMA2_Stream7_IRQHandler             /* 70 */
  .word USART6_IRQHandler                   /* 71 */
  .word I2C3_EV_IRQHandler                  /* 72 */
  .word I2C3_ER_IRQHandler                  /* 73 */
  .word 0                                   /* 74 reserved                   */
  .word 0                                   /* 75 reserved                   */
  .word 0                                   /* 76 reserved                   */
  .word 0                                   /* 77 reserved                   */
  .word 0                                   /* 78 reserved                   */
  .word 0                                   /* 79 reserved                   */
  .word 0                                   /* 80 reserved                   */
  .word FPU_IRQHandler                      /* 81 */
  .word 0                                   /* 82 reserved                   */
  .word 0                                   /* 83 reserved                   */
  .word SPI4_IRQHandler                     /* 84 */
  .word SPI5_IRQHandler                     /* 85 */

  .size g_pfnVectors, .-g_pfnVectors

/******************************************************************************
 * Weak aliases. Each resolves to Default_Handler unless a strong symbol of
 * the same name is linked in from C.
 ******************************************************************************/

  .macro def_irq_handler handler_name
  .weak \handler_name
  .thumb_set \handler_name, Default_Handler
  .endm

  def_irq_handler NMI_Handler
  def_irq_handler HardFault_Handler
  def_irq_handler MemManage_Handler
  def_irq_handler BusFault_Handler
  def_irq_handler UsageFault_Handler
  def_irq_handler SVC_Handler
  def_irq_handler DebugMon_Handler
  def_irq_handler PendSV_Handler
  def_irq_handler SysTick_Handler
  def_irq_handler WWDG_IRQHandler
  def_irq_handler PVD_IRQHandler
  def_irq_handler TAMP_STAMP_IRQHandler
  def_irq_handler RTC_WKUP_IRQHandler
  def_irq_handler FLASH_IRQHandler
  def_irq_handler RCC_IRQHandler
  def_irq_handler EXTI0_IRQHandler
  def_irq_handler EXTI1_IRQHandler
  def_irq_handler EXTI2_IRQHandler
  def_irq_handler EXTI3_IRQHandler
  def_irq_handler EXTI4_IRQHandler
  def_irq_handler DMA1_Stream0_IRQHandler
  def_irq_handler DMA1_Stream1_IRQHandler
  def_irq_handler DMA1_Stream2_IRQHandler
  def_irq_handler DMA1_Stream3_IRQHandler
  def_irq_handler DMA1_Stream4_IRQHandler
  def_irq_handler DMA1_Stream5_IRQHandler
  def_irq_handler DMA1_Stream6_IRQHandler
  def_irq_handler ADC_IRQHandler
  def_irq_handler EXTI9_5_IRQHandler
  def_irq_handler TIM1_BRK_TIM9_IRQHandler
  def_irq_handler TIM1_UP_TIM10_IRQHandler
  def_irq_handler TIM1_TRG_COM_TIM11_IRQHandler
  def_irq_handler TIM1_CC_IRQHandler
  def_irq_handler TIM2_IRQHandler
  def_irq_handler TIM3_IRQHandler
  def_irq_handler TIM4_IRQHandler
  def_irq_handler I2C1_EV_IRQHandler
  def_irq_handler I2C1_ER_IRQHandler
  def_irq_handler I2C2_EV_IRQHandler
  def_irq_handler I2C2_ER_IRQHandler
  def_irq_handler SPI1_IRQHandler
  def_irq_handler SPI2_IRQHandler
  def_irq_handler USART1_IRQHandler
  def_irq_handler USART2_IRQHandler
  def_irq_handler EXTI15_10_IRQHandler
  def_irq_handler RTC_Alarm_IRQHandler
  def_irq_handler OTG_FS_WKUP_IRQHandler
  def_irq_handler DMA1_Stream7_IRQHandler
  def_irq_handler SDIO_IRQHandler
  def_irq_handler TIM5_IRQHandler
  def_irq_handler SPI3_IRQHandler
  def_irq_handler DMA2_Stream0_IRQHandler
  def_irq_handler DMA2_Stream1_IRQHandler
  def_irq_handler DMA2_Stream2_IRQHandler
  def_irq_handler DMA2_Stream3_IRQHandler
  def_irq_handler DMA2_Stream4_IRQHandler
  def_irq_handler OTG_FS_IRQHandler
  def_irq_handler DMA2_Stream5_IRQHandler
  def_irq_handler DMA2_Stream6_IRQHandler
  def_irq_handler DMA2_Stream7_IRQHandler
  def_irq_handler USART6_IRQHandler
  def_irq_handler I2C3_EV_IRQHandler
  def_irq_handler I2C3_ER_IRQHandler
  def_irq_handler FPU_IRQHandler
  def_irq_handler SPI4_IRQHandler
  def_irq_handler SPI5_IRQHandler

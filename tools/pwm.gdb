# GDB helpers for pwm-edge-aligned
#   load with:   source tools/pwm.gdb
#
# Uses RAW ADDRESSES rather than the CMSIS macros (RCC, GPIOA, TIM2), because
# those are preprocessor macros and only resolve when you are stopped inside a
# file that included stm32f4xx.h. Addresses work from anywhere - including
# main.c, which no longer includes it after the driver was split out.
#
#   RCC   base 0x40023800    AHB1ENR +0x30   APB1ENR +0x40
#   GPIOA base 0x40020000    MODER   +0x00   AFR[0]  +0x20   AFR[1] +0x24
#   TIM2  base 0x40000000    CR1 +0x00  EGR +0x14  CCMR1 +0x18  CCER +0x20
#                            CNT +0x24  PSC +0x28  ARR   +0x2c  CCR2  +0x38
# --------------------------------------------------------------------------

define pos
  set *(unsigned int *)0x40000038 = $arg0
  printf "CCR2 = %u us\n", *(unsigned int *)0x40000038
end
document pos
Set the PWM pulse width in microseconds.  Usage: pos 1500
Safe servo range is roughly 1000-2000; outside that most servos drive against
a mechanical stop, stall and overheat.
end

define regs
  printf "--- clocks ---\n"
  printf "  RCC_AHB1ENR  0x%08x   bit0 GPIOAEN should be 1\n", *(unsigned int *)0x40023830
  printf "  RCC_APB1ENR  0x%08x   bit0 TIM2EN  should be 1\n", *(unsigned int *)0x40023840
  printf "--- pin PA1 ---\n"
  printf "  GPIOA_MODER  0x%08x   expect 0xa8000008\n", *(unsigned int *)0x40020000
  printf "  GPIOA_AFRL   0x%08x   expect 0x00000010\n", *(unsigned int *)0x40020020
  printf "  GPIOA_AFRH   0x%08x   expect 0x00000000\n", *(unsigned int *)0x40020024
  printf "--- timer TIM2 ---\n"
  printf "  PSC          %-10u  expect 15   (1 us tick at 16 MHz)\n", *(unsigned int *)0x40000028
  printf "  ARR          %-10u  expect 19999 (20 ms)\n", *(unsigned int *)0x4000002c
  printf "  CCMR1        0x%08x   expect 0x6800 (OC2M=PWM1, OC2PE)\n", *(unsigned int *)0x40000018
  printf "  CCER         0x%08x   bit4 CC2E should be 1\n", *(unsigned int *)0x40000020
  printf "  CR1          0x%08x   bit0 CEN  should be 1\n", *(unsigned int *)0x40000000
  printf "  CCR2         %-10u  us pulse width\n", *(unsigned int *)0x40000038
  printf "  CNT          %-10u\n", *(unsigned int *)0x40000024
end
document regs
Dump every register this project configures, with expected values.
Works from any stack frame - uses raw addresses, not CMSIS macros.
end

define running
  set $a = *(unsigned int *)0x40000024
  set $b = *(unsigned int *)0x40000024
  printf "CNT: %u then %u  ->  ", $a, $b
  if $a != $b
    printf "TIMER IS RUNNING\n"
  else
    printf "STOPPED - check CEN (CR1 bit 0) and that APB1ENR bit 0 is set\n"
  end
end
document running
Read TIM2->CNT twice and report whether the counter is advancing.
end

define rf
  make
  load
  monitor reset
end
document rf
Rebuild, flash the new ELF, and reset the target.
end

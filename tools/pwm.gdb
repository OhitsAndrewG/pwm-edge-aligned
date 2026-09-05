# GDB helpers for pwm_example
#   load with:   source tools/pwm.gdb
#
# --------------------------------------------------------------------------

# pos <microseconds>   set the servo pulse width
define pos
  set var TIM2->CCR2 = $arg0
  printf "CCR2 = %d us\n", TIM2->CCR2
end
document pos
Set servo pulse width in microseconds.  Usage: pos 1500
Safe range is roughly 1000-2000. Stop if the servo buzzes or strains.
end

# regs   dump every register this project configures
define regs
  printf "--- clocks ---\n"
  printf "  RCC->AHB1ENR  0x%08x   (bit0 GPIOAEN)\n", RCC->AHB1ENR
  printf "  RCC->APB1ENR  0x%08x   (bit0 TIM2EN)\n",  RCC->APB1ENR
  printf "--- pin PA1 ---\n"
  printf "  GPIOA->MODER  0x%08x   (expect 0xa8000008)\n", GPIOA->MODER
  printf "  GPIOA->AFR[0] 0x%08x   (expect 0x00000010)\n", GPIOA->AFR[0]
  printf "--- timer ---\n"
  printf "  TIM2->PSC     %d\n",                TIM2->PSC
  printf "  TIM2->ARR     %d       (expect 19999)\n", TIM2->ARR
  printf "  TIM2->CCMR1   0x%08x   (expect 0x6800)\n", TIM2->CCMR1
  printf "  TIM2->CCER    0x%08x   (bit4 CC2E)\n",     TIM2->CCER
  printf "  TIM2->CR1     0x%08x   (bit0 CEN)\n",      TIM2->CR1
  printf "  TIM2->CCR2    %d us\n",             TIM2->CCR2
  printf "  TIM2->CNT     %d\n",                TIM2->CNT
end
document regs
Dump every register pwm_example configures, with expected values.
end

# running   read CNT twice - different numbers mean the timer is alive
define running
  set $a = TIM2->CNT
  set $b = TIM2->CNT
  printf "CNT: %d then %d  ->  ", $a, $b
  if $a != $b
    printf "TIMER IS RUNNING\n"
  else
    printf "STOPPED (check CEN in CR1)\n"
  end
end
document running
Read TIM2->CNT twice and report whether the timer is counting.
end

# rf   rebuild, reflash, reset
define rf
  make
  load
  monitor reset
end
document rf
Rebuild, flash the new ELF, and reset the target.
end

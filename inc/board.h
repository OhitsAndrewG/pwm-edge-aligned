/*
 * board.h  -  WeAct Black Pill (STM32F411CEU6)
 *
 * The ONLY file that knows what hardware this is. Move the servo to a
 * different pin, or port to a different board, and this is the file you edit.
 *
 * ---------------------------------------------------------------------------
 * WHY PA1?  Every pin choice passes three filters, in order. Each layer can
 * only REMOVE options, never add them.
 *
 *   1. SILICON  - can the peripheral reach this pin at all?
 *                 (datasheet, "Alternate function mapping" table)
 *   2. PACKAGE  - is that pin bonded out on UFQFPN48?
 *                 (datasheet, "Pin definitions" table)
 *   3. BOARD    - has WeAct already claimed it?
 *                 (board schematic - and physically look at the board)
 *
 * TIM2's channels, filtered:
 *
 *   CH1  PA0    board: user button (KEY)          -> rejected at filter 3
 *   CH1  PA5    free, but shares the SPI1 flash footprint on the underside
 *   CH1  PA15   defaults to JTDI at reset         -> extra work to reclaim
 *   CH2  PA1    clean on all three filters        -> CHOSEN
 *   CH2  PB3    defaults to JTDO at reset
 *   CH3  PA2    free  (use for a second servo)
 *   CH4  PB11   NOT bonded out on UFQFPN48        -> rejected at filter 2
 *
 * Never repurpose PA13/PA14 - they are SWDIO/SWCLK. You would lose the debugger.
 * ---------------------------------------------------------------------------
 */
#ifndef BOARD_H
#define BOARD_H

#include "stm32f4xx.h"

/* --- the PWM output pin --------------------------------------------------- */
#define PWM_PORT            GPIOA
#define PWM_PIN             1u          /* PA1, physical pin 11              */
#define PWM_AF              1u          /* AF1 = TIM2 (see datasheet Table 9) */
#define PWM_PORT_RCC_BIT    0u          /* GPIOAEN in RCC->AHB1ENR           */

/* --- the timer ------------------------------------------------------------ */
#define PWM_TIM             TIM2
#define PWM_TIM_RCC_BIT     0u          /* TIM2EN in RCC->APB1ENR            */

/*
 * Timer input clock, in Hz.
 *
 * 16 MHz because this project deliberately runs on the HSI - the internal RC
 * oscillator the chip boots on. No PLL, no clock configuration.
 *
 * The cost is accuracy: HSI is spec'd around +/-1%. Measured on this board it
 * ran near 15.76 MHz, making absolute pulse widths ~1.5% long. See the README.
 *
 * If you configure HSE + PLL for 96 MHz, change ONLY this number. pwm.c
 * derives the prescaler from it, so nothing else moves.
 */
#define PWM_TIM_CLK_HZ      16000000u

#endif /* BOARD_H */

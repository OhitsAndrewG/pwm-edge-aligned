/*
 * pwm_example - STM32F411CEU6 (WeAct Black Pill)
 *
 * Servo PWM on PA1 = TIM2_CH2 (AF1), physical pin 11
 *
 *   timer clock 16 MHz (HSI, the default at reset - no PLL configured yet)
 *   PSC   15      -> divides by PSC+1 = 16  -> 1 tick = 1 us
 *   ARR   19999   -> counts ARR+1 = 20000 ticks -> 20 ms -> 50 Hz
 *   CCR2  1000..2000 = pulse width in microseconds (1500 = centre)
 *
 * ---------------------------------------------------------------------------
 * REGISTER ORDER  -  why each one sits where it does
 * ---------------------------------------------------------------------------
 *    #  register              hard rule?
 *   --  --------------------  ------------------------------------------------
 *    1  RCC->AHB1ENR   GPIOA  YES - must be first
 *    2  RCC->APB1ENR   TIM2   YES - writes to an unclocked peripheral are
 *                             silently discarded. No error, nothing happens.
 *    3  GPIOA->MODER          convention
 *    4  GPIOA->AFR[0]         convention
 *    5  TIM2->PSC             convention
 *    6  TIM2->ARR             convention
 *    7  TIM2->CCMR1           convention
 *    8  TIM2->CCR2            YES - before 9 and 11, or the first pulse is
 *                             0 us wide and some servos read that as a fault
 *    9  TIM2->CCER            convention
 *   10  TIM2->EGR    (UG)     YES - after 5 and 6, before 11. Copies PSC/ARR
 *                             out of their holding registers into the live ones
 *   11  TIM2->CR1    (CEN)    YES - must be LAST. Nothing should reach the pin
 *                             until every setting is in place
 *
 * Steps 3-7 and 9 can be reordered freely; they are just tidy grouping.
 *
 * The universal pattern, true for every STM32 peripheral (UART, SPI, I2C...):
 *      1. CLOCK ON      RCC->xxxENR
 *      2. CONFIGURE     everything, while the peripheral is still disabled
 *      3. ENABLE LAST   the "GO" bit
 * ---------------------------------------------------------------------------
 */

#include "stm32f4xx.h"

int main(void)
{
    /* =====================================================================
     * [1][2]  CLOCK ON  -  open the AND gates from the clock tree.
     *         Everything is gated OFF at reset.
     * ===================================================================== */
    RCC->AHB1ENR |= (1 << 0);   // GPIOAEN, bit 0 - GPIOA lives on AHB1
    RCC->APB1ENR |= (1 << 0);   // TIM2EN,  bit 0 - TIM2 lives on APB1


    /* =====================================================================
     * [3]  MODER  -  "what job does this pin have?"      RM0383 pg 158
     *
     *      2 bits per pin, so pin n uses bits [2n+1 : 2n]. Pin 1 -> bits 3:2.
     *        00 Input (reset state)   01 General purpose output
     *        10 Alternate function    11 Analog
     *
     *      Multi-bit field, so CLEAR then SET. (|= alone can only turn bits on.)
     * ===================================================================== */
    GPIOA->MODER &= ~(3 << 2);  // clear bits 3:2   (3 = 0b11, the field mask)
    GPIOA->MODER |=  (2 << 2);  // write 0b10 = alternate function mode


    /* =====================================================================
     * [4]  AFR  -  "WHICH peripheral drives it?"        RM0383 pg 162
     *
     *      MODER opened the door; AFR names who walks through.
     *      4 bits per pin, so pin n uses bits [4n+3 : 4n]. Pin 1 -> bits 7:4.
     *      AFR[0] = AFRL = pins 0-7.  AFR[1] = AFRH = pins 8-15.
     *      AF1 on PA1 = TIM2_CH2.
     * ===================================================================== */
    GPIOA->AFR[0] &= ~(15 << 4); // clear bits 7:4  (15 = 0b1111, field mask)
    GPIOA->AFR[0] |=  (1  << 4); // AF1 = TIM2 channel 2


    /* =====================================================================
     * [5][6]  TIMEBASE                                  RM0383 pg 350
     *
     *      PSC = how FAST the counter ticks. Divides by PSC+1.
     *            16 MHz / 16 = 1 MHz -> one tick per microsecond.
     *      ARR = how HIGH it counts before wrapping to 0. Counts ARR+1 ticks
     *            (the count includes 0), so 19999 gives 20000 us = 20 ms.
     *
     *      Both are plain numbers, not bitfields -> use '=', not '|='.
     * ===================================================================== */
    TIM2->PSC = 15;             // 1 tick = 1 us
    TIM2->ARR = 19999;          // 20 ms period = 50 Hz


    /* =====================================================================
     * [7]  CCMR1  -  "what does the output DO at the compare mark?"
     *
     *      Capture = channel used as an input.  Compare = used as an output.
     *      The '1' is a REGISTER index, not a channel: CCMR1 holds channels
     *      1 and 2 (low half / high half), CCMR2 holds channels 3 and 4.
     *
     *      OC2M[2:0] at bits 14:12 - 3 bits wide, so the mask is 0b111 = 7.
     *          110 = PWM mode 1: output HIGH while CNT < CCR, then LOW.
     *      OC2PE at bit 11 - preload. Without it, changing CCR2 mid-pulse
     *          cuts that pulse short and the servo twitches. With it, the new
     *          value is parked and swapped in at the next wrap. Double
     *          buffering, exactly like a graphics back buffer.
     * ===================================================================== */
    TIM2->CCMR1 &= ~(7 << 12);              // clear OC2M
    TIM2->CCMR1 |=  (6 << 12) | (1 << 11);  // OC2M=0b110 (PWM1), OC2PE=1
                                            // -> reads back as 0x6800


    /* =====================================================================
     * [8]  CCR2  -  the mark on the dial. Because 1 tick = 1 us, this IS
     *      the pulse width in microseconds.
     *          1000 = full left   1500 = centre   2000 = full right
     *      Stay inside 1000-2000 or the servo drives against its end stop.
     *
     *      Set BEFORE the output is enabled, so the very first pulse is valid.
     * ===================================================================== */
    TIM2->CCR2 = 1500;          // centre


    /* =====================================================================
     * [9]  CCER  -  the tap. An on/off switch connecting the channel to the
     *      physical pin. The timer runs either way; without this, nothing
     *      reaches PA1.
     *
     *      Both ends must agree:
     *          pin side   MODER + AFR   "PA1 accepts TIM2_CH2"
     *          timer side CC2E          "TIM2_CH2 is driving"
     *
     *      4 bits per channel: CC1E bit 0, CC2E bit 4, CC3E bit 8, CC4E bit 12.
     * ===================================================================== */
    TIM2->CCER |= (1 << 4);     // CC2E - enable channel 2 output


    /* =====================================================================
     * [10]  EGR / UG  -  force an update event.
     *
     *       PSC and ARR are shadowed: writes land in holding registers and
     *       only transfer to the live ones on an update event. At power-on no
     *       update has ever happened, so the live registers are still 0.
     *       Start the counter without this and the first period runs at ARR=0.
     * ===================================================================== */
    TIM2->EGR |= (1 << 0);      // UG - copy holding -> live


    /* =====================================================================
     * [11]  CR1 / CEN  -  GO. Must be last.
     * ===================================================================== */
    TIM2->CR1 |= (1 << 0);      // CEN - start the counter

    /* PWM is now running on PA1 with zero CPU involvement.
     *
     * Verify in gdb:
     *     p TIM2->CNT      twice - different numbers means it is counting
     *     p/x TIM2->CCMR1  should read 0x6800
     *     p TIM2->ARR      should read 19999 (0 means UG did not take)
     */


    /* TODO next: a delay function, then sweep CCR2 between 1000 and 2000 */
    while (1) {
        
    }
}

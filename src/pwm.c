/*
 * pwm.c  -  edge-aligned PWM, configured directly against the registers
 *
 * Reference: RM0383 (STM32F411xC/E), chapters 6 (RCC), 8 (GPIO), 13 (TIM2-5)
 *
 * ---------------------------------------------------------------------------
 * REGISTER ORDER  -  why each write sits where it does
 * ---------------------------------------------------------------------------
 *    #  register            hard rule?
 *   --  ------------------  -------------------------------------------------
 *    1  RCC->AHB1ENR        YES - must be first. Writes to an unclocked
 *    2  RCC->APB1ENR              peripheral are silently discarded: no error,
 *                                 no effect, nothing to debug.
 *    3  GPIOx->MODER        convention
 *    4  GPIOx->AFR[]        convention
 *    5  TIMx->PSC           convention
 *    6  TIMx->ARR           convention
 *    7  TIMx->CCMR1         convention
 *    8  TIMx->CCR2          YES - before 9 and 11, or the first pulse is 0 us
 *    9  TIMx->CCER          convention
 *   10  TIMx->EGR (UG)      YES - after 5 and 6, before 11. Copies PSC and ARR
 *                                 out of their shadow registers into the live
 *                                 ones. Skip it and the first period uses ARR=0.
 *   11  TIMx->CR1 (CEN)     YES - LAST. Nothing partial should reach the pin.
 *
 * The pattern generalises to every STM32 peripheral - UART, SPI, I2C, ADC:
 *
 *      CLOCK ON  ->  CONFIGURE  ->  ENABLE LAST
 *
 * ---------------------------------------------------------------------------
 * CHANNEL
 * ---------------------------------------------------------------------------
 * Hardcoded to channel 2, deliberately. Making the channel a parameter means
 * pointer arithmetic over CCR1..CCR4 and per-channel bit offsets - compact,
 * but far harder to check against the reference manual, which is the point of
 * this code. To use a different channel, change these four things:
 *
 *      CCR2      -> CCRn
 *      OC2M      bits 14:12 (ch2) -> bits 6:4 (ch1); ch3/ch4 live in CCMR2
 *      OC2PE     bit 11    (ch2) -> bit 3    (ch1)
 *      CC2E      bit 4     (ch2) -> bit 0/8/12 for ch1/3/4
 *
 * ...and pick a pin that carries that channel. See board.h.
 */

#include "pwm.h"
#include "board.h"

/* --- TIMx_CCMR1 output-compare fields, channel 2 -------------------------- */
#define OC2M_Pos            12u
#define OC2M_Msk            (7u << OC2M_Pos)   /* 3 bits wide -> mask 0b111   */
#define OC2M_PWM_MODE_1     (6u << OC2M_Pos)   /* 0b110: high while CNT < CCR */
#define OC2PE               (1u << 11)         /* preload enable              */

/* --- TIMx_CCER ------------------------------------------------------------ */
#define CC2E                (1u << 4)          /* connect channel 2 to the pin */

/* --- TIMx_SR -------------------------------------------------------------- */
#define UIF                 (1u << 0)          /* update interrupt flag        */

/* --- TIMx_EGR / TIMx_CR1 -------------------------------------------------- */
#define UG                  (1u << 0)          /* force an update event        */
#define CEN                 (1u << 0)          /* counter enable               */

/* --- GPIO field widths ---------------------------------------------------- */
#define MODER_BITS          2u
#define MODER_MSK           3u
#define MODER_ALTERNATE     2u                 /* 0b10                        */
#define AFR_BITS            4u
#define AFR_MSK             15u

/*
 * Prescaler for a 1 microsecond tick, derived rather than hardcoded.
 *
 * The hardware divides by PSC+1, hence the -1. That +1 exists so PSC=0 means
 * "do not divide" instead of being a division by zero.
 *
 *      16 MHz -> 15      96 MHz -> 95
 *
 * Change PWM_TIM_CLK_HZ in board.h and this follows automatically.
 */
#define PSC_FOR_1US         ((PWM_TIM_CLK_HZ / 1000000u) - 1u)

/*
 * Counter wraps after ARR+1 ticks - the count includes 0 - so subtract one.
 * 20000 us of 1 us ticks -> ARR = 19999.
 */
#define ARR_FOR_PERIOD      (PWM_PERIOD_US - 1u)


void pwm_init(uint16_t initial_us)
{
    if (initial_us >= PWM_PERIOD_US) {
        initial_us = PWM_PERIOD_US - 1u;
    }

    /* [1][2] CLOCK ON. Every peripheral is gated off at reset - these are the
     * AND gates drawn in the RM0383 clock tree. */
    RCC->AHB1ENR |= (1u << PWM_PORT_RCC_BIT);
    RCC->APB1ENR |= (1u << PWM_TIM_RCC_BIT);

    /* [3] MODER - "what job does this pin have?" 2 bits per pin, so pin n
     * occupies bits [2n+1:2n]. Multi-bit field: clear, then set. */
    PWM_PORT->MODER &= ~(MODER_MSK       << (PWM_PIN * MODER_BITS));
    PWM_PORT->MODER |=  (MODER_ALTERNATE << (PWM_PIN * MODER_BITS));

    /* [4] AFR - "WHICH peripheral drives it?" MODER opened the door; this
     * names who walks through. 4 bits per pin. AFR[0] covers pins 0-7,
     * AFR[1] covers 8-15, so index by pin/8 and shift by 4*(pin%8). */
    PWM_PORT->AFR[PWM_PIN / 8u] &= ~(AFR_MSK << ((PWM_PIN % 8u) * AFR_BITS));
    PWM_PORT->AFR[PWM_PIN / 8u] |=  (PWM_AF  << ((PWM_PIN % 8u) * AFR_BITS));

    /* [5][6] TIMEBASE. PSC sets how fast the counter ticks, ARR how far it
     * counts before wrapping. Plain values, not bitfields - so '='. */
    PWM_TIM->PSC = PSC_FOR_1US;
    PWM_TIM->ARR = ARR_FOR_PERIOD;

    /* [7] CCMR1 - what the output DOES at the compare point.
     * PWM mode 1: high from 0 until CNT reaches CCR, then low.
     * OC2PE (preload): a new CCR value is parked and swapped in at the next
     * wrap, so changing the width never cuts a pulse in half. Double
     * buffering, the same idea as a graphics back buffer. */
    PWM_TIM->CCMR1 &= ~OC2M_Msk;
    PWM_TIM->CCMR1 |=  OC2M_PWM_MODE_1 | OC2PE;

    /* [8] CCR2 - the compare point. With a 1 us tick this IS the pulse width
     * in microseconds. Set before the output is enabled (see pwm.h). */
    PWM_TIM->CCR2 = initial_us;

    /* [9] CCER - the tap. The timer counts either way; without this nothing
     * reaches the pin. Both ends must agree: MODER+AFR is the pin saying it
     * accepts the timer, CC2E is the timer saying it is driving. */
    PWM_TIM->CCER |= CC2E;

    /* [10] UG - PSC and ARR are shadowed. Writes land in holding registers and
     * transfer to the live ones only on an update event. At power-on none has
     * occurred, so force one by hand. */
    PWM_TIM->EGR |= UG;

    /* Generating that update event ALSO set UIF - an update by hand is still
     * an update. Clear it now, so the first pwm_wait_frames() call waits a
     * real frame instead of returning immediately on a stale flag. */
    PWM_TIM->SR = ~UIF;

    /* [11] CEN - GO. Last, so nothing partial ever appears on the pin. */
    PWM_TIM->CR1 |= CEN;
}


void pwm_set_us(uint16_t us)
{
    if (us >= PWM_PERIOD_US) {
        us = PWM_PERIOD_US - 1u;
    }
    /* Thanks to OC2PE this lands at the next frame boundary, not immediately.
     * From here on this single register write is the entire runtime cost of
     * PWM - the timer regenerates every pulse in hardware. */
    PWM_TIM->CCR2 = us;
}


uint16_t pwm_get_us(void)
{
    return (uint16_t)PWM_TIM->CCR2;
}


void pwm_wait_frames(uint16_t frames)
{
    while (frames--) {
        /* UIF is sticky: hardware sets it on every counter wrap and leaves it
         * set until software clears it. So wait for it, then clear it. */
        while ((PWM_TIM->SR & UIF) == 0u) {
            /* spin - one PWM period, 20 ms */
        }

        /* Timer status flags are rc_w0: writing 0 clears a bit, writing 1 does
         * nothing. So '= ~UIF' stores 0 to UIF and 1s everywhere else,
         * clearing exactly one flag in a single write.
         *
         * Deliberately NOT '&= ~UIF' - that is a read-modify-write, and a flag
         * the hardware sets between the read and the write would be lost. */
        PWM_TIM->SR = ~UIF;
    }
}

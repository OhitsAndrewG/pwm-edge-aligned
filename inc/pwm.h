/*
 * pwm.h  -  edge-aligned PWM on one timer channel
 *
 * Knows nothing about servos. It produces a pulse of a requested width at a
 * fixed frame rate; what that width MEANS is the caller's business.
 *
 * Which pin and which timer come from board.h.
 */
#ifndef PWM_H
#define PWM_H

#include <stdint.h>

/* Frame length. 20 ms / 50 Hz is the RC servo convention; change freely. */
#define PWM_PERIOD_US   20000u

/*
 * Configure the pin and timer, and start generating pulses.
 *
 * initial_us is the pulse width the FIRST pulse will have.
 *
 * It is a parameter rather than something you set afterwards on purpose: the
 * compare register must hold a valid value BEFORE the output is connected to
 * the pin, or the first pulse is 0 us wide. Some devices - servos among them -
 * treat a 0 us pulse as a fault. Making it an argument means a caller cannot
 * get that ordering wrong.
 *
 * Call once at startup.
 */
void pwm_init(uint16_t initial_us);

/*
 * Set the pulse width in microseconds.
 *
 * Takes effect at the start of the next frame, never mid-pulse - the timer's
 * preload register handles the swap. Values above PWM_PERIOD_US are clamped.
 */
void pwm_set_us(uint16_t us);

/* Current pulse width in microseconds. */
uint16_t pwm_get_us(void);

#endif /* PWM_H */

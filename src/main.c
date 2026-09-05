/*
 * pwm-edge-aligned  -  STM32F411CEU6 (WeAct Black Pill)
 *
 * Sweeps an RC servo back and forth using edge-aligned PWM generated entirely
 * in hardware. The CPU's only job is to write a new pulse width once per
 * frame; the timer regenerates every pulse on its own, even while the core is
 * halted at a breakpoint.
 *
 * Pin, timer and clock rate live in inc/board.h.
 * All register work lives in src/pwm.c.
 * This file knows only about servos.
 */

#include "pwm.h"

/*
 * RC servo pulse widths, in microseconds.
 *
 * These are the convention, not a guarantee - real servos vary. Find your own
 * limits by stepping outward from centre in 50 us increments (gdb: 'pos 1450')
 * and stopping the moment it buzzes or stops moving further. Driving into a
 * mechanical stop stalls the motor: heat, current draw, sometimes stripped
 * gears.
 */
#define SERVO_MIN_US        1000u
#define SERVO_CENTRE_US     1500u
#define SERVO_MAX_US        2000u

/*
 * Sweep shape.
 *
 * STEP_US       how far the commanded position moves each frame.
 * FRAMES_PER_STEP  how many 20 ms frames to hold before moving again.
 * PAUSE_FRAMES  hold at each end, so the servo can actually arrive - the
 *               command reaches the endpoint before the horn does.
 *
 * 10 us per frame over a 1000 us range = 100 steps = 2 seconds per direction.
 * Small steps matter: jumping straight from 1000 to 2000 makes the servo slam
 * across at full speed, which is loud, draws a lot of current, and looks bad.
 */
#define STEP_US             10u
#define FRAMES_PER_STEP     1u
#define PAUSE_FRAMES        25u     /* 25 x 20 ms = 500 ms */

int main(void)
{
    uint16_t us;

    pwm_init(SERVO_CENTRE_US);

    while (1) {
        for (us = SERVO_MIN_US; us <= SERVO_MAX_US; us += STEP_US) {
            pwm_set_us(us);
            pwm_wait_frames(FRAMES_PER_STEP);
        }
        pwm_wait_frames(PAUSE_FRAMES);

        for (us = SERVO_MAX_US; us >= SERVO_MIN_US; us -= STEP_US) {
            pwm_set_us(us);
            pwm_wait_frames(FRAMES_PER_STEP);
        }
        pwm_wait_frames(PAUSE_FRAMES);
    }
}

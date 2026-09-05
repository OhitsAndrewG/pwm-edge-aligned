/*
 * pwm-edge-aligned  -  STM32F411CEU6 (WeAct Black Pill)
 *
 * A worked example of hardware PWM, configured register by register.
 *
 * The point is not the application - it is that once the timer is configured,
 * PWM costs the CPU nothing. The counter, the comparator and the output are
 * all in silicon. The loop below writes one register per frame; the pulses
 * would keep coming even if it wrote nothing at all, and they keep coming
 * while the core is halted at a breakpoint.
 *
 * The numbers below (20 ms frame, 1000-2000 us pulse) are RC servo timing.
 * They were chosen because they are a real, published, externally verifiable
 * target - you can check the output against a specification rather than
 * against your own arithmetic. Any other PWM application is the same code
 * with different constants; see "Retargeting" in the README.
 *
 * Pin, timer and clock rate live in inc/board.h.
 * All register work lives in src/pwm.c.
 */

#include "pwm.h"

/*
 * Sweep endpoints, in microseconds of pulse width.
 *
 * These happen to be the RC servo convention: 1000 us = one extreme, 1500 =
 * centre, 2000 = the other. Real servos vary; if you have one connected, find
 * its actual limits by stepping outward from centre in 50 us increments
 * (gdb: 'pos 1450') and stopping the moment it buzzes or stops moving.
 * Driving into a mechanical stop stalls the motor - heat, current, sometimes
 * stripped gears.
 *
 * With nothing connected these are simply pulse widths on a pin, and a scope
 * shows the duty cycle walking from 5 % to 10 % at a fixed 50 Hz.
 */
#define SWEEP_MIN_US        1000u
#define SWEEP_CENTRE_US     1500u
#define SWEEP_MAX_US        2000u

/*
 * Sweep shape.
 *
 * 10 us per frame across a 1000 us range = 101 steps = ~2 s per direction.
 *
 * Stepping rather than jumping end to end is not just cosmetic: a step change
 * commands the fastest movement the actuator can manage, which is loud, draws
 * heavy current, and tells you nothing about the intermediate values. A ramp
 * makes the relationship between CCR and output visible.
 */
#define STEP_US             10u
#define FRAMES_PER_STEP     1u
#define PAUSE_FRAMES        25u     /* 25 x 20 ms = 500 ms */

int main(void)
{
    uint16_t us;

    pwm_init(SWEEP_CENTRE_US);

    while (1) {
        for (us = SWEEP_MIN_US; us <= SWEEP_MAX_US; us += STEP_US) {
            pwm_set_us(us);
            pwm_wait_frames(FRAMES_PER_STEP);
        }
        pwm_wait_frames(PAUSE_FRAMES);

        for (us = SWEEP_MAX_US; us >= SWEEP_MIN_US; us -= STEP_US) {
            pwm_set_us(us);
            pwm_wait_frames(FRAMES_PER_STEP);
        }
        pwm_wait_frames(PAUSE_FRAMES);
    }
}

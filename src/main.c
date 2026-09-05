/*
 * pwm-edge-aligned  -  STM32F411CEU6 (WeAct Black Pill)
 *
 * Holds an RC servo at centre using edge-aligned PWM generated entirely in
 * hardware. Once configured the CPU does nothing: the loop below is empty and
 * the pulses continue regardless - including while halted at a breakpoint.
 *
 * Pin, timer and clock rate live in inc/board.h.
 * All register work lives in src/pwm.c.
 * This file knows only about servos.
 */

#include "pwm.h"

/*
 * RC servo pulse widths, in microseconds.
 *
 * These are the convention, not a guarantee - real servos vary. Find your
 * own limits by stepping outward from centre in 50 us increments and stopping
 * the moment it buzzes or stops moving further. Driving into a mechanical
 * stop stalls the motor: heat, current draw, sometimes stripped gears.
 */
#define SERVO_MIN_US        1000u
#define SERVO_CENTRE_US     1500u
#define SERVO_MAX_US        2000u

int main(void)
{
    pwm_init(SERVO_CENTRE_US);

    while (1) {
        /* Nothing to do. The timer generates every pulse in hardware.
         *
         * To move the servo, call pwm_set_us(). With gdb attached you can do
         * it live, without changing this file:
         *
         *     (gdb) source tools/pwm.gdb
         *     (gdb) pos 1000
         *     (gdb) pos 2000
         */
    }
}

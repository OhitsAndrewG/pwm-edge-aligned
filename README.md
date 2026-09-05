# pwm-edge-aligned

Hardware PWM on an STM32F411, configured directly against the registers. No
HAL, no LL drivers, no CubeMX output.

## What it does

Outputs a 50 Hz signal on PA1. The pulse width sweeps from 1000 µs to 2000 µs
in 10 µs steps, pauses 500 ms, then sweeps back. One cycle takes about 5
seconds.

After configuration the timer runs without CPU involvement. The counter,
comparator and output are all in hardware. The loop writes one register per
frame. The pulses continue if it writes nothing, and continue while the core
is halted at a breakpoint.

The timing values (20 ms frame, 1000–2000 µs pulse) are the RC servo
convention. They are used here because they are published and externally
verifiable, so the output can be checked against a specification rather than
against the same arithmetic that produced it.

| Setting | Value | Meaning |
|---|---|---|
| Timer / channel | TIM2 CH2 | 32-bit general-purpose timer |
| Pin | PA1, physical pin 11, AF1 | |
| Timer clock | 16 MHz | HSI, the reset default. No PLL. |
| `PSC` | 15 | divides by `PSC+1` = 16, giving a 1 µs tick |
| `ARR` | 19999 | `ARR+1` = 20000 ticks = 20 ms = 50 Hz |
| `CCR2` | 1000–2000 | pulse width in microseconds |

`PSC` is chosen so one tick is one microsecond. `CCR2` is therefore the pulse
width in microseconds directly, with no conversion.

The full derivation is in
[`reference_documents/pwm-math.png`](reference_documents/pwm-math.png).

## Hardware

| Item | Notes |
|---|---|
| WeAct Black Pill, STM32F411CEU6 | Cortex-M4F, 512 KB flash, 128 KB RAM, UFQFPN48. The Black Pill is an F4. The Blue Pill is an F103. Read the chip marking. |
| SEGGER J-Link | SWD probe. Used for flashing and register inspection. |
| PicoScope 2204A | 2 channels, 10 MHz, 100 MS/s. Used to verify the output. |
| Breadboard, jumpers | |
| RC servo (optional) | Not required. The signal can be verified on a scope alone. |

### Wiring

```
   J-Link  VTref ──── 3V3
           SWDIO ──── PA13
           SWCLK ──── PA14
           GND   ──── GND

   Servo   signal ─── PA1  (pin 11)
           +5V    ─── external 5 V supply
           GND    ─── supply GND and board GND
```

VTref senses the target voltage. It does not supply power. Connect the Black
Pill's USB for power and the J-Link for debug at the same time.

Do not power a servo from the Black Pill. A 9 g servo draws around an amp when
stalled and will brown out the board.

## Toolchain

| | |
|---|---|
| Compiler | `arm-none-eabi-gcc`, Arm GNU Toolchain 15.2 |
| Debugger | `arm-none-eabi-gdb` with `JLinkGDBServer` |
| Flashing | `JLinkExe`, driven by [`tools/flash.jlink`](tools/flash.jlink) |
| Headers | CMSIS core and device only, 8 files, vendored under `vendor/` |

```bash
make            # build -> build/pwm.bin
make flash      # build and write to the chip
make gdbserver  # GDB server on :2331
make clean
```

Every flag in the Makefile has a comment explaining what it does.

### Debugging

```bash
make gdbserver                                              # terminal 1
arm-none-eabi-gdb build/pwm.elf -ex "target remote :2331"   # terminal 2
```

Then:

```
source tools/pwm.gdb
regs        # dump every configured register with expected values
running     # check whether the counter is advancing
pos 1200    # set pulse width in µs
rf          # rebuild, flash, reset
```

`pos` works while the core is halted. The timer keeps running, so the pulse
width changes on the scope with the processor stopped.

The helpers use raw addresses rather than the CMSIS macros. Those macros only
resolve in files that include `stm32f4xx.h`, which `main.c` does not.

## Project layout

```
pwm-edge-aligned/
├── LICENSE                     MIT. CMSIS is Apache-2.0.
├── Makefile
├── linker/
│   └── STM32F411CEUx_FLASH.ld  512K flash @ 0x08000000, 128K RAM @ 0x20000000
├── startup/
│   └── startup_stm32f411xe.s   vector table, .data/.bss init, calls SystemInit
├── vendor/cmsis/
│   ├── core/                   core_cm4.h and its four dependencies
│   └── device/                 stm32f4xx.h, stm32f411xe.h, system_stm32f4xx.h
├── inc/
│   ├── board.h                 pin, timer and clock rate
│   └── pwm.h                   driver interface
├── src/
│   ├── main.c                  application
│   ├── pwm.c                   register configuration
│   └── system_stm32f4xx.c      ST template, defines SystemInit()
├── tools/
│   ├── flash.jlink
│   └── pwm.gdb
└── reference_documents/
    ├── pwm-math.png/.svg       timing derivation
    ├── BARE-METAL-PROJECT-FILES.txt
    ├── pwm_notes.txt
    ├── datasheets/             not committed, see its README
    └── screenshots/
```

`system_stm32f4xx.c` is ST's code but sits in `src/` because ST ships it under
`Source/Templates/`. It is a file you are expected to edit. Headers under
`vendor/` are consumed unchanged.

## Scope

This runs on the HSI, the internal RC oscillator the chip boots on. There is no
PLL and no clock configuration. That keeps the example to 11 register writes.

The cost is accuracy. HSI is specified at around ±1 %. On this board it ran near
15.76 MHz, which makes absolute pulse widths about 1.5 % long. The measurements
below show the effect.

To fix it, configure HSE and the PLL for 96 MHz and change `PWM_TIM_CLK_HZ` in
[`inc/board.h`](inc/board.h). `pwm.c` derives the prescaler from that value, so
`PSC` becomes 95 automatically and nothing else changes.

## Using this in another project

Three files, three kinds of knowledge:

| If you change | You edit |
|---|---|
| the output pin | `inc/board.h` |
| what the program does | `src/main.c` |
| the STM32 family | `src/pwm.c` |
| the clock source | `inc/board.h`, one number |

Copy `inc/board.h`, `inc/pwm.h` and `src/pwm.c`, edit the defines in `board.h`,
then:

```c
pwm_init(1500);          /* configure and start, first pulse 1500 µs */
pwm_set_us(2000);        /* new width, applied at the next frame boundary */
pwm_wait_frames(25);     /* block for 25 frames = 500 ms */
```

`pwm.c` has no knowledge of servos. It emits a pulse of the requested width at
a fixed frame rate.

`pwm_init()` takes the initial width as an argument because the compare
register must hold a valid value before the output is connected to the pin.
Otherwise the first pulse is 0 µs wide, which some devices treat as a fault.

`pwm_wait_frames()` blocks on the timer's `UIF` flag, which hardware sets once
per period. It stays accurate regardless of CPU clock, compiler or optimisation
level. A calibrated busy-loop does not.

## Register order

| # | Register | Fixed position? |
|---|---|---|
| 1–2 | `RCC->AHB1ENR`, `RCC->APB1ENR` | Yes. Writes to an unclocked peripheral are discarded silently. |
| 3–4 | `GPIOA->MODER`, `GPIOA->AFR[0]` | No |
| 5–7 | `TIM2->PSC`, `ARR`, `CCMR1` | No |
| 8 | `TIM2->CCR2` | Yes. Before the output is enabled. |
| 9 | `TIM2->CCER` | No |
| 10 | `TIM2->EGR` (`UG`) | Yes. Loads `PSC` and `ARR` from their shadow registers. |
| 11 | `TIM2->CR1` (`CEN`) | Yes. Last. |

The same pattern applies to every STM32 peripheral: enable the clock,
configure, then enable the peripheral last.

## Measured results

Captured on a PicoScope 2204A at PA1. Values set from GDB with `pos <us>`.
Screenshots are in `reference_documents/screenshots/`.

| `CCR2` | Nominal | Measured | Duty expected | Duty measured |
|---|---|---|---|---|
| 1000 | 1.000 ms | 1.024 ms | 5.00 % | 5.04 % |
| 1500 | 1.500 ms | 1.516 ms | 7.50 % | 7.48 % |
| 2000 | 2.000 ms | 2.021 ms | 10.00 % | 9.97 % |
| 3000 | 3.000 ms | 3.045 ms | 15.00 % | 15.01 % |

Cycle time stayed between 20.28 and 20.30 ms (49.27–49.32 Hz) in all four
cases. The period does not depend on `CCR2`.

The 3000 µs point is outside the RC servo range and was captured with the scope
only. It shows the relationship stays linear past that range.

### Duty cycle is accurate, absolute time is not

Absolute pulse widths are consistently 1.0–1.5 % long. Duty cycle matches the
intended value to within 0.04 %.

Duty cycle is a ratio:

```
duty = t_high / T_period = CCR2 / (ARR + 1)
```

The pulse and the period are counted in the same ticks. If a tick is 1.5 % too
long, both stretch by 1.5 % and the error cancels.

This matters for devices that read absolute pulse width, such as RC servos. It
does not matter for LED dimming or motor drive, where only the ratio is used.

### Cause

The systematic offset comes from the clock source. The HSI ran near 15.76 MHz
instead of 16.00 MHz, so each 1 µs tick was about 1.015 µs.

```
20.28 ms measured / 20.00 ms expected = 1.014
```

The arithmetic is correct. Only the clock source carries error. HSE with the
PLL is specified at ±20 ppm and would remove it.

## Not done

- [ ] Drive the sweep from the timer interrupt instead of blocking in
      `pwm_wait_frames()`, so the CPU is free for other work
- [ ] Photograph the wired-up board

HSE and PLL configuration is out of scope. See [Scope](#scope).

## Resources

Three documents, each answering a different question.

| Document | Answers |
|---|---|
| [RM0383 Reference Manual](https://www.st.com/resource/en/reference_manual/rm0383-stm32f411xce-advanced-armbased-32bit-mcus-stmicroelectronics.pdf) | What bits to write. RCC, GPIO and TIM chapters. |
| [STM32F411xC/E Datasheet](https://www.st.com/resource/en/datasheet/stm32f411ce.pdf) | Which pin can carry a given function, and which pins exist on this package. |
| [WeAct Black Pill schematic](https://github.com/WeActStudio/WeActStudio.MiniSTM32F4x1) | Whether the board already uses that pin. |

Choosing a pin means passing three filters in order. Each one removes options.

1. Silicon: can the peripheral reach this pin. Datasheet, alternate function
   mapping table.
2. Package: is that pin bonded out on UFQFPN48. Datasheet, pin definitions
   table.
3. Board: has the board vendor already used it. Schematic, and inspect the
   board.

PA0 is TIM2_CH1 and passes filters 1 and 2, but WeAct wired it to the user
button, so it fails filter 3. PB11 is TIM2_CH4 but is not bonded out on the
48-pin package, so it fails filter 2.

### Vendored headers

- [STMicroelectronics/cmsis_device_f4](https://github.com/STMicroelectronics/cmsis_device_f4)
- [ARM-software/CMSIS_5](https://github.com/ARM-software/CMSIS_5)

Both are also included in the STM32CubeF4 package under `Drivers/CMSIS/`.

### Tools

- [Arm GNU Toolchain](https://developer.arm.com/downloads/-/arm-gnu-toolchain-downloads)
- [SEGGER J-Link software](https://www.segger.com/downloads/jlink/)
- [PicoScope software](https://www.picotech.com/downloads)
- [STM32CubeMX](https://www.st.com/en/development-tools/stm32cubemx.html), useful
  for its interactive clock tree view even if you generate no code with it

## Licence

MIT for this project's code. See [`LICENSE`](LICENSE).

CMSIS headers under `vendor/cmsis/` are Apache-2.0. See
[`vendor/cmsis/LICENSE.txt`](vendor/cmsis/LICENSE.txt).

ST's reference manual and datasheet are not redistributed here. Download links
are in
[`reference_documents/datasheets/README.md`](reference_documents/datasheets/README.md).

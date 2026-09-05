# pwm-edge-aligned

**A bare-metal reference for generating edge-aligned PWM on an STM32.**

Configured as **PWM mode 1, edge-aligned** — the counter only counts up, so
every pulse begins at the same instant and only the falling edge moves. Used
here to produce an **RC servo pulse**: a 20 ms frame with a 1–2 ms high time.

> Strictly, a servo reads the *absolute pulse width*, not the duty ratio — so
> it is a pulse-width-encoded signal rather than PWM in the dimmer/motor sense.
> The [measurements below](#the-interesting-result-duty-is-exact-absolute-time-is-not)
> show why that distinction has real consequences.

Built to be copied. The goal was not to drive a servo — it was to have a
known-good, fully commented starting point for *any* future project that
needs PWM, written directly against the hardware registers with no HAL, no
LL drivers, and no CubeMX-generated code.

Every register write in [`src/main.c`](src/main.c) carries a comment saying
what it does and **why it sits where it does in the sequence**.

---

## What it does

Generates a 50 Hz PWM signal on **PA1** with a pulse width of 1500 µs —
standard hobby-servo centre position.

| Setting | Value | Meaning |
|---|---|---|
| Timer / channel | TIM2 CH2 | 32-bit general-purpose timer |
| Pin | **PA1** (physical pin 11), AF1 | |
| Timer clock | 16 MHz | HSI, the reset default — no PLL configured |
| `PSC` | 15 | divides by `PSC+1` = 16 → **1 tick = 1 µs** |
| `ARR` | 19999 | `ARR+1` = 20 000 ticks → **20 ms → 50 Hz** |
| `CCR2` | 1500 | **pulse width in microseconds** |

Because `PSC` was chosen to make one tick equal exactly one microsecond,
`CCR2` *is* the pulse width in µs. No conversion arithmetic anywhere.

Once configured, the timer runs entirely in hardware. The `while(1)` loop is
empty and the CPU does nothing — PWM continues even while halted at a GDB
breakpoint.

See [`reference_documents/pwm-math.png`](reference_documents/pwm-math.png)
for the full derivation.

---

## Hardware used

| Tool | What it is | Role here |
|---|---|---|
| **WeAct Black Pill** — STM32F411CEU6 | Cortex-M4F, 100 MHz max, 512 KB flash, 128 KB RAM, UFQFPN48 package | The target. Note: "Black Pill" is an **F4**; the "Blue Pill" is an F103. Always read the chip marking, not the nickname |
| **Breadboard + jumpers** | — | Servo signal from PA1, and a separate 5 V rail for the servo |
| **SEGGER J-Link** | SWD debug probe | Flashing and live register inspection. Needs `VTref`, `SWDIO`→PA13, `SWCLK`→PA14, `GND` |
| **PicoScope 2204A** (2000 series) | 2-channel USB scope, 10 MHz / 100 MS/s | Verifying the waveform is *actually* what the registers claim. This is the tool that caught the HSI clock error |
| **Hobby servo** | — | 50 Hz frame, 1–2 ms pulse. Powered from its **own** supply, grounds tied |

### Wiring

```
   J-Link  VTref ──── 3V3        (sense only — does NOT power the board)
           SWDIO ──── PA13
           SWCLK ──── PA14
           GND   ──── GND

   Servo   signal ─── PA1  (pin 11)
           +5V    ─── external 5 V supply
           GND    ─── supply GND  AND  board GND
```

> **Do not power the servo from the Black Pill.** Even a 9 g servo pulls
> around an amp when it stalls and will brown out the board.

---

## Toolchain

Everything is command-line. No IDE.

| | |
|---|---|
| Compiler | `arm-none-eabi-gcc` (Arm GNU Toolchain 15.2) |
| Debugger | `arm-none-eabi-gdb` + `JLinkGDBServer` |
| Flashing | `JLinkExe` via [`tools/flash.jlink`](tools/flash.jlink) |
| Headers | CMSIS only — core + device, 8 files, vendored in `vendor/` |

```bash
make          # build  -> build/pwm.bin
make flash    # build + write to the chip via J-Link
make gdbserver # start a GDB server on :2331
make clean
```

Debugging:

```bash
make gdbserver                                    # terminal 1
arm-none-eabi-gdb build/pwm.elf -ex "target remote :2331"   # terminal 2
```

Then in GDB:

```
source tools/pwm.gdb
regs        # dump every configured register with expected values
running     # is the timer actually counting?
pos 1200    # set pulse width in µs, live
rf          # rebuild + flash + reset
```

`pos` works while the CPU is **halted** — the timer keeps running, so you can
watch the pulse width change on a scope with the processor stopped. That is
the clearest demonstration that PWM is hardware, not code.

---

## Project layout

```
pwm_example/
├── LICENSE                     MIT (your code) — CMSIS is Apache-2.0
├── Makefile                    every flag commented — see it for what -mthumb,
│                               --specs=, --gc-sections etc. actually do
├── linker/
│   └── STM32F411CEUx_FLASH.ld  512K flash @ 0x08000000, 128K RAM @ 0x20000000
├── startup/
│   └── startup_stm32f411xe.s   vector table, .data/.bss init, calls SystemInit
├── vendor/cmsis/               code NOT written here
│   ├── core/                   core_cm4.h + its 4 dependencies
│   └── device/                 stm32f4xx.h, stm32f411xe.h, system_stm32f4xx.h
├── src/
│   ├── main.c                  ← the actual PWM configuration
│   └── system_stm32f4xx.c      ST template: defines SystemInit()
├── inc/                        (empty — for the pwm.c/board.h refactor)
├── tools/
│   ├── flash.jlink             J-Link Commander script
│   └── pwm.gdb                 GDB helper commands
└── reference_documents/
    ├── pwm-math.png/.svg       full derivation of the timing math
    ├── BARE-METAL-PROJECT-FILES.txt   what files any bare-metal project needs
    ├── pwm_notes.txt           working notes
    ├── datasheets/             NOT committed — see its README for links
    └── screenshots/
        ├── scope-ccr2-{1000,1500,2000,3000}.png   measured waveforms
        ├── rm0383-fig12-clock-tree.png
        └── ds-fig3-block-diagram.png
```

**Why `system_stm32f4xx.c` is in `src/` despite being ST's code:** it ships
under `Source/Templates/`, meaning it is a starting point you are expected to
edit. The test is *"will I ever change this file?"* — if yes, it is yours.

---

## The register order (and why it matters)

| # | Register | Hard rule? |
|---|---|---|
| 1–2 | `RCC->AHB1ENR`, `RCC->APB1ENR` | **yes** — writes to an unclocked peripheral are silently discarded |
| 3–4 | `GPIOA->MODER`, `GPIOA->AFR[0]` | convention |
| 5–7 | `TIM2->PSC`, `ARR`, `CCMR1` | convention |
| 8 | `TIM2->CCR2` | **yes** — before the output is enabled, or the first pulse is 0 µs |
| 9 | `TIM2->CCER` | convention |
| 10 | `TIM2->EGR` (`UG`) | **yes** — loads `PSC`/`ARR` out of their shadow registers |
| 11 | `TIM2->CR1` (`CEN`) | **yes** — last, so nothing partial reaches the pin |

The general pattern, true for every STM32 peripheral:

> **CLOCK ON → CONFIGURE → ENABLE LAST**

---

## Measured results

Captured with the PicoScope 2204A on PA1, values set live from GDB with
`pos <us>`. Full screenshots in `reference_documents/screenshots/`.

| `CCR2` | Nominal | **Measured pulse** | Ratio | Duty expected | **Duty measured** | Capture |
|---|---|---|---|---|---|---|
| 1000 | 1.000 ms | **1.024 ms** | 1.0240 | 5.00 % | **5.04 %** | [scope-ccr2-1000.png](reference_documents/screenshots/scope-ccr2-1000.png) |
| 1500 | 1.500 ms | **1.516 ms** | 1.0107 | 7.50 % | **7.48 %** | [scope-ccr2-1500.png](reference_documents/screenshots/scope-ccr2-1500.png) |
| 2000 | 2.000 ms | **2.021 ms** | 1.0105 | 10.00 % | **9.97 %** | [scope-ccr2-2000.png](reference_documents/screenshots/scope-ccr2-2000.png) |
| 3000 | 3.000 ms | **3.045 ms** | 1.0150 | 15.00 % | **15.01 %** | [scope-ccr2-3000.png](reference_documents/screenshots/scope-ccr2-3000.png) |

Cycle time held at **20.28–20.30 ms** (49.27–49.32 Hz) across all four — the
period is completely independent of `CCR2`, exactly as PWM requires.

The 3000 point is outside the servo's usable range and was captured with the
scope only. It is there to show the relationship stays **linear** well beyond
1000–2000: the timer does not know or care what a servo is.

### The interesting result: duty is exact, absolute time is not

Look at the two right-hand columns against the two left-hand ones.

- **Absolute pulse width** is consistently ~1.0–1.5 % long
- **Duty cycle** matches the intended value to within 0.04 %

That is not a coincidence. Duty cycle is a *ratio*:

```
    duty = t_high / T_period = CCR2 / (ARR + 1)
```

Both the pulse and the period are generated by counting the same ticks, so if
the tick is 1.5 % too long, both stretch by 1.5 % and **the error cancels in
the ratio**. The counter is doing exactly what it was told; only the wall-clock
meaning of a "tick" is off.

**Which is why this matters for a servo specifically.** A servo does not
measure duty cycle — it measures the *absolute* high time and compares it
against an internal reference. So it sees the full 1.5 % error, roughly 4° of
position. An LED dimmer or a motor driver, which only cares about the ratio,
would not be affected at all by this clock error.

### Root cause: the HSI

The systematic offset traces back to the clock source. The internal RC
oscillator is spec'd around ±1 % and was running near **15.76 MHz** instead of
16.00 MHz, making each "1 µs" tick actually ~1.015 µs.

```
    20.28 ms measured / 20.00 ms expected = 1.014
```

The arithmetic was never wrong. **Only the clock source carried error.**
Switching to the 25 MHz crystal and PLL (±20 ppm) removes it entirely.

That is the whole argument for an external crystal — measured on a bench
rather than taken on faith.

## Not done yet

- [ ] **HSE + PLL** — 96 MHz from the 25 MHz crystal, fixing the 1.5 % error
      (96 MHz needs `PSC = 95`; note 100 MHz and working USB are mutually
      exclusive with a 25 MHz crystal, since no integer `Q` gives 48 MHz)
- [ ] **A delay function** — SysTick, so the board can sweep on its own
- [ ] **Sweep loop** — move `CCR2` between endpoints
- [ ] **Refactor** into `inc/board.h` (pin choices) + `src/pwm.c` (the driver)
      + `main.c` (application), so porting touches one file

---

## Resources

### Documents — you need all three, they answer different questions

| Document | Answers |
|---|---|
| [RM0383 — Reference Manual](https://www.st.com/resource/en/reference_manual/rm0383-stm32f411xce-advanced-armbased-32bit-mcus-stmicroelectronics.pdf) | *"What bits do I write?"* — RCC, GPIO, TIM chapters. Local copy in `reference_documents/datasheets/` |
| [STM32F411xC/E Datasheet](https://www.st.com/resource/en/datasheet/stm32f411ce.pdf) | *"Which pin can do this?"* — the alternate-function mapping table and the per-package pin list |
| [WeAct Black Pill schematic](https://github.com/WeActStudio/WeActStudio.MiniSTM32F4x1) | *"Is that pin already used?"* — the one people forget |

**The three-filter rule for choosing any pin:**

1. **Silicon** — can this peripheral reach this pin at all? *(datasheet, AF table)*
2. **Package** — is that pin bonded out on UFQFPN48? *(datasheet, pin definitions)*
3. **Board** — has WeAct already claimed it? *(schematic, and look at the board)*

Each layer only removes options. `PA0` is `TIM2_CH1` and passes filters 1 and
2 — but it is wired to the user button, so it fails filter 3. `PB11` is a real
`TIM2_CH4` but is not bonded out on the 48-pin package, so it fails filter 2.

### Source of the vendored headers

- [STMicroelectronics/cmsis_device_f4](https://github.com/STMicroelectronics/cmsis_device_f4) — device headers and startup files
- [ARM-software/CMSIS_5](https://github.com/ARM-software/CMSIS_5) — `core_cm4.h` and friends

Both also ship inside the STM32CubeF4 package under `Drivers/CMSIS/`.

### Tools

- [Arm GNU Toolchain](https://developer.arm.com/downloads/-/arm-gnu-toolchain-downloads)
- [SEGGER J-Link software](https://www.segger.com/downloads/jlink/)
- [PicoScope software](https://www.picotech.com/downloads)
- [STM32CubeMX](https://www.st.com/en/development-tools/stm32cubemx.html) — worth
  installing *just* for its interactive clock-tree view, even if you never
  generate a line of code with it

---

## Licence

This project's own code is **MIT** — see [`LICENSE`](LICENSE).

Vendored CMSIS headers under `vendor/cmsis/` are **Apache-2.0** (ARM and
STMicroelectronics) — see [`vendor/cmsis/LICENSE.txt`](vendor/cmsis/LICENSE.txt).

The ST reference manual and datasheet are **not redistributed here**. Download
links are in [`reference_documents/datasheets/README.md`](reference_documents/datasheets/README.md).

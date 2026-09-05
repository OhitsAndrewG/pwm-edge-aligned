# Datasheets

These PDFs are **not committed** — they are ~16 MB, freely available from ST,
and never change (a revision gets a new document). Download them here:

| File | Document | Link |
|---|---|---|
| `rm0383-stm32f411xce-advanced-armbased-32bit-mcus-stmicroelectronics.pdf` | **RM0383** — Reference Manual. Registers: RCC, GPIO, TIM | https://www.st.com/resource/en/reference_manual/rm0383-stm32f411xce-advanced-armbased-32bit-mcus-stmicroelectronics.pdf |
| `stm32f411ce.pdf` | **STM32F411xC/E Datasheet**. Pinout, alternate-function mapping, per-package pin list | https://www.st.com/resource/en/datasheet/stm32f411ce.pdf |

You need **both**. The reference manual tells you *what bits to write*; the
datasheet tells you *which pin can do it*. Neither answers the other's question.

A third source, not a PDF: the **WeAct Black Pill schematic**, for whether a pin
is already used on this particular board —
https://github.com/WeActStudio/WeActStudio.MiniSTM32F4x1

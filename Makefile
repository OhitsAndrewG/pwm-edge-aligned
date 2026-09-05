# =============================================================================
#  pwm_example - bare-metal STM32F411CEU6 (WeAct Black Pill)
#
#  make          build everything -> build/pwm.bin
#  make flash    build, then write it to the chip
#  make clean    delete build/
# =============================================================================

TARGET := pwm
BUILD  := build


# --- TOOLCHAIN ---------------------------------------------------------------
# One prefix, four tools. "arm-none-eabi" means:
#   arm    - target CPU architecture
#   none   - no operating system (bare metal!)
#   eabi   - Embedded Application Binary Interface (the calling convention)
PREFIX  := arm-none-eabi-
CC      := $(PREFIX)gcc
OBJCOPY := $(PREFIX)objcopy
SIZE    := $(PREFIX)size

# --- DEBUG PROBE (SEGGER J-Link) ---
# The device name must match SEGGER's list exactly - it selects the
# correct flash programming algorithm for this chip.
JLINK        := JLinkExe
JLINK_DEVICE := STM32F411CE


# --- SOURCES -----------------------------------------------------------------
# Listed explicitly rather than globbed, so adding a file is a deliberate act.
C_SRCS   := src/main.c src/system_stm32f4xx.c
ASM_SRCS := startup/startup_stm32f411xe.s
LDSCRIPT := linker/STM32F411CEUx_FLASH.ld


# --- INCLUDE PATHS -----------------------------------------------------------
# -I tells the preprocessor where to look for #include "..." files.
# CMSIS headers only. No HAL, no LL, no CubeMX output.
INCLUDES := -Iinc -Ivendor/cmsis/device -Ivendor/cmsis/core


# --- DEFINES -----------------------------------------------------------------
# -D defines a macro, exactly as if you wrote #define at the top of every file.
# stm32f4xx.h is a switchboard of #ifdefs; this is what selects our chip's
# register map. Without it you get a wall of "unknown type name" errors.
DEFS := -DSTM32F411xE


# --- CPU FLAGS ---------------------------------------------------------------
# These four MUST match your chip, and MUST be identical when compiling and
# when linking. Mismatch = cryptic linker errors about incompatible objects.
#
#   -mcpu=cortex-m4        which ARM core -> picks the instruction set
#   -mthumb                use the Thumb-2 instruction set (16/32-bit mixed).
#                          Cortex-M ONLY runs Thumb. Never omit this.
#   -mfpu=fpv4-sp-d16      the F411 has a single-precision hardware FPU
#                          (sp = single precision, d16 = 16 double registers)
#   -mfloat-abi=hard       pass floats in FPU registers, not integer registers.
#                          Faster, but requires SystemInit() to enable CP10/CP11
#                          or the first float instruction faults.
CPU := -mcpu=cortex-m4 -mthumb -mfpu=fpv4-sp-d16 -mfloat-abi=hard


# --- OPTIMISATION ------------------------------------------------------------
#   -Og          optimise for DEBUGGING. Faster than -O0, but the debugger
#                still shows sane line numbers and variables. Use while learning.
#   -g3          maximum debug info (g3 also keeps #define macros)
#   -gdwarf-4    debug format that current arm-none-eabi-gdb reads best
OPT := -Og -g3 -gdwarf-4


# --- C COMPILER FLAGS --------------------------------------------------------
#   -std=c11               use the C11 language standard
#
#   WARNINGS (each one has caught a real bug for somebody):
#   -Wall -Wextra          the standard useful warning set
#   -Wshadow               warn when a local variable hides an outer one
#   -Wundef                warn on #if of an undefined macro (catches typos in
#                          names like STM32F411xE)
#   -Wdouble-promotion     warn when a float is silently promoted to double.
#                          Critical on M4F: the FPU is single-precision only,
#                          so a stray double drops you into slow software math.
#
#   SIZE (these two work together with --gc-sections at link time):
#   -ffunction-sections    put each function in its own linker section
#   -fdata-sections        put each variable in its own linker section
#                          ...so the linker can then delete the unused ones.
#
#   -fno-common            make duplicate globals a link ERROR instead of
#                          silently merging them into one variable.
#
#   DEPENDENCY TRACKING:
#   -MMD                   write a .d file listing every header this .c used
#   -MP                    add dummy targets so deleting a header doesn't
#                          break the build with "no rule to make target"
#                          (see the -include at the bottom of this file)
CFLAGS := $(CPU) $(DEFS) $(INCLUDES) $(OPT) -std=c11 \
          -Wall -Wextra -Wshadow -Wundef -Wdouble-promotion \
          -ffunction-sections -fdata-sections -fno-common \
          -MMD -MP


# --- ASSEMBLER FLAGS ---------------------------------------------------------
#   -x assembler-with-cpp  run the C preprocessor over the .s file first,
#                          so it can use #define / #ifdef / C-style comments
ASFLAGS := $(CPU) $(OPT) -x assembler-with-cpp -MMD -MP


# --- LINKER FLAGS ------------------------------------------------------------
#   $(CPU)                 yes, again. The linker uses these to pick the
#                          correct pre-built libraries (multilib).
#   -T$(LDSCRIPT)          use OUR linker script, not the toolchain default.
#                          This is what puts code at 0x08000000.
#   --specs=nano.specs     link the small newlib-nano C library
#   --specs=nosys.specs    provide empty stubs for OS calls (_write, _sbrk...).
#                          Bare metal has no OS, but the library still
#                          references them, so they must resolve to something.
#   -Wl,--gc-sections      garbage-collect unused sections. This is the half
#                          that actually deletes what -ffunction-sections split.
#   -Wl,-Map=...           write a map file: exactly what ended up where, and
#                          how big everything is. Invaluable when debugging.
#
#   NOTE: -Wl, means "pass this option through to the linker, not gcc".
LDFLAGS := $(CPU) -T$(LDSCRIPT) \
           --specs=nano.specs --specs=nosys.specs \
           -Wl,--gc-sections -Wl,--no-warn-rwx-segments -Wl,-Map=$(BUILD)/$(TARGET).map


# --- OBJECT FILES ------------------------------------------------------------
# Turn   src/main.c   into   build/src/main.o
# The syntax $(VAR:pattern=replacement) is a substitution reference.
OBJS := $(C_SRCS:%.c=$(BUILD)/%.o) $(ASM_SRCS:%.s=$(BUILD)/%.o)

# Every .o has a matching .d written by -MMD. Same names, different extension.
DEPS := $(OBJS:.o=.d)


# =============================================================================
#  RULES
#
#  Shape of a rule:      target: prerequisites
#                        <TAB>recipe
#
#  Automatic variables:  $@ = the target
#                        $< = the FIRST prerequisite
#                        $^ = ALL prerequisites
# =============================================================================

# The first rule in the file is the default one, so `make` alone runs this.
all: $(BUILD)/$(TARGET).bin

# --- compile: .c -> .o ---
# mkdir -p because build/src/ does not exist yet. The @ hides the command
# itself from the output (you still see errors).
$(BUILD)/%.o: %.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

# --- assemble: .s -> .o ---
$(BUILD)/%.o: %.s
	@mkdir -p $(dir $@)
	$(CC) $(ASFLAGS) -c $< -o $@

# --- link: all .o -> .elf ---
# The ELF holds your code PLUS debug symbols and section info. This is what
# you give to gdb. $(SIZE) then prints how much flash and RAM you used.
$(BUILD)/$(TARGET).elf: $(OBJS)
	$(CC) $(OBJS) $(LDFLAGS) -o $@
	$(SIZE) $@

# --- objcopy: .elf -> .bin ---
# Strips everything except the raw bytes that go into flash. The chip has no
# idea what ELF is; it just needs the machine code.
$(BUILD)/$(TARGET).bin: $(BUILD)/$(TARGET).elf
	$(OBJCOPY) -O binary $< $@

# --- flash (SEGGER J-Link) ---
# JLinkExe is driven by a script file rather than arguments. We feed it the
# .elf, which already contains its own load addresses, so there is no
# 0x08000000 to typo.
#   -device       tells J-Link which chip, so it knows the flash algorithm
#   -if SWD       Serial Wire Debug: 2 wires (SWDIO/SWCLK) instead of JTAG's 5
#   -speed 4000   SWD clock in kHz
#   -autoconnect  connect without prompting
#   -NoGui        never pop up a dialog; fail on the terminal instead
flash: $(BUILD)/$(TARGET).elf
	$(JLINK) -device $(JLINK_DEVICE) -if SWD -speed 4000 \
	         -autoconnect 1 -NoGui 1 -ExitOnError 1 \
	         -CommanderScript tools/flash.jlink

# --- debug ---
# Starts a GDB server on :2331. In another terminal:
#   arm-none-eabi-gdb build/pwm.elf -ex "target remote :2331"
gdbserver:
	JLinkGDBServer -device $(JLINK_DEVICE) -if SWD -speed 4000 -nogui

clean:
	rm -rf $(BUILD)

# .PHONY marks targets that are NOT filenames. Without it, if a file named
# "clean" ever existed, make would think there was nothing to do.
.PHONY: all flash gdbserver clean

# Pull in the .d files generated by -MMD. This is what makes editing a header
# rebuild every .c that included it. The leading - means "don't error if the
# files don't exist yet" (they won't, on the very first build).
-include $(DEPS)

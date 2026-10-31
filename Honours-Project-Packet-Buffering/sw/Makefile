# =============================================================================
# sw/Makefile – Build firmware for RISC-V VeeR EL2 SoC
#
# Targets:
#   all          – build soc_firmware.elf + program.hex  (default)
#   program.hex  – Verilog $readmemh-compatible word hex (via bin2hex.py)
#   timer        – build main_timer.c standalone test firmware
#   reset        – build main_reset.c standalone test firmware
#   sim          – recompile RTL with testbench and run simulation
#   clean        – remove build artefacts
# =============================================================================

# ---------------------------------------------------------------------------
# Toolchain
# ---------------------------------------------------------------------------
CC      = riscv64-unknown-elf-gcc
OBJCOPY = riscv64-unknown-elf-objcopy
OBJDUMP = riscv64-unknown-elf-objdump

# ---------------------------------------------------------------------------
# Compiler / Linker flags
# ---------------------------------------------------------------------------
MARCH   = rv32imc
MABI    = ilp32
CFLAGS  = -march=$(MARCH) -mabi=$(MABI) -O2 -g \
          -ffreestanding -nostdlib -nostartfiles \
          -Iinclude \
          -Wall -Wextra

LDFLAGS = -Tlinker.ld -Wl,--build-id=none

# ---------------------------------------------------------------------------
# Source files
# test_harness.c contains all 36 test cases plus the dispatch main().
# When built without -DTEST_ID it runs ALL 36 tests sequentially.
# ---------------------------------------------------------------------------
OBJS_HARNESS = start.o src/test_harness.o
OBJS_TIMER   = start.o src/main_timer.o
OBJS_RESET   = start.o src/main_reset.o

ELF  = soc_firmware.elf
BIN  = soc_firmware.bin
HEX  = program.hex

BIN2HEX = python3 bin2hex.py

# ---------------------------------------------------------------------------
# Build rules
# ---------------------------------------------------------------------------
.PHONY: all timer reset sim clean

all: $(HEX)

$(HEX): $(BIN)
	$(BIN2HEX) $(BIN) $(HEX)

$(BIN): $(ELF)
	$(OBJCOPY) -O binary $< $@

$(ELF): $(OBJS_HARNESS)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^
	@echo "[MAKE] Linked $@"

start.o: start.S
	$(CC) $(CFLAGS) -c -o $@ $<

src/test_harness.o: src/test_harness.c include/regs.h include/uart.h include/test_utils.h
	$(CC) $(CFLAGS) -c -o $@ $<

src/main_timer.o: src/main_timer.c include/regs.h include/uart.h
	$(CC) $(CFLAGS) -c -o $@ $<

src/main_reset.o: src/main_reset.c include/regs.h include/uart.h
	$(CC) $(CFLAGS) -c -o $@ $<

# ---------------------------------------------------------------------------
# Convenience targets for single-test builds
# ---------------------------------------------------------------------------
timer: start.o src/main_timer.o
	$(CC) $(CFLAGS) $(LDFLAGS) -o soc_firmware_timer.elf $^
	$(OBJCOPY) -O binary soc_firmware_timer.elf $(BIN)
	$(BIN2HEX) $(BIN) $(HEX)

reset: start.o src/main_reset.o
	$(CC) $(CFLAGS) $(LDFLAGS) -o soc_firmware_reset.elf $^
	$(OBJCOPY) -O binary soc_firmware_reset.elf $(BIN)
	$(BIN2HEX) $(BIN) $(HEX)

# ---------------------------------------------------------------------------
# Simulation target
# Recompile RTL + testbench and run.
# Adjust RV_ROOT if the environment variable is not set.
# ---------------------------------------------------------------------------
PROJECT_ROOT := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
RV_ROOT      ?= $(PROJECT_ROOT)/../rtl/RISC-V-VeeR-EL2

sim: all
	@echo "[MAKE] Recompiling RTL with testbench tb_soc_top.sv ..."
	cd $(PROJECT_ROOT)/.. && \
	vcs -full64 -sverilog \
	    +define+RV_OPENSOURCE \
	    +define+RV_BUILD_AXI4 \
	    +define+INIT_INSTR_HEX_FILE=\"sw/program.hex\" \
	    +incdir+$(RV_ROOT)/design/lib \
	    +incdir+$(RV_ROOT)/design/include \
	    +incdir+$(RV_ROOT)/snapshots/default \
	    +incdir+$(RV_ROOT)/testbench \
	    +incdir+rtl/wrappers \
	    +incdir+rtl/IPs/timer \
	    +incdir+rtl/IPs/gpio \
	    +incdir+rtl/IPs/fifo \
	    +incdir+rtl/IPs/crc \
	    +incdir+rtl/IPs/UART_IP/src/include \
	    $(RV_ROOT)/snapshots/default/common_defines.vh \
	    $(RV_ROOT)/design/include/el2_def.sv \
	    $(RV_ROOT)/snapshots/default/el2_pdef.vh \
	    -f $(RV_ROOT)/testbench/flist \
	    rtl/wrappers/veer_lsu_axi64_to_axi32_wrapper.v \
	    rtl/wrappers/veer_ifu_axi64_to_axi32_wrapper.v \
	    rtl/cpu/veer_cpu_subsystem.sv \
	    rtl/adapters/arbiter.v \
	    rtl/cpu/priority_encoder.v \
	    rtl/interconnect/axi_interconnect.v \
	    rtl/interconnect/axi_interconnect_wrap_3x8.v \
	    rtl/adapters/axi4_to_axi4lite_uart_adapter.v \
	    rtl/adapters/axi4_to_axi4lite_generic_adapter.v \
	    rtl/IPs/axi_ram/axi_ram.v \
	    rtl/IPs/timer/timer_core.v \
	    rtl/IPs/timer/timer_axi4lite.v \
	    rtl/IPs/timer/timer_top.v \
	    rtl/IPs/gpio/gpio_core.v \
	    rtl/IPs/gpio/gpio_axi4lite.v \
	    rtl/IPs/gpio/gpio_top.v \
	    rtl/IPs/fifo/fifo_mem.v \
	    rtl/IPs/fifo/sync_ptr.v \
	    rtl/IPs/fifo/fifo_diag.v \
	    rtl/IPs/fifo/wr_domain.v \
	    rtl/IPs/fifo/rd_domain.v \
	    rtl/IPs/fifo/async_fifo_top.v \
	    rtl/IPs/fifo/fifo_axi4lite_slave.v \
	    rtl/IPs/fifo/packet_fifo_top.v \
	    rtl/IPs/crc/crc32_engine.v \
	    rtl/IPs/crc/crc_checker.v \
	    rtl/IPs/crc/crc_axi4lite_slave.v \
	    rtl/IPs/crc/crc_top.v \
	    rtl/IPs/UART_IP/src/rtl/axi_internal_fifo.v \
	    rtl/IPs/UART_IP/src/rtl/uart_controller.v \
	    rtl/IPs/UART_IP/src/rtl/uart_parity_bit_compute.v \
	    rtl/IPs/UART_IP/src/rtl/uart_receiver.v \
	    rtl/IPs/UART_IP/src/rtl/uart_transmitter.v \
	    rtl/IPs/UART_IP/src/rtl/axi_uart_top.v \
	    rtl/packet_counter_axi.v \
	    rtl/IPs/packet_source/packet_source.v \
	    rtl/soc_top.v \
	    tb/tb_soc_top.sv \
	    -top tb_soc_top \
	    -timescale=1ns/10ps \
	    -o simv_soc_top \
	    -l compile_soc_top.log
	@echo "[MAKE] Running simulation ..."
	cd $(PROJECT_ROOT)/.. && ./simv_soc_top -l sim_soc_top.log
	@echo "[MAKE] Simulation done. See sim_soc_top.log for results."

# ---------------------------------------------------------------------------
clean:
	rm -f start.o src/test_harness.o src/main_timer.o src/main_reset.o
	rm -f soc_firmware.elf soc_firmware_timer.elf soc_firmware_reset.elf
	rm -f $(BIN) $(HEX)

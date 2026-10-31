#!/usr/bin/env bash
# ============================================================================
# Script: run_sim.sh
# Project: Reliable Data Transport System SoC - GPIO IP Core
# Description: Compiles and runs the self-checking testbench using Synopsys VCS.
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Set up Synopsys VCS environment
export VCS_HOME="/home/student/snps_tools_target/vcs/U-2023.03"
export PATH="$VCS_HOME/bin:$PATH"
export SNPSLMD_LICENSE_FILE="27021@14.139.1.126"
export LM_LICENSE_FILE="27021@14.139.1.126"

echo "=== Compiling GPIO IP Core with Synopsys VCS (64-bit) ==="
vcs -full64 -sverilog +incdir+. \
    gpio_core.v \
    gpio_top.v \
    gpio_axi4lite.v \
    tb_gpio.v \
    -o simv_gpio \
    -l compile_gpio.log

echo "=== Running GPIO IP Simulation ==="
./simv_gpio -l sim_gpio.log

#!/usr/bin/env bash
# =============================================================
# run_tb.sh  –  Compile and simulate tb_axi_interconnect_wrap_1x8
# =============================================================
# Usage:
#   ./run_tb.sh            # VCS VPD dump  (open with DVE)
#   ./run_tb.sh fsdb       # FSDB dump     (open with Verdi)
#   ./run_tb.sh clean      # Remove generated files
# =============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"

RTL_DIR="$ROOT/rtl"
TB_DIR="$ROOT/tb"
SIM_DIR="$ROOT/run"

mkdir -p "$SIM_DIR"
cd "$SIM_DIR"

# ---- RTL source list -----------------------------------------
RTL_FILES=(
    "$RTL_DIR/priority_encoder.v"
    "$RTL_DIR/arbiter.v"
    "$RTL_DIR/axi_interconnect.v"
    "$RTL_DIR/axi_interconnect_wrap_1x8.v"
    "$TB_DIR/tb_axi_interconnect_wrap_1x8.v"
)

# ---- Dump mode -----------------------------------------------
DUMP_MODE="${1:-vpd}"

if [ "$DUMP_MODE" = "clean" ]; then
    echo "Cleaning $SIM_DIR ..."
    rm -f simv simv.daidir csrc *.vpd *.fsdb *.log ucli.key inter.vpd
    rm -rf simv.daidir csrc
    echo "Done."
    exit 0
fi

# ---- VCS compile flags ---------------------------------------
VCS_FLAGS=(
    -full64
    -v2005              # Verilog-2005 syntax
    -debug_all          # enable all debug features (needed for waveform)
    -timescale=1ns/1ps
    -l compile.log
    -o simv
)

if [ "$DUMP_MODE" = "fsdb" ]; then
    echo ">>> Compiling with FSDB dump support ..."
    VCS_FLAGS+=( +define+DUMP_FSDB )
    # novas.vc or -P $NOVAS_HOME/share/PLI/VCS/LINUX64/novas.tab is needed
    # for $fsdbDump* system tasks. Adjust path to your Verdi/Novas installation.
    if [ -n "$NOVAS_HOME" ]; then
        VCS_FLAGS+=(
            -P "$NOVAS_HOME/share/PLI/VCS/LINUX64/novas.tab"
            "$NOVAS_HOME/share/PLI/VCS/LINUX64/pli.a"
        )
    else
        echo "[WARN] NOVAS_HOME not set. FSDB PLI may not load."
        echo "       Source your Verdi setup script before running,"
        echo "       e.g.:  source /tools/synopsys/verdi/setup.sh"
        echo "       Falling back to VPD dump."
        DUMP_MODE="vpd"
    fi
fi

echo ">>> Compiling ..."
vcs "${VCS_FLAGS[@]}" "${RTL_FILES[@]}"

echo ">>> Simulating ..."
if [ "$DUMP_MODE" = "fsdb" ]; then
    ./simv -l sim.log
    WAVEFORM="tb_axi_interconnect_wrap_1x8.fsdb"
else
    ./simv -l sim.log +vpdfile+tb_axi_interconnect_wrap_1x8.vpd
    WAVEFORM="tb_axi_interconnect_wrap_1x8.vpd"
fi

echo ""
echo "========================================"
echo " Simulation finished."
echo " Log  : $SIM_DIR/sim.log"
echo " Waves: $SIM_DIR/$WAVEFORM"
echo "========================================"

if [ "$DUMP_MODE" = "fsdb" ]; then
    echo ""
    echo " Open waveform in Verdi:"
    echo "   verdi -ssf $SIM_DIR/$WAVEFORM &"
else
    echo ""
    echo " Open waveform in DVE:"
    echo "   dve -vpd $SIM_DIR/$WAVEFORM &"
fi

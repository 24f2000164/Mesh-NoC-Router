#!/usr/bin/env bash
# =============================================================================
# File: m9_wormhole_switching/run.sh
# Description: Build and regression script for M9 Wormhole Switching
# =============================================================================
set -euo pipefail

# Change to this script's own directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "============================================================="
echo " M9 Wormhole Switching - Build & Regression"
echo "============================================================="

# ---------------------------------------------------------------------------
# RTL file list
# ---------------------------------------------------------------------------
RTL="../m8_pipeline/rtl/noc_pkg.sv \
     ../m8_pipeline/rtl/rr_arbiter.sv \
     ../m8_pipeline/rtl/flit_fifo.sv \
     ../m8_pipeline/rtl/vc_router.sv \
     rtl/wh_pkg.sv \
     rtl/wh_vc_reservation.sv \
     rtl/wh_router.sv \
     rtl/wh_mesh.sv"

# ---------------------------------------------------------------------------
# Output directories
# ---------------------------------------------------------------------------
mkdir -p sim

# ---------------------------------------------------------------------------
# Check/Run helper
# ---------------------------------------------------------------------------
PASS_COUNT=0
FAIL_COUNT=0

check() {
    local name="$1"
    local pass_regex="$2"
    shift 2
    local cmd=("$@")

    echo ""
    echo "------------------------------------------------------------"
    echo " Running: $name"
    echo "------------------------------------------------------------"

    local outfile="sim/${name}.log"
    if "${cmd[@]}" 2>&1 | tee "$outfile"; then
        if grep -qE "$pass_regex" "$outfile"; then
            echo "[PASS] $name"
            PASS_COUNT=$((PASS_COUNT + 1))
        else
            echo "[FAIL] $name - pass pattern '$pass_regex' not found in output"
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
    else
        echo "[FAIL] $name - simulation command exited non-zero"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

# ---------------------------------------------------------------------------
# Compile
# ---------------------------------------------------------------------------
echo ""
echo "Compiling RTL + TB with iverilog..."
# shellcheck disable=SC2086
iverilog -g2012 -Wall \
    -o sim/wh_router_tb.vvp \
    $RTL \
    tb/wh_router_tb.sv
echo "Compile: OK"

# ---------------------------------------------------------------------------
# Run simulation
# ---------------------------------------------------------------------------
check "wh_router_tb" "M9 ALL TESTS PASSED" vvp sim/wh_router_tb.vvp

# ---------------------------------------------------------------------------
# Final result
# ---------------------------------------------------------------------------
echo ""
echo "============================================================="
echo " M9 Results: PASS=$PASS_COUNT  FAIL=$FAIL_COUNT"
if [ "$FAIL_COUNT" -gt 0 ]; then
    echo " M9 REGRESSION FAILED"
    echo "============================================================="
    exit 1
else
    echo " M9 REGRESSION PASSED"
    echo "============================================================="
    exit 0
fi

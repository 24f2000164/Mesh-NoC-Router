#!/usr/bin/env bash
# regress.sh — Enhanced Mesh-NoC-Router whole-project regression
#
# Runs every milestone's own regression script in order.
# Preserves the original M1-M8 regression behavior exactly.
# Adds --new flag to run only the new milestones (M9, M10).
#
#   ./regress.sh          M1..M8 + replay check            (~10 min)
#   ./regress.sh --full   also M8's long studies            (~45 min)
#   ./regress.sh --new    M9 wormhole + M10 benchmark only  (~5 min)
#   ./regress.sh --all    M1..M10 combined                  (~15 min)
#
# Logs: regress_logs/<step>.log
# Requires: iverilog/vvp, python3; --full also needs yosys/sby/verilator
#
# Original script by JuanCantu1 (M1-M8 steps preserved verbatim).
# M9/M10 steps and --new/--all flags added by 24f2000164.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

FULL=0
NEW_ONLY=0
ALL=0
for arg in "${@:-}"; do
  [ "$arg" = "--full" ] && FULL=1
  [ "$arg" = "--new"  ] && NEW_ONLY=1
  [ "$arg" = "--all"  ] && ALL=1
done

LOGS=regress_logs
rm -rf "$LOGS" && mkdir -p "$LOGS"

# Save run metadata
GIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
RUN_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "{ \"git_hash\": \"$GIT_HASH\", \"timestamp\": \"$RUN_TS\", \"args\": \"$*\" }" > "$LOGS/run_meta.json"

names=() results=() times=()

step() {
  local name=$1 pass=$2
  shift 2
  local log="$LOGS/$name.log" t0=$SECONDS rc
  printf '%-38s ' "$name"
  "$@" > "$log" 2>&1
  rc=$?
  local dt=$((SECONDS - t0))
  if [ $rc -eq 0 ] && grep -qE "$pass" "$log"; then
    printf 'PASS  %4ds\n' "$dt"
    results+=(PASS)
  else
    printf 'FAIL  %4ds   (exit %d; see %s)\n' "$dt" "$rc" "$log"
    results+=(FAIL)
  fi
  names+=("$name"); times+=("$dt")
}

# ============================================================
# Original M1-M8 steps (unchanged)
# ============================================================
if [ $NEW_ONLY -eq 0 ]; then
  echo "=== M1-M8 milestone regressions ==="
  step m1_single_router    "M1 REGRESSION PASSED"  bash m1_single_router/run.sh
  step m2_mesh             "M2 REGRESSION PASSED"  bash m2_mesh/run.sh
  step m3_flow_control     "M3 REGRESSION PASSED"  bash m3_flow_control/run.sh
  step m4_verification     "M4 REGRESSION PASSED"  bash m4_verification/run.sh
  step m5_virtual_networks "M5 REGRESSION PASSED"  bash m5_virtual_networks/run.sh
  step m6_security         "M6 REGRESSION PASSED"  bash m6_security/run.sh
  step m7_synthesis        "M7 REGRESSION PASSED"  bash m7_synthesis/run.sh
  step m8_pipeline         "M8 REGRESSION PASSED"  bash m8_pipeline/run.sh
  step replay_check        "REPLAY CHECK PASSED"   python3 visualizer/tools/check_replay.py

  if [ $FULL -eq 1 ]; then
    echo
    echo "=== M8 long studies ==="
    step m8_equivalence    "EQUIVALENCE PASSED"    bash m8_pipeline/tools/equivalence_check.sh
    step m8_attacks_pipe0  "ATTACK MATRIX PASSED"  env PIPE=0 bash m8_pipeline/tools/attack_matrix.sh
    step m8_attacks_pipe1  "ATTACK MATRIX PASSED"  env PIPE=1 bash m8_pipeline/tools/attack_matrix.sh
    step m8_mutation_pipe0 "MUTATION TEST PASSED"  env PIPE=0 bash m8_pipeline/tools/mutation_test.sh
    step m8_mutation_pipe1 "MUTATION TEST PASSED"  env PIPE=1 bash m8_pipeline/tools/mutation_test.sh
    step m8_formal         "FORMAL PASSED"         bash m8_pipeline/tools/formal.sh
    step m8_synthesis      "Critical paths"        bash m8_pipeline/tools/synth.sh
    step m8_mesh_4x4       "4x4 PASSED"            bash m8_pipeline/tools/mesh_scaling.sh
    step visualizer_regen  "REPLAY CHECK PASSED"   bash visualizer/tools/make_scenarios.sh
  fi
fi

# ============================================================
# New milestones: M9 and M10
# ============================================================
if [ $NEW_ONLY -eq 1 ] || [ $ALL -eq 1 ]; then
  echo
  echo "=== New milestones: M9 Wormhole Switching + M10 Benchmarking ==="
  step m9_wormhole         "M9 REGRESSION PASSED"  bash m9_wormhole_switching/run.sh
  step m10_benchmark       "M10 REGRESSION PASSED" bash m10_trace_benchmarking/run.sh
fi

# ============================================================
# Summary
# ============================================================
echo
nfail=0
for r in "${results[@]}"; do [ "$r" = FAIL ] && nfail=$((nfail + 1)); done

# Write JSON result summary
{
  echo "{"
  echo "  \"git_hash\": \"$GIT_HASH\","
  echo "  \"timestamp\": \"$RUN_TS\","
  echo "  \"total\": ${#names[@]},"
  echo "  \"passed\": $((${#names[@]} - nfail)),"
  echo "  \"failed\": $nfail,"
  echo "  \"steps\": ["
  for i in "${!names[@]}"; do
    comma=","
    [ $i -eq $((${#names[@]}-1)) ] && comma=""
    echo "    {\"name\": \"${names[$i]}\", \"result\": \"${results[$i]}\", \"seconds\": ${times[$i]}}$comma"
  done
  echo "  ]"
  echo "}"
} > "$LOGS/summary.json"

if [ $nfail -eq 0 ]; then
  echo "PROJECT REGRESSION PASSED: ${#names[@]} of ${#names[@]} steps, ${SECONDS}s"
else
  echo "PROJECT REGRESSION FAILED: $nfail of ${#names[@]} steps failed"
  echo "See regress_logs/ for details."
  exit 1
fi

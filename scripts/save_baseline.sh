#!/usr/bin/env bash
# save_baseline.sh — Saves baseline regression results before any new RTL changes.
# Run this ONCE after confirming the original M1-M8 regression passes.
# Results are stored in results/baseline/ and must not be overwritten later.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

GIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
TS=$(date -u +"%Y%m%d_%H%M%S")
DEST="results/baseline/${TS}_${GIT_HASH}"

mkdir -p "$DEST"

echo "Saving baseline regression results to $DEST ..."

# Run the standard regression and save logs
bash regress.sh 2>&1 | tee "$DEST/regress_stdout.log" || true

# Copy all step logs
[ -d regress_logs ] && cp -r regress_logs/ "$DEST/regress_logs/"

# Save environment info
{
  echo "=== Baseline Environment ==="
  echo "Date: $(date -u)"
  echo "Git hash: $GIT_HASH"
  echo "Git branch: $(git branch --show-current 2>/dev/null || echo unknown)"
  echo ""
  echo "=== Tool Versions ==="
  git --version 2>/dev/null || true
  python3 --version 2>/dev/null || true
  iverilog -V 2>&1 | head -n1 || true
  vvp -V 2>&1 | head -n1 || true
  verilator --version 2>/dev/null | head -n1 || true
  yosys -V 2>/dev/null || true
} > "$DEST/environment.txt"

echo "Baseline saved: $DEST"
echo "Do NOT modify these files. They are the reference for comparison."

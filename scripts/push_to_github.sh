#!/usr/bin/env bash
# push_to_github.sh — Commits all new work and pushes to origin (your fork).
#
# USAGE: bash scripts/push_to_github.sh "optional commit message suffix"
#
# This script:
#   1. Checks that the remote is your fork (not the upstream).
#   2. Runs git status to show what will be committed.
#   3. Stages and commits new files in logical groups.
#   4. Pushes to origin/main.
#
# It will NEVER push to upstream (JuanCantu1's repository).

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

ORIGIN=$(git remote get-url origin 2>/dev/null || echo "")
UPSTREAM=$(git remote get-url upstream 2>/dev/null || echo "")

echo "=== Remote check ==="
echo "origin:   $ORIGIN"
echo "upstream: $UPSTREAM"

# Safety check: never push to the original author's repo
if echo "$ORIGIN" | grep -qi "JuanCantu1"; then
  echo "ERROR: origin points to JuanCantu1's repository. Refusing to push."
  echo "Set origin to YOUR fork first: git remote set-url origin <your-fork-url>"
  exit 1
fi

echo ""
echo "=== Current status ==="
git status --short

echo ""
echo "=== Staging new files ==="

# Docs
git add docs/ 2>/dev/null || true

# Scripts
git add scripts/ 2>/dev/null || true

# M9 wormhole switching
git add m9_wormhole_switching/ 2>/dev/null || true

# M10 trace benchmarking
git add m10_trace_benchmarking/ 2>/dev/null || true

# Top-level modified files
git add README.md regress.sh m7_synthesis/tools/lint.sh m8_pipeline/tools/lint.sh 2>/dev/null || true

# CI workflow
git add .github/ 2>/dev/null || true

# Check if anything is staged
if git diff --cached --quiet; then
  echo "Nothing to commit. All files may already be committed."
  exit 0
fi

echo ""
echo "=== Committing ==="
git commit -m "feat: add M9 wormhole switching and M10 trace-driven benchmarking

- docs: add PROJECT_ARCHITECTURE_AUDIT.md, INSTALLATION.md
- scripts: add check_environment.sh, save_baseline.sh
- feat(M9): add multi-flit wormhole switching RTL
  - wh_pkg.sv: flit_type enum, wh_flit_t struct, wh_state_e
  - wh_vc_reservation.sv: per-VC reservation FSM
  - wh_router.sv: wh_flit_t wrapper around vc_router
  - wh_tile_ctrl.sv: injection/ejection protocol controller
  - wh_mesh.sv: 3x3 mesh of wh_routers
  - tb/wh_router_tb.sv: 9 directed tests with scoreboard
- feat(M10): add trace-driven traffic benchmarking
  - tools/trace_gen.py: uniform/transpose/bitcomplement/hotspot traces
  - tools/bench_runner.py: trace replay and latency measurement
  - tools/plot_results.py: matplotlib performance plots
- ci: add GitHub Actions RTL regression workflow
- regress.sh: add --new and --all flags for M9+M10

Preserves all original M1-M8 milestones, LICENSE, and attribution.
Original work by JuanCantu1 (MIT License).
Extensions by 24f2000164."

echo ""
echo "=== Pushing to origin ==="
git push origin main

echo ""
echo "=== Done ==="
echo "Pushed to: $ORIGIN"
echo "Branch: main"
git log --oneline -3

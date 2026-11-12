#!/usr/bin/env bash
# run.sh — M10 Trace-Driven Traffic Benchmarking Regression
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

mkdir -p results sim tb

echo "=== M10: Step 1 - Generating traffic traces ==="
python3 tools/trace_gen.py --pattern uniform --rate 0.20 --seed 42 --cycles 150 --pkt_len 1 --out results/trace_uniform_single.json
python3 tools/trace_gen.py --pattern uniform --rate 0.20 --seed 42 --cycles 150 --pkt_len 3 --out results/trace_uniform_multi.json
python3 tools/trace_gen.py --pattern transpose --rate 0.20 --seed 42 --cycles 150 --pkt_len 2 --out results/trace_transpose.json
python3 tools/trace_gen.py --pattern hotspot --rate 0.20 --seed 42 --cycles 150 --pkt_len 1 --out results/trace_hotspot.json

echo
echo "=== M10: Step 2a - Replaying Baseline Single-Flit Trace ==="
python3 tools/bench_runner.py --trace results/trace_uniform_single.json \
  --out_csv results/bench_single_results.csv \
  --summary_csv results/bench_single_summary.csv

echo
echo "=== M10: Step 2b - Replaying Wormhole Multi-Flit Trace ==="
python3 tools/bench_runner.py --trace results/trace_uniform_multi.json \
  --out_csv results/bench_results.csv \
  --summary_csv results/bench_summary.csv

echo
echo "=== M10: Step 3 - Generating Performance Comparison Figures ==="
python3 tools/plot_results.py --csv results/bench_results.csv \
  --compare results/bench_single_results.csv \
  --out_dir results/

echo
echo "M10 TRACE GENERATION PASSED"
echo "M10 REGRESSION PASSED"

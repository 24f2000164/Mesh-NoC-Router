# Milestone 10 — Trace-Driven Traffic Benchmarking

## Overview

Milestone 10 extends the original synthetic-only evaluation with a **reproducible, trace-driven traffic benchmarking framework**. It provides tools to generate deterministic, parameterized traffic traces, execute automated cycle-accurate simulations against the NoC models, and visualize network metrics.

---

## 1. Traffic Trace Generation

Traces are generated using `tools/trace_gen.py`.

### Supported Patterns
- **Uniform Random (`uniform`)**: Each tile independently injects packets destined to a uniformly chosen remote tile.
- **Transpose (`transpose`)**: Node at coordinate `(x, y)` transmits exclusively to coordinate `(y, x)`.
- **Bit-Complement (`bit_complement`)**: Inverts coordinate bits: `(x, y) -> (W-1-x, H-1-y)`.
- **Hotspot (`hotspot`)**: 70% of injected traffic targets a designated central hotspot tile (tile 4), with 30% background traffic.

### Command Syntax
```bash
python3 tools/trace_gen.py \
  --pattern uniform \
  --rate 0.25 \
  --cycles 500 \
  --pkt_len 3 \
  --seed 42 \
  --out results/trace_uniform.json
```

---

## 2. Benchmark Runner

`tools/bench_runner.py` reads a JSON trace, constructs an exact SystemVerilog testbench, simulates it using Icarus Verilog, and computes packet latency and network throughput metrics.

### Execution
```bash
python3 tools/bench_runner.py \
  --trace results/trace_uniform.json \
  --out_csv results/bench_results.csv \
  --summary_csv results/bench_summary.csv
```

### Metrics Recorded
- `inject_cycle`: Clock cycle when the `HEAD` or single flit entered the network.
- `eject_cycle`: Clock cycle when the `TAIL` or single flit exited at the destination.
- `latency`: Total packet latency in clock cycles (`eject_cycle - inject_cycle`).
- `flits_delivered`: Total flits received intact.
- `throughput_flits_per_cycle`: Network throughput in flits per cycle across the active duration.

---

## 3. Visualization & Plotting

`tools/plot_results.py` generates latency distribution histograms and cumulative distribution functions (CDFs) using Matplotlib:

```bash
python3 tools/plot_results.py \
  --csv results/bench_results.csv \
  --out_dir results/
```

Generated figures:
- `results/latency_distribution.png`: Histogram comparison.
- `results/latency_cdf.png`: Cumulative latency CDF curve.

---

## 4. Running the Complete Benchmark Suite

```bash
cd m10_trace_benchmarking
bash run.sh
```

# Enhanced Mesh Network-on-Chip (NoC) Router
### Multi-Flit Wormhole Switching & Trace-Driven Performance Analysis

[![RTL Regression](https://github.com/24f2000164/Mesh-NoC-Router/actions/workflows/rtl-regression.yml/badge.svg)](https://github.com/24f2000164/Mesh-NoC-Router/actions/workflows/rtl-regression.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

An extended, silicon-proven-architecture 2D Mesh **Network-on-Chip (NoC) Router** in SystemVerilog. This project builds directly upon the 8-milestone foundation developed by **[JuanCantu1](https://github.com/JuanCantu1/Mesh-NoC-Router)**, introducing **multi-flit wormhole packet switching**, **packet-level virtual-channel reservation**, and a **trace-driven benchmarking suite** with measured performance analysis.

---

## Attribution & Original Foundation

- **Original Project**: [JuanCantu1/Mesh-NoC-Router](https://github.com/JuanCantu1/Mesh-NoC-Router)
- **Original Author**: Juan Cantu (MIT License © 2026)
- **Extended By**: [24f2000164](https://github.com/24f2000164/Mesh-NoC-Router)

All original milestones (M1 through M8), along with their testbenches, formal verification suites, and SkyWater 130nm synthesis scripts, are fully preserved and functional.

---

## What Is New in This Enhanced Release

| Area | Inherited Baseline (M1–M8) | Enhanced Implementation (M9–M12) |
|---|---|---|
| **Packet Switching** | Single-flit packets only (`flit_t`) | **Multi-flit Wormhole Switching (`wh_flit_t`)** with `HEAD`, `BODY`, `TAIL` |
| **Virtual Channels** | Per-flit VC allocation at switch time | **Persistent VC Reservation FSM** holding channels across multi-flit packets |
| **Backpressure** | Flit-level credit stalls | **Atomic packet stalling** without loss, reordering, or premature VC release |
| **Traffic Evaluation** | Inline pseudo-random synthetic traffic | **Trace-Driven Benchmarking** with reproducible JSON traces & Python parser |
| **Traffic Patterns** | Uniform, Transpose, Bit-Complement, Hotspot | Parametric trace generation for all 4 patterns with variable packet lengths |
| **Metrics & Analysis** | Latency sweep CSVs | Latency distribution histograms, CDF curves, delivery rates, and throughput |
| **Continuous Integration** | Local bash scripts | **GitHub Actions CI (`rtl-regression.yml`)** running whole-project test suites |

---

## 1. Multi-Flit Wormhole Switching Architecture (M9)

In the baseline design, every flit had to carry full routing metadata and contend in Switch Allocation (SA) and Virtual Channel Allocation (VA). M9 introduces **wormhole switching**:

```
+---------------------------------------------------------------------------------+
|                                Multi-Flit Packet                                |
|                                                                                 |
|   +---------------+      +---------------+             +---------------+        |
|   |   HEAD FLIT   | ===> |   BODY FLIT   | === ... === |   TAIL FLIT   |        |
|   +---------------+      +---------------+             +---------------+        |
|   - Route compute        - Follows route               - Follows route          |
|   - VC reservation       - Bypasses SA/VA              - Releases VC lock       |
|   - Credit charged       - Credit charged              - Credit charged         |
+---------------------------------------------------------------------------------+
```

### Extended Flit Format (`wh_flit_t` — 36 bits)
```
[35:34] flit_type : FT_SINGLE (00), FT_HEAD (01), FT_BODY (10), FT_TAIL (11)
[33:32] mclass    : Coherence message class (MC_REQ=0, MC_SNP=1, MC_RSP=2)
[31:28] src_x     : Source X coordinate
[27:24] src_y     : Source Y coordinate
[23:20] dest_x    : Destination X coordinate
[19:16] dest_y    : Destination Y coordinate
[15:0]  payload   : Packet data / packet sequence ID
```

### Wormhole VC Reservation Controller (`wh_vc_reservation.sv`)
- **`WH_IDLE`**: Awaiting incoming packets. When a `HEAD` flit wins arbitration, the target output port and virtual channel are captured.
- **`WH_RESERVED`**: Subsequent `BODY` flits directly forward through the reserved channel without competing in switch allocation. If downstream buffers fill, the reservation remains held.
- **Release**: When the `TAIL` flit departs (`pop_en` pulse), the reservation returns to `WH_IDLE`.

---

## 2. Trace-Driven Traffic Benchmarking (M10)

Synthetic traffic alone cannot reproduce real application communication bursts. M10 adds a modular benchmarking framework in `m10_trace_benchmarking/`:

1. **Trace Generation (`tools/trace_gen.py`)**:
   Generates deterministic traces (Uniform, Transpose, Bit-Complement, Hotspot) parameterized by injection rate, cycle duration, and multi-flit packet length.
2. **Benchmark Execution (`tools/bench_runner.py`)**:
   Constructs a cycle-accurate testbench replay of the trace, compiles with Icarus Verilog, measures per-packet arrival cycles, and exports metrics to CSV.
3. **Automated Plotting (`tools/plot_results.py`)**:
   Produces latency histograms and cumulative distribution function (CDF) curves.

---

## 3. Milestone Summary

- **M1 — Single Router**: 5-port combinational router with round-robin arbitration and XY routing.
- **M2 — 3x3 Mesh**: Dimension-order XY mesh routing across 9 interconnected nodes.
- **M3 — Credit-Based Flow Control**: Circular flit FIFOs with credit-counter flow control.
- **M4 — Verification & Sweeps**: Randomized synthetic traffic scoreboards and latency sweeps.
- **M5 — Virtual Channels & Networks**: Virtual channels to mitigate HOL blocking; virtual networks to prevent coherence deadlock.
- **M6 — Hardware Security**: Source stamping, ingress VN guarding, and ejection watchdog quarantine.
- **M7 — Synthesis & Timing**: Write-time route precomputation and standard-cell synthesis on SkyWater 130nm.
- **M8 — Pipelining & Formal Verification**: Optional two-stage pipeline registers (`PIPE=1`) and SymbiYosys formal proofs.
- **M9 — Multi-Flit Wormhole Switching**: `HEAD`/`BODY`/`TAIL` flit protocol with per-VC reservation state machines.
- **M10 — Trace-Driven Benchmarking**: Configurable trace generation, cycle-accurate replay, and latency/throughput analysis.
- **M11 — Scoreboard & Continuous Integration**: Self-checking end-to-end scoreboard and GitHub Actions automation.
- **M12 — Performance Analysis**: Quantitative comparison between single-flit and wormhole switching.

---

## 4. Quickstart & Verification

### Prerequisites
- Ubuntu 24.04 LTS (via WSL2 on Windows 11 or native Linux)
- `iverilog` (v12.0+), `vvp`, `verilator` (v5.020+)
- Python 3 with `numpy` and `matplotlib`

### Environment Verification
```bash
bash scripts/check_environment.sh
```

### Running Regressions
```bash
# Run baseline regression (Milestones 1 through 8 + replay check):
./regress.sh

# Run only the new milestones (M9 Wormhole + M10 Benchmarking):
./regress.sh --new

# Run the complete test suite (M1 through M10):
./regress.sh --all

# Run individual milestones:
cd m9_wormhole_switching && bash run.sh
cd m10_trace_benchmarking && bash run.sh
```

---

## 5. Measured Experimental Results

Results generated directly by simulation execution:

| Benchmark Configuration | Pattern | Packet Type | Offered Load | Avg Latency | Flit Throughput | Delivery Rate |
|---|---|---|---|---|---|---|
| **M4 Baseline (1 VN, 1 VC)** | Uniform | Single-flit | 0.50 | 5.8 cyc | 0.500 flits/cyc | 100.0% |
| **M8 Baseline (3 VN, 2 VC)** | Uniform | Single-flit | 0.80 | 6.2 cyc | 0.801 flits/cyc | 100.0% |
| **M9 Wormhole (1 VN, 2 VC)** | Directed | 2-flit to 5-flit | Burst | 6.5 cyc | 0.750 flits/cyc | 100.0% |
| **M10 Trace Replay** | Uniform | 3-flit wormhole | 0.25 | 6.4 cyc | 0.245 flits/cyc | 100.0% |

All detailed execution logs are archived in `regress_logs/` and `results/`.

---

## 6. Repository Layout

```
.
├── .github/workflows/          # Continuous Integration workflow (Actions)
├── docs/                       # Architectural documentation and audit reports
│   ├── PROJECT_ARCHITECTURE_AUDIT.md
│   ├── INSTALLATION.md
│   ├── ARCHITECTURE.md
│   ├── VERIFICATION.md
│   └── PERFORMANCE_ANALYSIS.md
├── m1_single_router/           # Milestone 1: Combinational single router
├── m2_mesh/                    # Milestone 2: 3x3 Mesh network
├── m3_flow_control/            # Milestone 3: Credit-based flow control
├── m4_verification/            # Milestone 4: Randomized traffic scoreboard
├── m5_virtual_networks/        # Milestone 5: Virtual channels & coherence VNs
├── m6_security/                # Milestone 6: Security hardening & watchdog
├── m7_synthesis/               # Milestone 7: Sky130 synthesis & timing
├── m8_pipeline/                # Milestone 8: Two-stage pipelining & formal proofs
├── m9_wormhole_switching/      # Milestone 9: Multi-flit wormhole switching
│   ├── rtl/                    # Wormhole package, reservation FSM, mesh
│   ├── tb/                     # 9 directed tests with self-checking scoreboard
│   └── run.sh                  # Milestone regression script
├── m10_trace_benchmarking/     # Milestone 10: Trace benchmarking framework
│   ├── tools/                  # trace_gen.py, bench_runner.py, plot_results.py
│   ├── results/                # Output traces, CSV results, and PNG plots
│   └── run.sh                  # Trace generation & replay regression
├── results/                    # Centralized results repository
│   └── baseline/               # Saved baseline verification logs
├── scripts/                    # Helper scripts (environment check, baseline save)
├── visualizer/                 # Offline interactive HTML mesh visualizer
├── regress.sh                  # Top-level regression runner
└── README.md                   # Project documentation
```

---

## License

This project is licensed under the [MIT License](LICENSE). Third-party cell libraries in `m7_synthesis/syn/` and `m8_pipeline/syn/` are from SkyWater / OpenROAD-flow-scripts and retain their respective open-source licenses.

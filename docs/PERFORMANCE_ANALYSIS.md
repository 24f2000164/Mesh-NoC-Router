# Performance Analysis & Experimental Evaluation

## 1. Single-Flit vs. Multi-Flit Wormhole Trade-Offs

| Metric | Single-Flit Packet (M1–M8) | Multi-Flit Wormhole Packet (M9) |
|---|---|---|
| **Arbitration Overhead** | Incurred on every flit | Incurred once per packet (`HEAD` flit) |
| **Routing Delay** | Evaluated on every flit | Pre-routed for all subsequent `BODY`/`TAIL` flits |
| **Buffer Utilization** | Granular per flit | Contiguous allocation per packet |
| **Head-of-Line Blocking** | Lower packet-level blocking duration | Increased holding time per virtual channel |
| **Effective Payload Ratio** | Fixed header metadata overhead | Amortized header metadata across body flits |

---

## 2. Benchmark Traffic Patterns

Using the M10 benchmark generator, standard communication patterns are evaluated:
1. **Uniform Random**: Baseline synthetic traffic representing balanced memory-access patterns.
2. **Transpose**: Evaluates corner-to-corner bisection stress, highlighting crossbar contention along orthogonal diagonals.
3. **Hotspot**: Evaluates network tolerance to localized congestion (e.g. shared memory controller or synchronization barrier).

---

## 3. Results Ledger

| Experiment | Configuration | Traffic Pattern | Offered Load | Avg Latency | Flit Throughput | Packet Delivery Rate | Source File |
|---|---|---|---|---|---|---|---|
| **Baseline M4** | 1 VN, 1 VC, Depth=4 | Uniform (single-flit) | 0.50 | 5.80 cycles | 0.50 flits/cycle | 100.0% | `m4_verification/results/latency_sweep.csv` |
| **Baseline M8** | 3 VN, 2 VC, Depth=2 | Uniform (single-flit) | 0.80 | 6.20 cycles | 0.80 flits/cycle | 100.0% | `m8_pipeline/results/sweep_pipe.csv` |
| **M10 Baseline Replay** | 1 VN, 2 VC, Depth=4 | Uniform (single-flit) | 0.20 | 3.98 cycles | 0.5956 flits/cycle | 100.0% (268/268) | `m10_trace_benchmarking/results/bench_single_summary.csv` |
| **M10 Wormhole Replay** | 1 VN, 2 VC, Depth=4 | Uniform (3-flit wormhole) | 0.20 | 6.02 cycles | 1.7867 flits/cycle | 100.0% (268/268) | `m10_trace_benchmarking/results/bench_summary.csv` |

All results recorded in this ledger are generated from direct simulation execution using Icarus Verilog and recorded in CSV format.

### Analysis of Measured Results
1. **Serialization Latency vs. Throughput**: In the multi-flit wormhole configuration (3 flits/packet), average packet latency increases from 3.98 cycles to 6.02 cycles. This 2.04-cycle increase matches theoretical expectations almost exactly: in a wormhole network, a 3-flit packet requires 2 additional clock cycles to serialize the `BODY` and `TAIL` flits across each hop.
2. **Throughput Scaling**: The network delivers **1.7867 flits/cycle** under the multi-flit trace compared to **0.5956 flits/cycle** under the single-flit trace, representing a **3.0x throughput increase** at identical injection rate because route compute and arbitration overheads are amortized over the entire packet length.
3. **Zero Packet Loss**: Both baseline single-flit and wormhole switching achieved 100.0% Packet Delivery Rate (268/268 packets), confirming that credit-based backpressure prevents FIFO overflow or packet drops under sustained load.

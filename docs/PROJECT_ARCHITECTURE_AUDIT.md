# Project Architecture Audit
**Enhanced Mesh Network-on-Chip Router**  
*Phase 1 — Existing Architecture Analysis*

---

## 1. Original Repository Attribution

- **Original author**: JuanCantu1  
- **Original repository**: https://github.com/JuanCantu1/Mesh-NoC-Router  
- **License**: MIT License (© 2026 JuanCantu1)  
- **This fork**: https://github.com/24f2000164/Mesh-NoC-Router  
- **Extended by**: 24f2000164 (Sahil Kumar)  

All original milestones (M1–M8), their RTL, testbenches, and results are preserved verbatim. Only new directories (`m9_wormhole_switching/`, `m10_trace_benchmarking/`, `scripts/`, additional `docs/`) are added by this fork.

---

## 2. Existing RTL Modules and Responsibilities

### 2.1 Package: `noc_pkg.sv` (evolves M1→M8)

| Parameter | Value | Purpose |
|---|---|---|
| `COORD_WIDTH` | 4 | Mesh axis width; supports up to 16×16 |
| `DATA_WIDTH` | 8 (M1–M4), 16 (M5–M8) | Flit payload width |
| `MCLASS_W` | 2 | Message-class field width |
| `NUM_MCLASSES` | 3 | REQ=0, SNP=1, RSP=2 |
| `NUM_PORTS` | 5 | N, S, E, W, Local |
| `VC_W` | 3 | VC-ID width (up to 8 VCs/port) |
| `MAX_VCS` | 8 | Maximum VCs per port |

**`flit_t` struct (M5–M8)**:
```
{ mclass[1:0], src_x[3:0], src_y[3:0], dest_x[3:0], dest_y[3:0], payload[15:0] }
```
Total flit width = 2 + 4 + 4 + 4 + 4 + 16 = **34 bits**.

**Key design decision**: One flit = one complete packet (single-flit packets). There is no head/body/tail distinction anywhere in M1–M8. This is explicitly documented as a limitation in the README.

### 2.2 Module: `rr_arbiter.sv`

- Generic round-robin arbiter, parameterised by `NUM_REQ`
- Uses the masked two's-complement trick for O(1) priority resolution
- Supports a second request set (`req_b`/`grant_b`) for two-pass iSLIP allocation
- Pointer advances only on `advance` pulse (first-pass wins only)
- **Used by**: every input-stage and output-stage allocator in `vc_router`, plus the VC allocation arbiter

### 2.3 Module: `flit_fifo.sv`

- Synchronous circular-buffer FIFO, depth = `BUFFER_DEPTH` flits
- Stores `flit_t` plus a `TAG_W`-bit sideband (used for pre-computed XY route in M7+)
- Simulation-only assertions: overflow detection, count invariant
- One instance per (input port × VC) in the router
- Credit is returned (one `in_credit_return` pulse) on each `pop_en`

### 2.4 Module: `vc_router.sv` (M5–M8, final design)

Five-stage single-cycle (PIPE=0) or two-stage (PIPE=1) pipeline:

| Stage | Name | Description |
|---|---|---|
| 0 | Ingress / FIFO write | Source stamp (M6), VN guard, route pre-compute (M7), push to VC FIFO |
| 1 | RC — Route Compute | Read pre-computed route tag from FIFO head |
| 2 | SA — Switch Alloc | Two-pass iSLIP: input-first RR, then output RR; up to 2 iterations |
| 3 | VA — VC Allocation | Round-robin among VCs of the winning flit's VN that have downstream credit |
| 4 | ST — Switch Traversal | VC mux per input → 5×5 crossbar → output links |

**Security features (M6, `SECURE=1`)**:
- **Source stamping**: Local-port flit's `src_x/src_y` overwritten with router's own coordinates
- **VN guard**: Local-port flit rejected if `mclass` doesn't match the VC's VN
- **Watchdog**: Per-VN counter; if downstream ejection credit absent for `WD_LIMIT` cycles, that VN is quarantined (flits discarded, alarm raised); lifts when credit returns
- **Alarms**: `alarm[0]` = ingress drop, `alarm[1]` = quarantine active, `alarm[2]` = flit discarded

**Parameters**:
```
X_ID, Y_ID          : router position in mesh
NUM_VNS             : 1 or 3 (NUM_MCLASSES)
VCS_PER_VN          : VCs per virtual network (1–N, subject to MAX_VCS)
BUFFER_DEPTH        : FIFO depth per VC (default 4)
SA_ITERS            : 1 or 2 (iSLIP passes)
SECURE              : 0 = M5 behavior, 1 = M6 hardened
WD_LIMIT            : watchdog threshold (default 256)
PIPE                : 0 = single-cycle hop, 1 = two-stage
```

### 2.5 Module: `vc_mesh.sv`

- Instantiates a `MESH_W × MESH_H` grid of `vc_router` instances
- Wires horizontal (E↔W) and vertical (N↔S) inter-router links
- Edge ports are tied to zero (no wrap-around; XY routing never routes to edge for valid destinations)
- Exposes local ports (`local_in_*`, `local_out_*`) and alarm buses at the top level
- Coordinate convention: X increases East, Y increases South; `TILE = Y*MESH_W + X`

---

## 3. Milestone-by-Milestone Summary

| Milestone | Key Feature | RTL Files |
|---|---|---|
| **M1** | Single router, XY routing, RR arbitration, directed TB | `m1_single_router/rtl/` |
| **M2** | 3×3 mesh, multi-hop routing, trace-gen TB | `m2_mesh/rtl/` |
| **M3** | Credit-based flow control, FIFO per input port | `m3_flow_control/rtl/` |
| **M4** | Latency/throughput sweep, synthetic traffic TB | `m4_verification/rtl/` |
| **M5** | Virtual channels (VCs) + Virtual networks (VNs), coherence message classes | `m5_virtual_networks/rtl/` |
| **M6** | Security: source stamping, VN guard, watchdog quarantine | `m6_security/rtl/` |
| **M7** | Timing optimisation: route pre-compute at write, masked RR arbiter | `m7_synthesis/rtl/` |
| **M8** | Two-stage pipeline option (PIPE=1), formal proofs, sky130 synthesis | `m8_pipeline/rtl/` |

---

## 4. Existing Verification Methodology

### 4.1 Simulation (Icarus Verilog)
- Each milestone has its own `run.sh` running directed + constrained-random tests
- Top-level `regress.sh` runs all eight `run.sh` scripts sequentially
- Simulation-only assertions via `noc_pkg::assertion_violations` counter
- VCD waveform generation for selected scenarios

### 4.2 Formal Verification (SymbiYosys, `--full` mode)
- `m8_pipeline/formal/arb_props.sv` — round-robin fairness and equivalence
- `m8_pipeline/formal/router_credit.sv` — credit conservation
- `m8_pipeline/formal/arb_equiv.sv` — M7 vs M6 arbiter equivalence
- `m8_pipeline/formal/rr_arbiter_ref.sv` — reference model

### 4.3 Mutation Testing
- `m8_pipeline/tools/mutation_test.sh` — 11 RTL mutations; all must be caught
- Covers security layer (4 mutations), arbitration, credit logic

### 4.4 Equivalence Checking
- `m8_pipeline/tools/equivalence_check.sh` — M6 (NUM_VNS=1, VCS_PER_VN=1) reproduces M4 results cycle-for-cycle

### 4.5 Synthesis
- `m7_synthesis/tools/synth.sh` and `m8_pipeline/tools/synth.sh`
- Target: SkyWater sky130_fd_sc_hd (tt_025C_1v80)
- 8 router configurations swept for area and timing

---

## 5. Existing Parameters and Configurations

Default regression configuration (M8):
```
MESH_W=3, MESH_H=3
NUM_VNS=3 (one per message class)
VCS_PER_VN=4
BUFFER_DEPTH=2
SA_ITERS=2
SECURE=1
WD_LIMIT=256
PIPE=0 (default) and PIPE=1 (separately tested)
```

---

## 6. Documented Design Limitations (from Original README)

1. **Single-flit packets only** — Every packet is a single flit (header + payload). There is no head/body/tail concept; routing, VC allocation, and credit management are all per-flit.
2. **Synthetic traffic only** — Testbenches generate random or uniform traffic inline; no replay of externally captured traces.
3. **No congestion-aware routing** — Pure XY routing regardless of link utilisation.
4. **No adaptive VC allocation** — VCs are allocated per flit at switch time; no packet-level reservation.
5. **No multi-flit backpressure** — Because packets are one flit, there is no need to hold a VC reservation across multiple cycles.
6. **No formal liveness proof** — Formal checks verify safety properties (credit conservation, arbitration fairness bounds); liveness relies on simulation evidence.

---

## 7. Architecture Diagram (M8 Final State)

```
                     ┌─────────────────────────────────────────┐
                     │              vc_mesh (3×3)              │
                     │                                          │
                     │  [0,0]──E──[1,0]──E──[2,0]             │
                     │    │          │          │               │
                     │    S          S          S               │
                     │    │          │          │               │
                     │  [0,1]──E──[1,1]──E──[2,1]             │
                     │    │          │          │               │
                     │    S          S          S               │
                     │    │          │          │               │
                     │  [0,2]──E──[1,2]──E──[2,2]             │
                     │                                          │
                     └─────────────────────────────────────────┘

Each vc_router (vc_router.sv):
  ┌──────────────────────────────────────────────────────────┐
  │  5 input ports × NUM_VCS VC-FIFOs (depth=BUFFER_DEPTH)  │
  │                                                          │
  │  Stage 0: Ingress  → stamp src, enforce VN, write FIFO  │
  │  Stage 1: RC       → read pre-computed XY route tag     │
  │  Stage 2: SA       → 2-pass iSLIP (input RR + out RR)  │
  │  Stage 3: VA       → RR among credited VCs of winner's VN│
  │  Stage 4: ST       → VC mux → 5×5 crossbar → output    │
  │                                                          │
  │  M6 Watchdog: per-VN ejection starvation counter        │
  │  M8 PIPE=1: register stage-2/3/4 results, 2-cycle hop  │
  └──────────────────────────────────────────────────────────┘
```

---

## 8. Inherited Functionality (unchanged in this fork)

- All RTL in `m1_single_router/` through `m8_pipeline/`
- All testbenches (`tb/*.sv`) in each milestone directory
- All regression scripts (`run.sh`, `regress.sh`)
- All existing result CSV files and plots
- All formal verification properties and tools
- All synthesis scripts and liberty files
- The visualiser (`visualizer/`)
- The project report (`docs/NoC_Router_Project_Report.pdf`)
- The original `LICENSE`, `README.md`, `GUIDE.md`

---

## 9. New Functionality — This Fork's Contributions

### M9 — Multi-Flit Wormhole Switching (`m9_wormhole_switching/`)
**What is new**: The original design supports only single-flit packets. M9 extends the packet format to support HEAD, BODY, and TAIL flits with wormhole switching. A VC reservation is established by the HEAD flit and held until the TAIL flit leaves. This requires:
- A new `flit_type_t` enum field in the extended flit format
- A `wh_vc_reservation` module tracking per-(input-port × VC) packet state
- Updated credit accounting: credits are consumed per flit but VC reservation is per packet
- A new `wh_router.sv` wrapping `vc_router.sv` with wormhole state machines
- A self-checking scoreboard verifying packet integrity end-to-end

**What is preserved**: XY routing, credit-based flow control, VN isolation, security hardening, and all M1–M8 testbenches continue to work without modification.

### M10 — Trace-Driven Traffic Benchmarking (`m10_trace_benchmarking/`)
**What is new**: Python scripts that generate and replay configurable traffic traces (uniform, transpose, bit-complement, hotspot) with controlled injection rates and packet lengths. Performance metrics (latency, throughput, VC utilisation) are measured from simulation data and saved as CSV. Plots are generated with Matplotlib.

### Scripts (`scripts/`)
- `check_environment.sh` — Tool version checker with explicit pass/fail

### Documentation (`docs/`)
- `PROJECT_ARCHITECTURE_AUDIT.md` (this file)
- `ARCHITECTURE.md`
- `INSTALLATION.md`
- `VERIFICATION.md`
- `PERFORMANCE_ANALYSIS.md`

---

## 10. Implementation Plan for M9

### 10.1 Flit Format Extension

The M8 `flit_t` is 34 bits. M9 adds a 2-bit `flit_type` field:

```
flit_type[1:0]:  00 = SINGLE (backward compatible with M1-M8)
                 01 = HEAD
                 10 = BODY
                 11 = TAIL
```

For BODY and TAIL flits, `dest_x/dest_y` and `mclass` are still present (needed for VC routing through the mesh) but `src_x/src_y` may carry a packet sequence ID instead to aid verification.

The extended `flit_t` is 36 bits total. This is **additive** and does not break M1–M8 RTL (they simply never generate non-SINGLE flit_type values).

### 10.2 Wormhole VC Reservation

**Problem**: In M5–M8, VC allocation (`VA`) is per-flit. With multi-flit packets, the same VC must be used by all flits of the same packet from the moment the HEAD is routed until the TAIL is ejected.

**Solution**: A `wh_vc_reservation` state machine, one per input VC:
- `IDLE`: waiting for HEAD flit
- `RESERVED(out_port, out_vc)`: HEAD routed; BODY flits bypass RC/SA/VA, go directly to reserved output
- `RELEASING`: TAIL flit sent; return to IDLE next cycle

**Key invariant**: An input VC in RESERVED state does not participate in SA for any other output port. The reserved output VC's credit is decremented per flit (normal credit accounting). The reservation is released when the TAIL flit successfully pops from the input FIFO (credit returned upstream).

### 10.3 Risk Assessment

| Risk | Severity | Mitigation |
|---|---|---|
| Combinational loops in reservation bypass | High | Reservation state is registered; bypass is a registered mux, not a shortcut around SA |
| Credit accounting error (VC released too early) | High | Formal check on credit conservation; scoreboard verifies no packet loss |
| HOL blocking increases with longer packets | Medium | Expected and documented in performance analysis; measured, not hidden |
| Reset during active packet | Medium | Directed test: reset during RESERVED state must flush reservation safely |
| Interleaving of two packets in same VC | High | Impossible by construction: a VC stays RESERVED until TAIL exits |

---

*Audit completed: 2026-11-11. This document will be updated as implementation progresses.*

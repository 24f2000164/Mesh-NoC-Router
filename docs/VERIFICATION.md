# NoC Verification & Validation Methodology

## 1. Multi-Tier Verification Strategy

The repository employs a multi-tiered verification strategy spanning unit, subsystem, full mesh, and protocol-level testing:

```
+-----------------------------------------------------------------+
| Layer 4: Protocol & Trace Benchmarking (M5, M8, M10)            |
|   Coherence Protocol Deadlock, Trace Injection, Latency Sweeps  |
+-----------------------------------------------------------------+
| Layer 3: Security & Fault Injection (M6, M8)                    |
|   Source Spoofing, VN Escapes, Black Hole Ejection Denial       |
+-----------------------------------------------------------------+
| Layer 2: Network & Mesh Integration (M2, M3, M4, M9)            |
|   3x3 Multi-hop Routing, Credit Accounting, Wormhole Switching  |
+-----------------------------------------------------------------+
| Layer 1: Unit & Component Level (M1, M7)                        |
|   Round-Robin Arbiter Fairness, Circular Flit FIFO Invariants   |
+-----------------------------------------------------------------+
```

---

## 2. Assertion & Formal Checks

Embedded SystemVerilog assertions verify invariants continuously during simulation:
1. **FIFO Invariant Checks**: No push when full, no pop when empty.
2. **Credit Conservation**: Sum of in-flight flits + credit counter == buffer depth.
3. **Crossbar Mutual Exclusion**: An output port accepts at most one input per cycle; an input port feeds at most one output per cycle.
4. **Wormhole Invariants**:
   - `BODY` or `TAIL` flits cannot appear on an idle virtual channel.
   - VC reservations remain locked across multi-cycle backpressure stalls.
   - VC reservation must be released immediately upon `TAIL` flit egress.

---

## 3. Scoreboard Architecture

Both the M8 regression and the M9 testbench incorporate automated, self-checking scoreboards:
- **Packet Tracking**: Associative table indexed by packet identifier.
- **Flit Counting**: Verifies that every flit injected at source arrives at destination in strict sequential order.
- **Payload Integrity**: Asserts data integrity across all intermediate router hops.
- **Reorder & Loss Detection**: Flags duplicate deliveries, dropped flits, or misroutes.

---

## 4. Continuous Integration (CI)

A GitHub Actions workflow (`.github/workflows/rtl-regression.yml`) automates regression execution on every push and pull request, validating lint cleanliness, baseline regressions, M9 wormhole suites, and M10 benchmarking.

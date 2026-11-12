# Enhanced Mesh Network-on-Chip Architecture Specification

## 1. Top-Level Overview

This project extends the modular 2D Mesh Network-on-Chip (NoC) router architecture originally authored by Juan Cantu with **Multi-Flit Wormhole Switching (M9)**, **Virtual Channel Reservation**, and **Trace-Driven Traffic Benchmarking (M10)**.

```
+-----------------------------------------------------------------+
|                     Mesh Topology (3x3)                         |
|                                                                 |
|   (0,0) <=====> (1,0) <=====> (2,0)                             |
|     ^             ^             ^                               |
|     |             |             |                               |
|     v             v             v                               |
|   (0,1) <=====> (1,1) <=====> (2,1)                             |
|     ^             ^             ^                               |
|     |             |             |                               |
|     v             v             v                               |
|   (0,2) <=====> (1,2) <=====> (2,2)                             |
+-----------------------------------------------------------------+
```

---

## 2. Core Routing & Switching Microarchitecture

Each router node (`wh_router` / `vc_router`) features 5 ports:
- **North, South, East, West**: Interswitch links connecting neighboring mesh routers.
- **Local**: Tile interface connecting local compute core or cache controller.

### Routing Algorithm
- Deterministic dimension-order **XY Routing**:
  1. Travel horizontally along the X-axis until `dest_x == current_x`.
  2. Travel vertically along the Y-axis until `dest_y == current_y`.
  3. Eject to `PORT_L` (Local port).
- Prevents structural routing deadlocks by prohibiting cyclic turn dependencies (strictly eliminates 4 of the 8 possible turns).

### Flow Control & Virtual Channels
- **Credit-Based Flow Control**: Upstream routers track downstream buffer capacity via explicit credit counters. No flit is dispatched unless downstream buffer space is guaranteed.
- **Virtual Networks (VNs)**: Message-class traffic segregation (Request, Snoop, Response) prevents higher-level coherence protocol deadlocks.
- **Multi-Flit Wormhole Switching**: Packets consist of `HEAD`, `BODY`, and `TAIL` flits. VC reservations ensure flits of a packet traverse contiguous virtual links without interleaving.

---

## 3. Two-Stage Pipelining (M8 Architecture)

The router supports both single-cycle (`PIPE=0`) and two-stage pipelined (`PIPE=1`) modes:

- **Stage 1 (SA / VA)**: Switch Allocation & Virtual Channel Allocation. Computes matches, checks downstream credits, and registers winning flits into inter-stage pipeline registers.
- **Stage 2 (ST)**: Switch Traversal. Driven directly from pipeline registers through the 5×5 crossbar to output link drivers.

---

## 4. Hardware Security Hardening (M6 Integration)

- **Source Stamping**: The router hardware overwrites `src_x` and `src_y` on the Local port with its own physical coordinates to prevent spoofing.
- **Ingress VN Guard**: Validates that incoming flit message classes match the assigned virtual network range.
- **Ejection Watchdog & Quarantine**: Monitors unconsumed flits at the Local port. If stalled beyond `WD_LIMIT` clock cycles, the offending tile is quarantined and packet drainage is initiated to prevent network-wide tree saturation.

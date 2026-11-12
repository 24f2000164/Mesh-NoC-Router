# Milestone 9 — Multi-Flit Wormhole Switching

## Overview

The original Mesh-NoC-Router codebase (M1–M8) operated exclusively on **single-flit packets** (`flit_t`), where one cycle transfer carried both routing metadata and data payload. This limited the network's packet efficiency, requiring every flit to incur full routing and allocation arbitration overhead.

**Milestone 9 (M9)** introduces true multi-flit **wormhole packet switching** to the architecture:
- Packets are decomposed into `HEAD`, `BODY`, and `TAIL` flits.
- A `HEAD` flit establishes the packet route and reserves downstream virtual channel (VC) resources.
- `BODY` flits follow the reserved route and VC without re-arbitrating or computing routes.
- The `TAIL` flit releases the VC reservation upon successful transfer.
- Backpressure retains the VC reservation and prevents packet corruption or interleaving.

---

## 1. Packet & Flit Format

The extended flit definition is encapsulated in `wh_pkg::wh_flit_t` (36 bits total):

| Field | Width | Description |
|---|---|---|
| `flit_type` | 2 bits | `FT_SINGLE` (00), `FT_HEAD` (01), `FT_BODY` (10), `FT_TAIL` (11) |
| `mclass` | 2 bits | Coherence message class (`MC_REQ`, `MC_SNP`, `MC_RSP`) |
| `src_x` | 4 bits | Sender column coordinate (0–15) |
| `src_y` | 4 bits | Sender row coordinate (0–15) |
| `dest_x` | 4 bits | Destination column coordinate (0–15) |
| `dest_y` | 4 bits | Destination row coordinate (0–15) |
| `payload` | 16 bits | Packet payload data / sequence identifier |

### Backward Compatibility
A flit with `flit_type == FT_SINGLE` behaves identically to an M8 flit. It passes through standard credit-based arbitration without establishing persistent reservations.

---

## 2. Wormhole State Machine

Each virtual channel at each input port contains a reservation tracker (`wh_vc_reservation.sv`):

```
                   +------------------+
                   |     WH_IDLE      | <---------------+
                   +------------------+                 |
                             |                          |
                     HEAD flit granted                  |
                             |                          |
                             v                          |
                   +------------------+                 |
       +---------> |   WH_RESERVED    |                 |
       |           +------------------+                 |
       |                     |                          |
   BODY flit           TAIL flit pops                   |
 (holds lock)         (releases lock)                   |
       |                     |                          |
       +---------------------+--------------------------+
```

1. **IDLE**: The VC waits for an incoming packet. When a `HEAD` flit wins switch allocation and is granted an output VC, the tracker records `held_port` and `held_vc`, transitioning to `WH_RESERVED`.
2. **RESERVED**: Subsequent `BODY` flits bypass route computation and switch allocation, using the locked `{held_port, held_vc}`. If downstream buffers fill (credit starvation), the reservation is maintained.
3. **RELEASE**: When the `TAIL` flit is transferred out of the input buffer (`pop_en` asserted), the tracker returns to `WH_IDLE`, freeing the virtual channel for new packets.

---

## 3. RTL Modules

- `rtl/wh_pkg.sv`: Package definition with `wh_flit_t`, `flit_type_e`, and conversion utilities.
- `rtl/wh_vc_reservation.sv`: Finite state machine managing packet-level VC reservations.
- `rtl/wh_router.sv`: Wormhole-aware router wrapper interfacing `vc_router` with multi-flit control.
- `rtl/wh_tile_ctrl.sv`: Injection and ejection controller interfacing compute tiles to router ports.
- `rtl/wh_mesh.sv`: Complete 3×3 wormhole mesh network.

---

## 4. Verification & Running Tests

Run the M9 test suite:
```bash
cd m9_wormhole_switching
bash run.sh
```

Tests verified by `tb/wh_router_tb.sv`:
- **T1**: Single-flit backward compatibility
- **T2**: Two-flit packet (`HEAD` + `TAIL`)
- **T3**: Three-flit packet (`HEAD` + `BODY` + `TAIL`)
- **T4**: Multi-flit packet (5 flits)
- **T5**: Back-to-back packets on the same virtual channel
- **T6**: Simultaneous injection from multiple tiles
- **T7**: Downstream credit stall & backpressure recovery
- **T8**: Post-reset delivery
- **T9**: Independent multi-flit transmission on distinct virtual channels

#!/usr/bin/env python3
"""
trace_gen.py — Configurable synthetic & trace traffic generator for NoC benchmarking.

Supports:
  - Patterns: uniform, transpose, bit_complement, hotspot
  - Configurable injection rates (0.0 to 1.0 packets/tile/cycle)
  - Configurable packet lengths (single-flit or multi-flit wormhole packets)
  - Reproducible random seeds
  - Outputs structured JSON trace format
"""

import argparse
import json
import random
import sys


def parse_args():
    parser = argparse.ArgumentParser(description="Generate NoC traffic traces.")
    parser.add_argument("--pattern", choices=["uniform", "transpose", "bit_complement", "hotspot"],
                        default="uniform", help="Traffic distribution pattern")
    parser.add_argument("--rate", type=float, default=0.2,
                        help="Injection rate per tile per cycle (0.0 - 1.0)")
    parser.add_argument("--cycles", type=int, default=500,
                        help="Simulation cycles to generate trace for")
    parser.add_argument("--seed", type=int, default=42,
                        help="Random seed for reproducibility")
    parser.add_argument("--mesh_w", type=int, default=3, help="Mesh width (X)")
    parser.add_argument("--mesh_h", type=int, default=3, help="Mesh height (Y)")
    parser.add_argument("--pkt_len", type=int, default=1,
                        help="Packet length in flits (1=single, >1=wormhole)")
    parser.add_argument("--hotspot_tile", type=int, default=4,
                        help="Hotspot tile index (default: center tile 4)")
    parser.add_argument("--out", type=str, default="results/trace.json",
                        help="Output JSON file path")
    return parser.parse_args()


def get_destination(pattern, src_tile, mesh_w, mesh_h, hotspot_tile, rng):
    num_tiles = mesh_w * mesh_h
    src_x = src_tile % mesh_w
    src_y = src_tile // mesh_w

    if pattern == "uniform":
        candidates = [t for t in range(num_tiles) if t != src_tile]
        return rng.choice(candidates)

    elif pattern == "transpose":
        dst_x = src_y
        dst_y = src_x
        # Clamp if mesh is non-square
        dst_x = min(dst_x, mesh_w - 1)
        dst_y = min(dst_y, mesh_h - 1)
        dst_tile = dst_y * mesh_w + dst_x
        if dst_tile == src_tile:
            candidates = [t for t in range(num_tiles) if t != src_tile]
            return rng.choice(candidates)
        return dst_tile

    elif pattern == "bit_complement":
        dst_x = (mesh_w - 1) - src_x
        dst_y = (mesh_h - 1) - src_y
        dst_tile = dst_y * mesh_w + dst_x
        if dst_tile == src_tile:
            candidates = [t for t in range(num_tiles) if t != src_tile]
            return rng.choice(candidates)
        return dst_tile

    elif pattern == "hotspot":
        if src_tile != hotspot_tile and rng.random() < 0.70:
            return hotspot_tile
        else:
            candidates = [t for t in range(num_tiles) if t != src_tile]
            return rng.choice(candidates)

    return (src_tile + 1) % num_tiles


def main():
    args = parse_args()
    rng = random.Random(args.seed)
    num_tiles = args.mesh_w * args.mesh_h

    packets = []
    pkt_id = 0

    for cycle in range(args.cycles):
        for src_tile in range(num_tiles):
            if rng.random() < args.rate:
                dst_tile = get_destination(args.pattern, src_tile, args.mesh_w, args.mesh_h,
                                           args.hotspot_tile, rng)
                src_x = src_tile % args.mesh_w
                src_y = src_tile // args.mesh_w
                dst_x = dst_tile % args.mesh_w
                dst_y = dst_tile // args.mesh_w

                pkt = {
                    "pkt_id": pkt_id,
                    "cycle": cycle,
                    "src_tile": src_tile,
                    "dst_tile": dst_tile,
                    "src_x": src_x,
                    "src_y": src_y,
                    "dest_x": dst_x,
                    "dest_y": dst_y,
                    "num_flits": args.pkt_len,
                    "payload": pkt_id & 0x3FFF  # 14-bit payload
                }
                packets.append(pkt)
                pkt_id += 1

    trace_data = {
        "config": {
            "pattern": args.pattern,
            "rate": args.rate,
            "cycles": args.cycles,
            "seed": args.seed,
            "mesh_w": args.mesh_w,
            "mesh_h": args.mesh_h,
            "pkt_len": args.pkt_len,
            "hotspot_tile": args.hotspot_tile,
            "total_packets": len(packets)
        },
        "packets": packets
    }

    with open(args.out, "w") as f:
        json.dump(trace_data, f, indent=2)

    print(f"Generated trace: {args.out}")
    print(f"  Pattern: {args.pattern}, Rate: {args.rate}, Seed: {args.seed}")
    print(f"  Cycles: {args.cycles}, Packets: {len(packets)}, Flits/pkt: {args.pkt_len}")


if __name__ == "__main__":
    main()

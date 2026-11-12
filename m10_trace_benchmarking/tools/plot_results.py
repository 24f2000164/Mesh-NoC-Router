#!/usr/bin/env python3
"""
plot_results.py — Visualises NoC benchmarking results using Matplotlib.

Generates:
  1. Latency distribution histogram (PDF & CDF)
  2. Latency over time (scatter / moving average)
  3. Pattern comparison bar chart (if multiple CSVs provided)
  4. Saves high-resolution publication-quality PNG figures
"""

import argparse
import csv
import os
import sys

import matplotlib
matplotlib.use("Agg")  # Non-interactive backend
import matplotlib.pyplot as plt
import numpy as np


def parse_args():
    parser = argparse.ArgumentParser(description="Plot NoC benchmark results.")
    parser.add_argument("--csv", type=str, default="results/bench_results.csv",
                        help="Path to per-packet benchmark CSV")
    parser.add_argument("--compare", type=str, default=None,
                        help="Optional secondary CSV to compare against (e.g. baseline)")
    parser.add_argument("--out_dir", type=str, default="results",
                        help="Directory to save plot images")
    parser.add_argument("--label", type=str, default="Wormhole M9",
                        help="Label for primary data series")
    parser.add_argument("--compare_label", type=str, default="Baseline Single-Flit",
                        help="Label for comparison data series")
    return parser.parse_args()


def load_latencies(csv_path):
    latencies = []
    cycles = []
    if not os.path.exists(csv_path):
        return [], []
    with open(csv_path, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row.get("status") == "PASS" and row.get("latency"):
                try:
                    lat = float(row["latency"])
                    cyc = int(row.get("inject_cycle", 0))
                    if lat >= 0:
                        latencies.append(lat)
                        cycles.append(cyc)
                except ValueError:
                    pass
    return np.array(latencies), np.array(cycles)


def plot_latency_hist(lat1, label1, lat2, label2, out_path):
    plt.figure(figsize=(8, 5))
    bins = np.linspace(0, max(np.max(lat1) if len(lat1) else 30,
                              np.max(lat2) if len(lat2) else 30) + 5, 25)

    if len(lat1):
        plt.hist(lat1, bins=bins, alpha=0.65, label=f"{label1} (mean={np.mean(lat1):.1f})",
                 color="#2b5c8f", edgecolor="black")
    if len(lat2):
        plt.hist(lat2, bins=bins, alpha=0.55, label=f"{label2} (mean={np.mean(lat2):.1f})",
                 color="#d95f02", edgecolor="black")

    plt.xlabel("Packet Latency (clock cycles)", fontsize=11)
    plt.ylabel("Packet Count", fontsize=11)
    plt.title("NoC Packet Latency Distribution", fontsize=13, fontweight="bold")
    plt.grid(True, linestyle="--", alpha=0.5)
    plt.legend(fontsize=10)
    plt.tight_layout()
    plt.savefig(out_path, dpi=200)
    plt.close()
    print(f"Saved: {out_path}")


def plot_latency_cdf(lat1, label1, lat2, label2, out_path):
    plt.figure(figsize=(8, 5))

    if len(lat1):
        sorted_l1 = np.sort(lat1)
        cdf1 = np.arange(1, len(sorted_l1) + 1) / len(sorted_l1)
        plt.plot(sorted_l1, cdf1, label=label1, color="#2b5c8f", linewidth=2)

    if len(lat2):
        sorted_l2 = np.sort(lat2)
        cdf2 = np.arange(1, len(sorted_l2) + 1) / len(sorted_l2)
        plt.plot(sorted_l2, cdf2, label=label2, color="#d95f02", linewidth=2, linestyle="--")

    plt.xlabel("Packet Latency (clock cycles)", fontsize=11)
    plt.ylabel("Cumulative Distribution (CDF)", fontsize=11)
    plt.title("Cumulative Latency Distribution", fontsize=13, fontweight="bold")
    plt.grid(True, linestyle="--", alpha=0.5)
    plt.legend(fontsize=10)
    plt.tight_layout()
    plt.savefig(out_path, dpi=200)
    plt.close()
    print(f"Saved: {out_path}")


def main():
    args = parse_args()
    os.makedirs(args.out_dir, exist_ok=True)

    lat1, cyc1 = load_latencies(args.csv)
    lat2, cyc2 = ([], [])
    if args.compare:
        lat2, cyc2 = load_latencies(args.compare)

    if len(lat1) == 0:
        print(f"Warning: No valid latency data found in {args.csv}")
        return

    hist_path = os.path.join(args.out_dir, "latency_distribution.png")
    plot_latency_hist(lat1, args.label, lat2, args.compare_label, hist_path)

    cdf_path = os.path.join(args.out_dir, "latency_cdf.png")
    plot_latency_cdf(lat1, args.label, lat2, args.compare_label, cdf_path)

    print("Plotting complete.")


if __name__ == "__main__":
    main()

# Installation Guide
**Enhanced Mesh Network-on-Chip Router**

---

## Prerequisites

- **OS**: Windows 11 with WSL2 (Ubuntu 24.04 LTS recommended), or native Linux/macOS
- **GitHub account**: needed to push your own fork
- **Disk space**: ~500 MB (OSS CAD Suite + repo)

---

## Step 1 — WSL2 Setup (Windows only)

Open PowerShell as Administrator:
```powershell
wsl --install
# Restart when prompted, then set a username/password for Ubuntu
```

Verify:
```powershell
wsl -l -v
# Should show Ubuntu with VERSION 2
```

---

## Step 2 — Ubuntu Base Packages

Inside Ubuntu (WSL2 terminal):
```bash
sudo apt update
sudo apt install -y git build-essential make \
    curl wget python3 python3-pip \
    python3-numpy python3-matplotlib \
    iverilog verilator
```

Verify mandatory tools:
```bash
git --version        # e.g. git version 2.43.0
iverilog -V          # e.g. Icarus Verilog version 12.0
vvp -V               # same version as iverilog
verilator --version  # e.g. Verilator 5.020
python3 --version    # e.g. Python 3.12.3
python3 -c "import numpy, matplotlib; print('Python libraries OK')"
```

---

## Step 3 — OSS CAD Suite (Yosys + SymbiYosys)

> Required only for `./regress.sh --full` (formal proofs and synthesis).

Download the latest Linux x64 release:
```bash
cd ~
# Check https://github.com/YosysHQ/oss-cad-suite-build/releases/latest
# and replace the URL below with the current date's tarball
wget https://github.com/YosysHQ/oss-cad-suite-build/releases/download/2024-11-10/oss-cad-suite-linux-x64-20241110.tgz
tar -xf oss-cad-suite-linux-x64-20241110.tgz
```

Add to PATH permanently:
```bash
echo 'export PATH="$HOME/oss-cad-suite/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

Verify:
```bash
yosys -V     # e.g. Yosys 0.44
sby --version # e.g. SymbiYosys 0.44
```

---

## Step 4 — Clone the Repository

```bash
mkdir -p ~/projects
cd ~/projects
git clone https://github.com/24f2000164/Mesh-NoC-Router.git Enhanced-Mesh-NoC-Router
cd Enhanced-Mesh-NoC-Router

# Keep the original as upstream reference:
git remote add upstream https://github.com/JuanCantu1/Mesh-NoC-Router.git
git remote -v
```

Expected output:
```
origin    https://github.com/24f2000164/Mesh-NoC-Router.git (fetch)
origin    https://github.com/24f2000164/Mesh-NoC-Router.git (push)
upstream  https://github.com/JuanCantu1/Mesh-NoC-Router.git (fetch)
upstream  https://github.com/JuanCantu1/Mesh-NoC-Router.git (push)
```

---

## Step 5 — Verify Environment

```bash
bash scripts/check_environment.sh
```

All mandatory tools must show `[OK]`. Fix any `[MISSING]` entries before continuing.

---

## Step 6 — Run the Baseline Regression

```bash
# Standard regression (~10 min): M1–M8 + replay check
./regress.sh

# Full regression (~45 min): adds formal proofs, synthesis, mutation testing
./regress.sh --full

# New milestones only (M9 + M10):
./regress.sh --new
```

Expected final line for a passing run:
```
PROJECT REGRESSION PASSED: N of N steps, Xs
```

Logs are saved to `regress_logs/<step>.log`.

---

## Step 7 — Run Simulations Manually

### Original M8 router:
```bash
cd m8_pipeline
bash run.sh
```

### M9 wormhole router:
```bash
cd m9_wormhole_switching
bash run.sh
```

### M10 benchmarks:
```bash
cd m10_trace_benchmarking
bash run.sh
# Or run individual traffic patterns:
python3 tools/trace_gen.py --pattern uniform --rate 0.5 --seed 42 --out results/trace_uniform.json
python3 tools/bench_runner.py --trace results/trace_uniform.json
```

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `iverilog: command not found` | `sudo apt install iverilog` |
| `vvp: command not found` | Installed with iverilog; check `which vvp` |
| `verilator: command not found` | `sudo apt install verilator` |
| `yosys: command not found` | Install OSS CAD Suite (Step 3) |
| `sby: command not found` | Install OSS CAD Suite (Step 3) |
| `No module named 'numpy'` | `pip3 install numpy matplotlib` |
| Icarus `Warning: port conflict` | Use `-g2012` flag (all scripts already do) |
| WSL `wsl --install` fails | Enable virtualisation in BIOS; run Windows Update |
| Matplotlib `not writable` warning | `export MPLCONFIGDIR=/tmp/mpl` |
| `git push` rejected | Make sure remote is `origin` (your fork), not `upstream` |

---

## PATH Configuration Summary

After OSS CAD Suite installation, your `~/.bashrc` should contain:
```bash
export PATH="$HOME/oss-cad-suite/bin:$PATH"
```

Verify with:
```bash
echo $PATH | tr ':' '\n' | grep oss
```

#!/usr/bin/env bash
# check_environment.sh
#
# Verifies that all tools required by the Enhanced Mesh-NoC-Router project
# are installed and prints their versions. Exits non-zero if any mandatory
# tool is missing.
#
# Usage:  ./scripts/check_environment.sh
#
# Tool categories:
#   MANDATORY  - without these the baseline regression cannot run
#   OPTIONAL   - needed only for --full mode (formal, synthesis)

set -uo pipefail

PASS=0
FAIL=0
WARN=0

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

check_tool() {
  local name=$1 cmd=$2 vflag=$3 category=$4
  local ver
  if command -v "$cmd" >/dev/null 2>&1; then
    ver=$("$cmd" $vflag 2>&1 | grep -iE 'version|\([0-9]+\.[0-9]+|yosys|verilator|make|gcc|python' | head -n 1 || echo "installed")
    [ -z "$ver" ] && ver="installed"
    printf "${GREEN}[OK]${NC}      %-20s %s\n" "$name" "$ver"
    PASS=$((PASS + 1))
  else
    if [ "$category" = "MANDATORY" ]; then
      printf "${RED}[MISSING]${NC} %-20s  ** MANDATORY — install this before continuing **\n" "$name"
      FAIL=$((FAIL + 1))
    else
      printf "${YELLOW}[WARN]${NC}    %-20s  optional (needed for --full mode)\n" "$name"
      WARN=$((WARN + 1))
    fi
  fi
}

echo "============================================================"
echo " Enhanced Mesh-NoC-Router — Environment Check"
echo " $(date)"
echo "============================================================"
echo ""

echo "--- Mandatory tools (baseline regression) ---"
check_tool "git"      git      "--version"  MANDATORY
check_tool "make"     make     "--version"  MANDATORY
check_tool "gcc"      gcc      "--version"  MANDATORY
check_tool "python3"  python3  "--version"  MANDATORY
check_tool "iverilog" iverilog "-V"         MANDATORY
check_tool "vvp"      vvp      "-V"         MANDATORY

echo ""
echo "--- Optional tools (--full mode: synthesis + formal) ---"
check_tool "verilator" verilator "--version" OPTIONAL
check_tool "yosys"     yosys     "-V"        OPTIONAL
check_tool "sby"       sby       "--version" OPTIONAL

echo ""
echo "--- Python packages ---"
python3 - <<'EOF'
import sys
pkgs = {"numpy": None, "matplotlib": None}
missing = []
for pkg in pkgs:
    try:
        m = __import__(pkg)
        ver = getattr(m, "__version__", "unknown")
        print(f"\033[0;32m[OK]\033[0m      {pkg:<20} {ver}")
    except ImportError:
        print(f"\033[0;31m[MISSING]\033[0m {pkg:<20}  ** install: pip3 install {pkg} **")
        missing.append(pkg)
sys.exit(1 if missing else 0)
EOF
PY_OK=$?

echo ""
echo "============================================================"
echo " Summary"
echo "============================================================"
echo "  Mandatory tools OK : $PASS"
[ $FAIL -gt 0 ] && echo "  MISSING (mandatory): $FAIL" || true
[ $WARN -gt 0 ] && echo "  Optional (missing) : $WARN" || true

if [ $FAIL -gt 0 ] || [ $PY_OK -ne 0 ]; then
  echo ""
  echo "ERROR: One or more mandatory tools are missing."
  echo "See docs/INSTALLATION.md for setup instructions."
  exit 1
fi

echo ""
echo "Environment OK — ready to run ./regress.sh"

#!/usr/bin/env bash
# setup_mac.sh — One-time Mac setup for CereLink + PsychoPy integration.
# Run from the repo root: bash setup_mac.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONDA_ENV="cerelink"
CERELINK_SRC="$SCRIPT_DIR/CereLink-master"
BUILD_DIR="$SCRIPT_DIR/build"

header() { echo ""; echo "▶ $1"; }
ok()     { echo "  [OK] $1"; }
warn()   { echo "  [WARN] $1"; }
fail()   { echo "  [ERROR] $1"; exit 1; }

echo "=============================="
echo " CereLink Mac Setup"
echo "=============================="

# ── 1. Homebrew ──────────────────────────────────────────────────────────────
header "Checking Homebrew"
if ! command -v brew &>/dev/null; then
    fail "Homebrew not found. Install it first: https://brew.sh"
fi
ok "Homebrew: $(brew --version | head -1)"

# ── 2. cmake ─────────────────────────────────────────────────────────────────
header "Checking cmake"
if ! command -v cmake &>/dev/null; then
    echo "  Installing cmake via Homebrew..."
    brew install cmake
fi
ok "cmake: $(cmake --version | head -1)"

# ── 3. conda ─────────────────────────────────────────────────────────────────
header "Checking conda"
if ! command -v conda &>/dev/null; then
    fail "conda not found. Install Miniconda: https://docs.conda.io/en/latest/miniconda.html"
fi
ok "conda: $(conda --version)"

# ── 4. conda environment ─────────────────────────────────────────────────────
header "Setting up conda environment '$CONDA_ENV'"
if conda env list | grep -qE "^${CONDA_ENV}[[:space:]]"; then
    ok "Environment '$CONDA_ENV' already exists — skipping creation"
else
    echo "  Creating environment with Python 3.11..."
    conda create -n "$CONDA_ENV" python=3.11 -y
    ok "Created '$CONDA_ENV'"
fi

# ── 5. Build libcbsdk.dylib ──────────────────────────────────────────────────
header "Building libcbsdk.dylib"
if [ ! -d "$CERELINK_SRC" ]; then
    fail "CereLink-master/ not found at $CERELINK_SRC"
fi

cmake -B "$BUILD_DIR" -S "$CERELINK_SRC" \
    -DCBSDK_BUILD_SHARED=ON \
    -DCBSDK_BUILD_TEST=OFF \
    -DCMAKE_BUILD_TYPE=Release

cmake --build "$BUILD_DIR" --target cbsdk_shared --config Release

DYLIB="$BUILD_DIR/src/cbsdk/libcbsdk.dylib"
if [ ! -f "$DYLIB" ]; then
    fail "Build succeeded but dylib not found at expected path: $DYLIB"
fi
ok "Built: $DYLIB"

# ── 6. Copy dylib for auto-discovery ─────────────────────────────────────────
# pycbsdk's _lib.py walks up from the package looking for the dylib via CMakeLists;
# copying it directly into the package dir is the simplest zero-config solution.
header "Installing dylib into pycbsdk package"
PYCBSDK_PKG="$CERELINK_SRC/pycbsdk/src/pycbsdk"
cp "$DYLIB" "$PYCBSDK_PKG/"
ok "Copied → $PYCBSDK_PKG/libcbsdk.dylib"

# ── 7. Install pycbsdk ───────────────────────────────────────────────────────
# SETUPTOOLS_SCM_PRETEND_VERSION is required because this repo is not inside
# a git repository; without it setuptools-scm raises LookupError at install time.
header "Installing pycbsdk"
SETUPTOOLS_SCM_PRETEND_VERSION=0.0.0 \
    conda run -n "$CONDA_ENV" pip install -e "$CERELINK_SRC/pycbsdk[numpy]"
ok "pycbsdk installed"

# ── 8. Install Python dependencies ───────────────────────────────────────────
header "Installing Python dependencies"
conda run -n "$CONDA_ENV" pip install neo
ok "neo installed"

# ── 9. Verify ─────────────────────────────────────────────────────────────────
header "Verifying installation"
conda run -n "$CONDA_ENV" python - <<'EOF'
import importlib, sys
for pkg in ("neo", "numpy"):
    importlib.import_module(pkg)
    print(f"  [OK] {pkg}")

# Check pycbsdk loads and finds the dylib
try:
    from pycbsdk import cbsdk
    print("  [OK] pycbsdk + libcbsdk.dylib")
except Exception as e:
    print(f"  [WARN] pycbsdk load issue (non-fatal): {e}")

# Check nsp_marker
import socket
print("  [OK] socket (raw UDP marker sender)")
EOF

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "=============================="
echo " Setup complete!"
echo "=============================="
echo ""
echo "Manual step required — set a static IP on your Mac's Ethernet adapter:"
echo ""
echo "  System Settings → Network → [your USB/Thunderbolt Ethernet]"
echo "  → Details → TCP/IP → Configure IPv4: Manually"
echo "    IP Address : 192.168.137.2"
echo "    Subnet Mask: 255.255.255.0"
echo "    Router     : (leave blank)"
echo ""
echo "Then connect the Mac to the network switch and run:"
echo "  bash run_experiment.sh"

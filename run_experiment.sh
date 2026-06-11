#!/usr/bin/env bash
# run_experiment.sh — Pre-flight check. Run this before every experiment session.
#
# Checks:
#   1. NSP reachable at 192.168.137.128 (listens for NSP heartbeat packets)
#   2. SMB share mounted (or attempts to mount it)
#   3. Injects 3 test comment markers and confirms no errors
#
# Usage:
#   bash run_experiment.sh
#   bash run_experiment.sh --dry-run    # skip actual UDP sends

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONDA_ENV="cerelink"
NSP_IP="192.168.137.128"
WINDOWS_IP="192.168.50.1"
SHARE_NAME="blackrock"
MOUNT_POINT="/Volumes/blackrock"
DRY_RUN="${1:-}"

PASS=0
FAIL=0

ok()   { echo "  [PASS] $1"; ((PASS++)) || true; }
fail() { echo "  [FAIL] $1"; ((FAIL++)) || true; }
info() { echo "  $1"; }

echo ""
echo "=============================="
echo " CereLink Pre-flight Check"
echo " $(date '+%Y-%m-%d %H:%M:%S')"
echo "=============================="

# ── 1. NSP connectivity ───────────────────────────────────────────────────────
echo ""
echo "▶ NSP ($NSP_IP)"

NSP_RESULT=$(conda run -n "$CONDA_ENV" python - <<EOF
import sys
sys.path.insert(0, "$SCRIPT_DIR")
from nsp_marker import test_connection
ok = test_connection(nsp_ip="$NSP_IP")
sys.exit(0 if ok else 1)
EOF
) && NSP_OK=true || NSP_OK=false

if $NSP_OK; then
    ok "NSP reachable — heartbeat received"
else
    fail "NSP not reachable — check Ethernet connection and Mac IP (should be 192.168.137.2/24)"
fi

# ── 2. SMB share ─────────────────────────────────────────────────────────────
echo ""
echo "▶ SMB share (smb://$WINDOWS_IP/$SHARE_NAME)"

if mount | grep -q "$MOUNT_POINT"; then
    ok "Share already mounted at $MOUNT_POINT"
else
    info "Not mounted — attempting to mount..."
    if osascript -e "mount volume \"smb://$WINDOWS_IP/$SHARE_NAME\"" 2>/dev/null; then
        sleep 2
        if mount | grep -q "$MOUNT_POINT"; then
            ok "Mounted at $MOUNT_POINT"
        else
            fail "Mount command succeeded but $MOUNT_POINT not found"
        fi
    else
        fail "Could not mount smb://$WINDOWS_IP/$SHARE_NAME"
        info "Manual fix: Finder → Go → Connect to Server → smb://$WINDOWS_IP/$SHARE_NAME"
        info "           Make sure setup_windows.ps1 has been run on the PC."
    fi
fi

# ── 3. Test marker injection ──────────────────────────────────────────────────
echo ""
echo "▶ Comment marker injection"

if [ "$DRY_RUN" = "--dry-run" ]; then
    info "(dry-run — no UDP packets sent)"
    ok "Dry run: marker build OK"
else
    MARKER_RESULT=$(conda run -n "$CONDA_ENV" python - 2>&1 <<EOF
import sys, time
sys.path.insert(0, "$SCRIPT_DIR")
from nsp_marker import NSPMarker

with NSPMarker(nsp_ip="$NSP_IP") as m:
    m.send("preflight_1")
    time.sleep(1)
    m.send("preflight_2", rgba=0xFF0000FF)
    time.sleep(1)
    m.send("preflight_3", rgba=0x00FF00FF)

print("sent 3 markers")
EOF
    ) && MARKER_OK=true || MARKER_OK=false

    if $MARKER_OK; then
        ok "Sent 3 test markers to NSP (preflight_1, preflight_2, preflight_3)"
        info "You should see them in Central's raster plot."
    else
        fail "Marker injection failed: $MARKER_RESULT"
    fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "=============================="
TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then
    echo " READY ($PASS/$TOTAL checks passed)"
else
    echo " NOT READY ($FAIL/$TOTAL checks FAILED — see above)"
fi
echo "=============================="
echo ""

if [ "$FAIL" -eq 0 ]; then
    echo "All systems go. Import NSPMarker in your experiment:"
    echo ""
    echo "  from nsp_marker import NSPMarker"
    echo "  marker = NSPMarker()"
    echo "  marker.send('trial_start')"
    echo "  marker.send('stimulus_on', rgba=0xFF0000FF)"
    echo ""
    echo "Recorded data will be saved to $MOUNT_POINT/"
    exit 0
else
    exit 1
fi

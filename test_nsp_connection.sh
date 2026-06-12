#!/usr/bin/env bash
# test_nsp_connection.sh — Pre-flight check. Run before every experiment session.
#
# Checks:
#   1. Mac has a 192.168.137.x IP on the lab Ethernet
#   2. NSP responds to ping
#   3. NSP UDP heartbeat received
#   4. Injects a "TEST" comment and prompts user to confirm it appears in Central
#
# Usage:
#   bash test_nsp_connection.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONDA_ENV="cerelink"
NSP_IP="192.168.137.128"

PASS=0
FAIL=0

ok()   { echo "  [PASS] $1"; ((PASS++)) || true; }
fail() { echo "  [FAIL] $1"; ((FAIL++)) || true; }
info() { echo "         $1"; }

echo ""
echo "=============================="
echo " nsp-marker-mac: Pre-flight Check"
echo " $(date '+%Y-%m-%d %H:%M:%S')"
echo "=============================="

# ── 0. Mac network config ─────────────────────────────────────────────────────
# The Mac must have a 192.168.137.x IP on the lab Ethernet to talk to the NSP.
# We pass this IP as the bind address for the UDP test so we only hear packets
# from the lab interface — not from other campus WiFi interfaces that might
# reach a different NSP on a shared university subnet.
echo ""
echo "▶ Mac network config"
MAC_NSP_IP=$(ifconfig 2>/dev/null | awk '/inet 192\.168\.137\./{print $2}' | head -1)
if [ -n "$MAC_NSP_IP" ]; then
    ok "Mac has NSP-subnet IP: $MAC_NSP_IP"
else
    fail "Mac has no 192.168.137.x IP — lab Ethernet not configured"
    info "Set a static IP: System Settings → Network → [USB Ethernet]"
    info "  IP: 192.168.137.2  Subnet: 255.255.255.0  Router: (blank)"
    MAC_NSP_IP=""
fi

# ── 1. Ping NSP ───────────────────────────────────────────────────────────────
# Advisory only — NSPs commonly ignore ICMP. The UDP heartbeat (step 2) is the
# real connectivity test; a ping failure here does not block READY status.
echo ""
echo "▶ NSP ping ($NSP_IP)"
if ping -c 1 -W 1000 "$NSP_IP" &>/dev/null; then
    ok "NSP responds to ping"
else
    echo "  [WARN] NSP did not respond to ping (normal — most NSPs ignore ICMP)"
    info "         UDP heartbeat check below is the authoritative test"
fi

# ── 2. NSP UDP heartbeat ──────────────────────────────────────────────────────
# We bind to the Mac's 192.168.137.x IP specifically so we only hear packets
# arriving on the lab Ethernet — not from campus WiFi, which may reach other
# NSPs on the same campus or building network that share the same 192.168.137.x subnet.
echo ""
echo "▶ NSP UDP heartbeat"
if [ -z "$MAC_NSP_IP" ]; then
    fail "Skipped — Mac has no 192.168.137.x IP (fix step 0 first)"
else
    _TMP_UDP=$(mktemp /tmp/nsp_udp_XXXX)
    cat > "$_TMP_UDP" <<EOF
import sys
sys.path.insert(0, "$SCRIPT_DIR")
from nsp_marker import test_connection
ok = test_connection(nsp_ip="$NSP_IP", bind_ip="$MAC_NSP_IP")
sys.exit(0 if ok else 1)
EOF
    conda run -n "$CONDA_ENV" python "$_TMP_UDP" 2>&1 && UDP_OK=true || UDP_OK=false
    rm -f "$_TMP_UDP"

    if $UDP_OK; then
        ok "NSP UDP heartbeat received from $NSP_IP"
    else
        fail "No UDP heartbeat from $NSP_IP"
        info "Central may not be running, or NSP is not powered on"
    fi
fi

# ── 3. Inject TEST comment ────────────────────────────────────────────────────
# Note: UDP send() always returns immediately without error even if the NSP is
# unreachable — delivery cannot be confirmed in software. The user confirmation
# below is the real end-to-end test.
echo ""
echo "▶ Sending TEST comment"
_TMP_SEND=$(mktemp /tmp/nsp_send_XXXX)
cat > "$_TMP_SEND" <<EOF
import sys
sys.path.insert(0, "$SCRIPT_DIR")
from nsp_marker import NSPMarker
with NSPMarker(nsp_ip="$NSP_IP") as m:
    m.send("TEST", rgba=0x00FF0000)
EOF
conda run -n "$CONDA_ENV" python "$_TMP_SEND" 2>/dev/null
rm -f "$_TMP_SEND"
echo "  [SENT] 'TEST' comment dispatched (UDP — delivery unconfirmed)"

# ── 4. User confirmation ──────────────────────────────────────────────────────
echo ""
echo "  ► Check Central now — does a 'TEST' comment appear in the raster plot?"
echo ""
printf "    Visible in Central? [y/n] "
read -r CONFIRM
echo ""
if [[ "$CONFIRM" =~ ^[Yy] ]]; then
    ok "TEST comment confirmed in Central — end-to-end marker injection working"
else
    fail "TEST comment not seen in Central"
    info "Marker was dispatched but not confirmed received."
    info "Make sure Central is running and recording (or at least in live view)."
    info "Comments sometimes only appear once a recording is started."
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "=============================="
TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then
    echo " ✓ READY  ($PASS/$TOTAL checks passed)"
    echo "=============================="
    echo ""
    echo "  from nsp_marker import NSPMarker"
    echo "  marker = NSPMarker()"
    echo "  marker.send('trial_start')"
    echo ""
    echo "  To access recorded data: bash transfer_data.sh"
else
    echo " ✗ NOT READY  ($FAIL/$TOTAL checks failed — see above)"
    echo "=============================="
fi
echo ""

[ "$FAIL" -eq 0 ]

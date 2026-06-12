#!/usr/bin/env bash
# transfer_data.sh — Mount the Blackrock data share from the Central PC.
#
# Mounts smb://192.168.50.1/blackrock at /Volumes/blackrock so you can
# browse, copy, or read NEV files directly from the Mac.
#
# Usage:
#   bash transfer_data.sh          # mount and open in Finder
#   bash transfer_data.sh --read   # mount and launch the NEV file reader

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONDA_ENV="cerelink"
WINDOWS_IP="192.168.50.1"
SHARE_NAME="blackrock"
MOUNT_POINT="/Volumes/blackrock"
MODE="${1:-}"

echo ""
echo "=============================="
echo " nsp-marker: Data Transfer"
echo " $(date '+%Y-%m-%d %H:%M:%S')"
echo "=============================="
echo ""

# ── 1. Ensure Mac has a 192.168.50.x IP to reach the PC ──────────────────────
echo "▶ Mac network config (192.168.50.x alias)"
if ifconfig 2>/dev/null | grep -q "inet 192\.168\.50\."; then
    echo "  [OK] 192.168.50.x alias already configured"
else
    # Find the interface that has the lab Ethernet (192.168.137.x)
    LAB_IFACE=$(ifconfig 2>/dev/null | awk '/^[a-z][^ ]*:/{iface=$1} /inet 192\.168\.137\./{gsub(/:$/,"",iface); print iface}' | head -1)
    if [ -z "$LAB_IFACE" ]; then
        echo "  [FAIL] Could not find lab Ethernet interface (no 192.168.137.x IP)"
        echo "         Plug in the Ethernet cable and set a static IP first."
        exit 1
    fi
    echo "  Adding 192.168.50.2 alias to $LAB_IFACE (requires sudo)..."
    if sudo ifconfig "$LAB_IFACE" alias 192.168.50.2 255.255.255.0; then
        echo "  [OK] Alias 192.168.50.2 added to $LAB_IFACE (temporary — gone after reboot)"
    else
        echo "  [FAIL] Could not add alias — try manually:"
        echo "         sudo ifconfig $LAB_IFACE alias 192.168.50.2 255.255.255.0"
        exit 1
    fi
fi

# ── 2. Check PC reachable (SMB port 445) ─────────────────────────────────────
# Ping is blocked by Windows Firewall by default — check TCP port 445 instead.
echo ""
echo "▶ Central PC ($WINDOWS_IP port 445)"
if nc -z -w 2 "$WINDOWS_IP" 445 2>/dev/null; then
    echo "  [OK] Central PC reachable (SMB port 445 open)"
elif ping -c 1 -W 1000 "$WINDOWS_IP" &>/dev/null; then
    echo "  [OK] Central PC reachable (ping) — port 445 closed, check Windows file sharing"
else
    echo "  [FAIL] Central PC not reachable at $WINDOWS_IP"
    echo "         Check: PC is on, NIC 2 is set to 192.168.50.1/24, connected to switch"
    echo "         Check: Windows file sharing is enabled (Control Panel → Network → Sharing)"
    exit 1
fi

# ── 3. Mount share if not already mounted ────────────────────────────────────
echo ""
echo "▶ SMB share (smb://$WINDOWS_IP/$SHARE_NAME)"
if mount | grep -q "$MOUNT_POINT"; then
    echo "  [OK] Already mounted at $MOUNT_POINT"
else
    echo "  Mounting..."
    # osascript uses macOS Keychain for stored credentials — no password in script.
    # On first use, macOS will prompt for Windows username + password and offer to
    # save them to Keychain so future mounts are silent.
    if osascript -e "mount volume \"smb://$WINDOWS_IP/$SHARE_NAME\"" 2>/dev/null; then
        sleep 2
        if mount | grep -q "$MOUNT_POINT"; then
            echo "  [OK] Mounted at $MOUNT_POINT"
        else
            echo "  [FAIL] Mount command ran but $MOUNT_POINT not found."
            echo "         Try manually: Finder → Go → Connect to Server → smb://$WINDOWS_IP/$SHARE_NAME"
            exit 1
        fi
    else
        echo "  [FAIL] Could not mount share."
        echo "         Try manually: Finder → Go → Connect to Server → smb://$WINDOWS_IP/$SHARE_NAME"
        echo "         Make sure setup_windows.ps1 has been run and a Windows password is set."
        exit 1
    fi
fi

# ── 4. List recent sessions ───────────────────────────────────────────────────
echo ""
echo "▶ Recent recordings in $MOUNT_POINT"
SESSIONS=$(find "$MOUNT_POINT" -name "*.nev" 2>/dev/null | sort -r | head -10)
if [ -z "$SESSIONS" ]; then
    echo "  No .nev files found yet."
else
    echo "$SESSIONS" | while IFS= read -r f; do
        echo "  $(stat -f '%Sm  %N' -t '%Y-%m-%d %H:%M' "$f" 2>/dev/null || echo "$f")"
    done
fi

# ── 5. Open Finder or NEV reader ──────────────────────────────────────────────
echo ""
if [ "$MODE" = "--read" ]; then
    echo "Launching NEV file reader..."
    conda run -n "$CONDA_ENV" python "$SCRIPT_DIR/read_nev.py"
else
    open "$MOUNT_POINT"
    echo "Opened $MOUNT_POINT in Finder."
    echo ""
    echo "  To read a NEV file directly: bash transfer_data.sh --read"
fi

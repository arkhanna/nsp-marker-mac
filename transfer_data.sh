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
echo " CereLink Data Transfer"
echo " $(date '+%Y-%m-%d %H:%M:%S')"
echo "=============================="
echo ""

# ── 1. Check PC reachable ─────────────────────────────────────────────────────
echo "▶ Central PC ($WINDOWS_IP)"
if ! ping -c 1 -W 1000 "$WINDOWS_IP" &>/dev/null; then
    echo "  [FAIL] Central PC not reachable at $WINDOWS_IP"
    echo "         Check that the PC is on and connected to the switch,"
    echo "         and that setup_windows.ps1 has been run."
    exit 1
fi
echo "  [OK] Central PC reachable"

# ── 2. Mount share if not already mounted ────────────────────────────────────
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

# ── 3. List recent sessions ───────────────────────────────────────────────────
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

# ── 4. Open Finder or NEV reader ──────────────────────────────────────────────
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

"""
NSP comment marker sender.

Sends cbPKT_COMMENT packets directly to the NSP via UDP, with no session
handshake. Works alongside Central running on Windows.

Usage:
    marker = NSPMarker()
    marker.send("trial_start")
    marker.send("stimulus_on", rgba=0xFF0000FF)  # red
    marker.close()

    # Or as a context manager:
    with NSPMarker() as marker:
        marker.send("trial_start")
"""

import socket
import struct
import time

# Protocol constants
_NSP_IP            = "192.168.137.128"
_NSP_PORT          = 51001
_CHAN_CONFIGURATION = 0x8000   # cbPKTCHAN_CONFIGURATION
_PKT_COMMENTSET    = 0x00B1   # cbPKTTYPE_COMMENTSET
_MAX_COMMENT       = 128
_DLEN_COMMENT      = 36       # (160 - 16) / 4  (body bytes / 4)


def _build_comment_packet(text: str, rgba: int = 0x00FF0000, charset: int = 0) -> bytes:
    """Build a cbPKT_COMMENT UDP payload (160 bytes, little-endian)."""
    comment_bytes = text.encode("ascii", errors="replace")[: _MAX_COMMENT - 1]
    comment_field = comment_bytes + b"\x00" * (_MAX_COMMENT - len(comment_bytes))

    # Header (16 bytes): time(Q) chid(H) type(H) dlen(H) instrument(B) reserved(B)
    header = struct.pack(
        "<QHHHBB",
        0,                    # time  — NSP stamps with its own clock
        _CHAN_CONFIGURATION,  # chid
        _PKT_COMMENTSET,      # type
        _DLEN_COMMENT,        # dlen
        0,                    # instrument
        0,                    # reserved
    )

    # Body (144 bytes): charset(B) reserved(BBB) timeStarted(Q) rgba(I) comment(128s)
    body = struct.pack("<BBBBQI", charset, 0, 0, 0, 0, rgba) + comment_field

    return header + body  # 160 bytes total


class NSPMarker:
    """Sends timestamped comment markers to the NSP over raw UDP.

    Args:
        nsp_ip:   IP of the NSP (default 192.168.137.128)
        nsp_port: UDP port (default 51001)
        dry_run:  If True, build packets but don't send (for testing)
    """

    def __init__(
        self,
        nsp_ip: str = _NSP_IP,
        nsp_port: int = _NSP_PORT,
        dry_run: bool = False,
    ):
        self.nsp_ip = nsp_ip
        self.nsp_port = nsp_port
        self.dry_run = dry_run
        self._sock: socket.socket | None = None
        if not dry_run:
            self._open_socket()

    def _open_socket(self):
        self._sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self._sock.connect((self.nsp_ip, self.nsp_port))

    def send(self, text: str, rgba: int = 0x00FF0000) -> None:
        """Send a comment marker to the NSP.

        Args:
            text: Marker string (max 127 ASCII chars; longer strings are truncated)
            rgba: colour value for Central. Central reads the uint32 as raw bytes
                  in R,G,B,A order with A=0x00 opaque, A=0xFF transparent.
                  Format: 0x00BBGGRR for opaque colours.
                  Default 0x00FF0000 = blue (R=0, G=0, B=255, A=0).
        """
        pkt = _build_comment_packet(text, rgba=rgba)
        if self.dry_run:
            print(f"[dry_run] would send {len(pkt)}-byte comment: {text!r}  rgba=0x{rgba:08X}")
        else:
            if self._sock is None:
                self._open_socket()
            self._sock.send(pkt)

    def close(self):
        if self._sock:
            self._sock.close()
            self._sock = None

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()


# ── quick connection test ──────────────────────────────────────────────────────

def test_connection(
    nsp_ip: str = _NSP_IP,
    nsp_port: int = _NSP_PORT,
    timeout: float = 2.0,
    bind_ip: str = "",
) -> bool:
    """Listen for a UDP heartbeat from the NSP.

    Binds to all interfaces and filters by source IP so we only accept
    packets that actually came from the NSP — not from other NSPs that
    might share the same subnet on campus WiFi.
    bind_ip is accepted for backwards compatibility but ignored.
    """
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
        s.settimeout(timeout)
        s.bind(("", nsp_port))
        deadline = time.monotonic() + timeout
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                break
            s.settimeout(remaining)
            data, addr = s.recvfrom(256)
            if addr[0] == nsp_ip:
                s.close()
                print(f"NSP reachable — got {len(data)}-byte heartbeat from {addr[0]}")
                return True
            # packet from wrong source or interface — keep waiting
        s.close()
        print(f"NSP not reachable — no heartbeat from {nsp_ip} within {timeout:.0f}s")
        return False
    except socket.timeout:
        print(f"NSP not reachable — no heartbeat from {nsp_ip} within {timeout:.0f}s")
        return False
    except Exception as e:
        print(f"NSP check failed: {e}")
        return False


if __name__ == "__main__":
    print("Testing NSP connection...")
    if test_connection():
        print("\nSending test markers...")
        with NSPMarker() as m:
            m.send("cerelink_test_1")
            time.sleep(0.1)
            m.send("cerelink_test_2")
            time.sleep(0.1)
            m.send("cerelink_test_3")
        print("Done — check Central for 3 comment events.")
    else:
        print("Skipping send (NSP unreachable).")

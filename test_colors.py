"""
Verify comment color encoding against Blackrock Central.

Central reads the rgba uint32 as raw bytes in R, G, B, A order (little-endian).
Alpha is inverted: A=0x00 is fully opaque, A=0xFF is fully transparent.
So the correct format for opaque colors is 0x00BBGGRR.

Run with Central recording active and confirm all four appear in the correct color.
"""

import sys
import time

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from nsp_marker import NSPMarker

COLORS = [
    ("TRUE_RED",   0x000000FF),  # bytes: FF 00 00 00 → R=255 G=0   B=0   A=0
    ("TRUE_GREEN", 0x0000FF00),  # bytes: 00 FF 00 00 → R=0   G=255 B=0   A=0
    ("TRUE_BLUE",  0x00FF0000),  # bytes: 00 00 FF 00 → R=0   G=0   B=255 A=0
    ("TRUE_WHITE", 0x00FFFFFF),  # bytes: FF FF FF 00 → R=255 G=255 B=255 A=0
]

if __name__ == "__main__":
    with NSPMarker() as m:
        for label, rgba in COLORS:
            m.send(label, rgba=rgba)
            print(f"Sent {label}  (rgba=0x{rgba:08X})")
            time.sleep(5)
    print("Done — confirm all four appear in Central in the correct colors.")

# nsp-marker-mac

Send timestamped event markers from a Mac to a Blackrock NSP during behavioral neuroscience experiments. Injects `cbPKT_COMMENT` packets directly over UDP, bypassing the need for a full CereLink session, so it works alongside Blackrock Central without conflicts.

---

## Current Status (as of 2026-06-12)

**Working end-to-end:**
- `nsp_marker.py` — raw UDP comment injection, confirmed visible in Central raster
- `test_nsp_connection.sh` — pre-flight check (NSP reachability + TEST comment)
- `transfer_data.sh` — mounts SMB share from Windows PC, lists NEV files
- pip-installable via `pip install git+https://github.com/arkhanna/nsp-marker-mac.git`

**Next session:** Write a minimal PsychoPy experiment using `NSPMarker`

---

## Hardware & Network Setup

```
NSP (192.168.137.128)
  ├── direct cable ──→ PC NIC 1 (192.168.137.x)   ← Central recording traffic
  └── switch cable ──→ switch
                          ├── Mac (192.168.137.1, en6)
                          └── PC NIC 2 (192.168.50.1) ← SMB data transfer
```

- **NSP** fixed IP: `192.168.137.128`, UDP port 51001
- **Mac** static IP: `192.168.137.1` on USB Ethernet (`en6`), subnet `255.255.255.0`
- **PC NIC 1** (direct to NSP): `192.168.137.x` — Central uses this for recording
- **PC NIC 2** (to switch): `192.168.50.1` — Mac uses this for SMB file access
- `transfer_data.sh` auto-adds a `192.168.50.2` alias to `en6` so the Mac can reach the PC

**Why two subnets?** Keeps Windows routing unambiguous — PC always uses the direct cable for NSP traffic, never the switch.

---

## Repository Layout

```
nsp-marker-mac/
├── nsp_marker.py            # Core API — raw UDP comment sender (no dependencies)
├── test_nsp_connection.sh   # Pre-flight check — run before each session
├── transfer_data.sh         # Mount smb://192.168.50.1/blackrock, list NEV files
├── test_colors.py           # Verify comment colour encoding against Central
├── test_nsp_connection.py   # Full pycbsdk session test (requires libcbsdk.dylib)
├── setup_mac.sh             # One-time Mac setup (conda env, builds libcbsdk.dylib)
├── setup_windows.ps1        # One-time Windows setup (static IP, SMB share, firewall)
├── pyproject.toml           # pip package definition
└── CereLink-master/         # Blackrock SDK source (C++ + pycbsdk Python wrapper)
```

---

## Key API

```python
from nsp_marker import NSPMarker

with NSPMarker() as marker:
    marker.send("trial_start")                  # default blue
    marker.send("stim_on",  rgba=0x000000FF)    # red
    marker.send("response", rgba=0x0000FF00)    # green
    marker.send("trial_end")
```

`NSPMarker` opens a UDP socket to `192.168.137.128:51001`. Each `send()` fires a single `cbPKT_COMMENT` packet — no handshake, no persistent connection required.

---

## Comment Colour Encoding (VERIFIED WORKING)

Central reads the `rgba` uint32 as raw bytes in **R, G, B, A** order (little-endian).
Alpha is **inverted**: `A=0x00` is opaque, `A=0xFF` is transparent.

Format: `0x00BBGGRR` for opaque colours.

| Colour | rgba value   |
|--------|-------------|
| Blue   | `0x00FF0000` |
| Red    | `0x000000FF` |
| Green  | `0x0000FF00` |
| White  | `0x00FFFFFF` |

Default in `NSPMarker.send()` is `0x00FF0000` (blue). Run `test_colors.py` to re-verify.

---

## Why Raw UDP Instead of pycbsdk?

Central "owns" the NSP — when Central is running, a second process attempting a full `pycbsdk` session handshake gets `INTERNAL_ERROR (-6)`. Raw `cbPKT_COMMENT` injection bypasses this: the NSP accepts and timestamps comment packets from any sender without a handshake. Central records them in the NEV file.

Future `CENTRAL_COMPAT` mode (read-only attach to Central's shared memory) would enable data streaming and recording state queries without this conflict — see Roadmap.

---

## Future: Building libcbsdk.dylib

Required for `pycbsdk` / `CENTRAL_COMPAT` mode (not needed for current nsp_marker.py):

```bash
cmake -B build -S CereLink-master \
  -DCBSDK_BUILD_SHARED=ON \
  -DCBSDK_BUILD_TEST=OFF \
  -DCMAKE_BUILD_TYPE=Release
cmake --build build --target cbsdk_shared --config Release
```

CMake 3.16+, C++17, macOS arm64/x86_64 universal binary already configured.

---

## Next Steps

- [x] NSP connection verified (ping + UDP heartbeat)
- [x] Comment injection end-to-end — blue markers visible in Central raster
- [x] SMB data transfer working — `transfer_data.sh` mounts share, lists NEV files
- [x] pip-installable package (`pyproject.toml`)
- [ ] Write minimal PsychoPy experiment using `NSPMarker`
- [ ] Add named colour support — `marker.send("stim_on", color="red")`
- [ ] Verify comment timestamps align with NSP-recorded neural data offline
- [ ] **Future (cerelink-mac):** `CENTRAL_COMPAT` mode — data streaming, recording state, TTL output, closed-loop

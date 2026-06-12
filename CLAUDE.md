# CereLink + PsychoPy Integration Project

## Goal

Use `pycbsdk` (the Python wrapper in `CereLink-master/`) together with PsychoPy to run behavioral experiments on a Mac laptop that:

1. **Dispatch event markers / comments** to a Blackrock NSP for time-alignment with displayed stimuli
2. **Stream or pull neural data** back from the NSP to the Mac in real time

---

## Hardware & Network Setup

- **NSP** fixed IP: `192.168.137.128`, UDP port 51001
- **Windows PC** running Blackrock Central: `192.168.137.x`
- **Mac laptop**: needs a static IP in `192.168.137.x` subnet (e.g. `192.168.137.2`)
- **Topology**: NSP ↔ unmanaged gigabit switch ↔ Windows PC + Mac (all on same subnet)
  - A switch was required previously — direct Mac↔PC Ethernet with Windows bridging was problematic
  - Known culprits for direct-connection failures: Windows Firewall blocking UDP 51001/51002, APIPA fallback IP addresses

---

## Repository Layout

```
CereLink-master/
├── src/
│   ├── cbproto/   # Packet definitions, protocol version translation (3.11→4.2)
│   ├── cbshm/     # Shared memory ring buffers (STANDALONE / CLIENT / CENTRAL_COMPAT)
│   ├── cbdev/     # UDP socket transport, device handshake, clock sync
│   ├── cbsdk/     # High-level C API (cbsdk.h), thread model orchestration
│   └── ccfutils/  # CCF XML config file load/save
├── pycbsdk/       # Python wrapper (cffi ABI mode, no compiler at install time)
│   └── src/pycbsdk/
│       ├── session.py   # Main Session class (public API)
│       ├── _lib.py      # cffi shared library loader
│       ├── _cdef.py     # C type declarations
│       └── _numpy.py    # Optional zero-copy numpy integration
├── examples/      # C++ and Python examples
├── docs/          # Architecture docs, shared memory layout, cbmex PDF reference
└── BUILD.md       # CMake build instructions
```

---

## Build Requirements (Mac)

`pycbsdk` requires a compiled `libcbsdk.dylib`. Must build from source:

```bash
cmake -B build -S CereLink-master \
  -DCBSDK_BUILD_SHARED=ON \
  -DCBSDK_BUILD_TEST=OFF \
  -DCMAKE_BUILD_TYPE=Release
cmake --build build --target cbsdk_shared --config Release
```

- CMake 3.16+, C++17, macOS universal binary support (arm64;x86_64) already configured
- Point pycbsdk at the built library via `CBSDK_LIB_PATH` env var, or place `.dylib` next to the package

---

## Key pycbsdk API

```python
from pycbsdk import Session, DeviceType, SampleRate, ChannelType

with Session(DeviceType.NSP) as session:

    # --- Send event markers to NSP ---
    session.send_comment("trial_start", rgba=0xFF0000)
    session.set_digital_output(chan_id, value)  # TTL pulse

    # --- Stream continuous data ---
    @session.on_group(SampleRate.SR_30kHz, as_array=True)
    def on_continuous(header, samples):
        # samples: numpy int16 array, one value per channel in group
        ...

    # --- Receive spike events ---
    @session.on_event(ChannelType.FRONTEND)
    def on_spike(header, data):
        ...

    # --- Align clocks ---
    host_time = session.device_to_monotonic(header.time)  # NSP ts → time.monotonic()
```

---

## Connection Modes

| Mode | Description |
|------|-------------|
| `STANDALONE` | CereLink owns UDP connection to NSP directly (3 threads) |
| `CLIENT` | Attaches to another CereLink's shared memory |
| `CENTRAL_COMPAT` | Attaches to Blackrock Central's shared memory (read-only access to Central's data) |

For sending comments and receiving data independently of Central, use **STANDALONE** mode.

---

## What "Building the Shared Library" Means

`pycbsdk` is pure Python — it can't call C++ code directly. It uses `cffi` to load a compiled binary (`libcbsdk.dylib`) at runtime, which contains the actual UDP networking, packet parsing, etc. The chain is:

```
Your Python script
    → pycbsdk (pure Python, cffi)
        → libcbsdk.dylib  (compiled C++ — UDP sockets, packet parsing, etc.)
            → NSP over Ethernet
```

A **shared library** (`.dylib` on macOS, `.so` on Linux, `.dll` on Windows) is a compiled binary that lives as a separate file on disk and is loaded by programs at runtime — as opposed to a static library (`.a`) whose code gets copied directly into the program at compile time. The `.dylib` must be compiled for your specific OS and CPU architecture, which is why it isn't pre-built in the repo.

---

## Comment Colour Encoding (VERIFIED WORKING)

Central reads the `rgba` uint32 field as raw bytes in **R, G, B, A** order (little-endian on the wire).
Alpha is **inverted**: `A=0x00` is fully opaque, `A=0xFF` is fully transparent.

Use the format `0x00BBGGRR` for opaque colours:

| Colour | rgba value   |
|--------|-------------|
| Blue   | `0x00FF0000` |
| Red    | `0x000000FF` |
| Green  | `0x0000FF00` |
| White  | `0x00FFFFFF` |

The default in `NSPMarker.send()` is `0x00FF0000` (blue). See `test_colors.py` to re-verify.

---

## Next Steps

- [ ] Build `libcbsdk.dylib` on Mac
- [ ] Install `pycbsdk` with numpy support and verify it loads the dylib
- [x] Test basic connection to NSP (verify IP/subnet config, switch setup)
- [x] Verify comment injection end-to-end — `nsp_marker.py` confirmed working, blue comments visible in Central raster (2026-06-12)
- [ ] Resolve SMB data transfer — Mac needs a `192.168.50.x` IP to reach Windows PC at `192.168.50.1`
- [ ] Write a minimal PsychoPy experiment that calls `send_comment()` at key trial events
- [ ] Verify comment timestamps align with NSP-recorded data in Central
- [ ] Prototype continuous data streaming callback alongside PsychoPy loop

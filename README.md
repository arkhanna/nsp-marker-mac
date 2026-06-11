# CereLink + PsychoPy Integration

Send timestamped event markers from a Mac to a Blackrock NSP during behavioral experiments, and access the recorded neural data over the same network.

---

## Hardware Requirements

- Blackrock Gemini NSP + Hub
- Windows PC running Blackrock Central
- Mac laptop (Intel or Apple Silicon)
- Two Ethernet cables + one unmanaged gigabit switch
- USB-to-Ethernet adapter on the Mac (if no built-in Ethernet port)

---

## Network Topology

```
Gemini Hub ──── NSP ──────────── Central PC (NIC 1)
                 │                      │
                 └────── Switch ─────── Central PC (NIC 2) [192.168.50.1]
                              │
                            Mac [192.168.137.2]
```

| Device | Interface | IP |
|--------|-----------|----|
| NSP | — | 192.168.137.128 |
| Central PC — NSP NIC | Ethernet (NSP) | 192.168.137.x |
| Central PC — Switch NIC | Ethernet (Switch) | 192.168.50.1 |
| Mac | USB Ethernet | 192.168.137.2 |

**Why two NICs on the PC?** The NSP requires a direct cable to Central for reliable operation (routing NSP traffic through the switch caused Hub detection failures and packet loss). A second NIC on the switch gives the Mac a path to the PC for file sharing without disrupting the NSP connection.

**Why raw UDP instead of a pycbsdk Session?** Central "owns" the NSP — when Central is running, the NSP sends its startup replies (SYSREP) only to Central. A second process attempting a full session handshake (via pycbsdk) gets an `INTERNAL_ERROR`. Instead, we inject `cbPKT_COMMENT` packets directly over UDP; the NSP accepts and timestamps them without needing a handshake, and Central records them in the NEV file.

---

## Repository Layout

```
cerelink/
├── CereLink-master/         # Blackrock SDK (C++ source + pycbsdk Python wrapper)
├── nsp_marker.py            # Raw UDP comment sender (main experiment API)
├── read_nev.py              # NEV file reader with GUI file picker
├── setup_mac.sh             # One-time Mac installation script
├── setup_windows.ps1        # One-time Windows PC configuration script
└── run_experiment.sh        # Pre-flight check — run before each session
```

---

## Installation

### Mac (one time)

1. Clone this repo.
2. Set a **static IP** on your Mac's Ethernet adapter:
   - System Settings → Network → [USB/Thunderbolt Ethernet] → Details → TCP/IP → Manual
   - IP: `192.168.137.2`, Subnet: `255.255.255.0`, Router: *(leave blank)*
3. Run the setup script:
   ```bash
   bash setup_mac.sh
   ```
   This will:
   - Create a `cerelink` conda environment (Python 3.11)
   - Build `libcbsdk.dylib` from source using CMake
   - Install `pycbsdk` (Python wrapper for the Blackrock SDK)
   - Install `neo` (for reading NEV files)

**Requirements:** [Homebrew](https://brew.sh), [Miniconda](https://docs.conda.io/en/latest/miniconda.html), Xcode Command Line Tools (`xcode-select --install`)

### Windows PC (one time)

1. Connect the PC's second NIC to the network switch.
2. Open **PowerShell as Administrator** and run:
   ```powershell
   .\setup_windows.ps1
   ```
   This will:
   - Assign static IP `192.168.50.1` to the switch-facing NIC
   - Set that adapter's network profile to **Private** (required for SMB)
   - Open firewall port 445 (SMB)
   - Create and share `C:\blackrock`

3. In Blackrock Central: **File → Preferences → Save → set path to `C:\blackrock`**

4. Set a password on your Windows account so the Mac can authenticate:
   ```cmd
   net user <your-username> <password>
   ```
   The Mac stores this in Keychain after the first login — you won't be asked again.

---

## Running an Experiment

Before each session, run the pre-flight check from the Mac:

```bash
bash run_experiment.sh
```

This will:
1. Confirm the NSP is reachable (listens for its UDP heartbeat)
2. Mount `smb://192.168.50.1/blackrock` if not already mounted
3. Inject 3 test comment markers and confirm no errors

If all checks pass, you're ready to record.

---

## Sending Markers from PsychoPy

```python
from nsp_marker import NSPMarker

# Open once at experiment start
marker = NSPMarker()  # connects to NSP at 192.168.137.128

# Send markers at key trial events
marker.send("experiment_start")
marker.send("block_1_start")
marker.send("trial_1_stimulus_on", rgba=0xFF0000FF)   # red
marker.send("trial_1_response",    rgba=0x00FF00FF)   # green
marker.send("trial_1_feedback",    rgba=0x0000FFFF)   # blue

# Close when done (or use as a context manager)
marker.close()
```

**Colour encoding:** `rgba` is a 32-bit integer `0xRRGGBBAA`. Assigning distinct colours to event types makes them easy to identify in Central's raster plot and in offline analysis.

**Marker text** is truncated to 127 ASCII characters. Keep labels short and consistent — they become searchable fields in the NEV file.

---

## Reading Recorded Data

NEV files are saved to `C:\blackrock` on the PC and accessible via the mounted share at `/Volumes/blackrock/`.

```bash
# GUI file picker — select any .nev file
conda run -n cerelink python read_nev.py
```

Or read programmatically:

```python
from neo.io import BlackrockIO

reader = BlackrockIO(filename="/Volumes/blackrock/session1/NSP-20260611-001.nev")
block = reader.read_block(lazy=False)

seg = block.segments[0]
for ev in seg.events:
    if ev.name == "comments":
        for t, label in zip(ev.times, ev.labels):
            print(f"{float(t):.4f} s  {label}")
```

**Which file has the comments?** Only the NSP file (e.g. `NSP-*.nev`). The Hub file (`Hub1-*.nev`) records electrode channel data but not comment markers.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| NSP not reachable | Check Mac Ethernet IP is `192.168.137.2/24`. Check switch power and cables. |
| Only the most recent comment visible in Central's raster | Normal — Central only shows the latest live marker. All markers are saved in the NEV file. |
| SMB mount fails with "connection refused" | Run `setup_windows.ps1` on the PC (sets network to Private, opens port 445). |
| SMB mount fails with auth error | Set a password: `net user <username> <password>` in Admin CMD on the PC. |
| `pycbsdk` session gets `INTERNAL_ERROR (-6)` | Expected — Central owns the NSP handshake. Use `nsp_marker.py` (raw UDP) for comment injection; pycbsdk sessions are not needed. |
| `SETUPTOOLS_SCM_PRETEND_VERSION` error during install | Repo is not inside a git repo. `setup_mac.sh` sets this env var automatically. |
| Comments appear duplicated in NEV file | Normal — the Blackrock firmware echoes comment packets; each marker appears twice with identical timestamps. |

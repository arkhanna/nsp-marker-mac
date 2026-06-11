"""
Open a NEV file via file dialog and print its contents.
Run with: conda run -n cerelink python read_nev.py
"""

import tkinter as tk
from tkinter import filedialog


def main():
    root = tk.Tk()
    root.withdraw()
    root.call("wm", "attributes", ".", "-topmost", True)

    path = filedialog.askopenfilename(
        title="Select a NEV file",
        filetypes=[("NEV files", "*.nev"), ("All files", "*.*")],
    )
    root.destroy()

    if not path:
        print("No file selected.")
        return

    print(f"Reading: {path}\n")

    try:
        from neo.io import BlackrockIO
    except ImportError:
        print("neo not found — run: conda run -n cerelink pip install neo")
        return

    reader = BlackrockIO(filename=path)
    block = reader.read_block(lazy=False)

    print(f"Block name    : {block.name!r}")
    print(f"Rec datetime  : {block.rec_datetime}")
    print(f"Segments      : {len(block.segments)}")

    for si, seg in enumerate(block.segments):
        print(f"\n{'='*60}")
        print(f"Segment {si}")
        print(f"  Spike trains  : {len(seg.spiketrains)}")
        print(f"  Analog signals: {len(seg.analogsignals)}")
        print(f"  Events        : {len(seg.events)}")
        print(f"  Epochs        : {len(seg.epochs)}")

        if seg.spiketrains:
            print("\n  -- Spike trains --")
            for st in seg.spiketrains:
                print(f"    ch={st.annotations.get('channel_id', '?'):>3}  "
                      f"unit={st.annotations.get('unit_id', '?')}  "
                      f"n_spikes={len(st)}")

        if seg.events:
            print("\n  -- Events (comments / digital markers) --")
            for ev in seg.events:
                print(f"    [{ev.name!r}]  n={len(ev)}")
                for t, label in zip(ev.times, ev.labels):
                    print(f"      t={float(t):10.4f} s   {label!r}")

        if seg.epochs:
            print("\n  -- Epochs --")
            for ep in seg.epochs:
                print(f"    [{ep.name!r}]  n={len(ep)}")
                for t, d, label in zip(ep.times, ep.durations, ep.labels):
                    print(f"      t={float(t):10.4f} s  dur={float(d):.4f} s   {label!r}")

        if seg.analogsignals:
            print("\n  -- Analog signals --")
            for sig in seg.analogsignals:
                print(f"    {sig.name!r}  shape={sig.shape}  "
                      f"sr={sig.sampling_rate}  units={sig.units}")


if __name__ == "__main__":
    main()

"""Quick connection test: open a Session to the NSP and verify handshake."""

import time
from pycbsdk import Session, DeviceType

print("Opening session to NSP...")
try:
    with Session(DeviceType.NSP) as session:
        # Give the UDP handshake time to complete
        time.sleep(3)

        print(f"  running:           {session.running}")
        print(f"  protocol_version:  {session.protocol_version!r}")
        print(f"  proc_ident:        {session.proc_ident!r}")
        print(f"  runlevel:          {session.runlevel}")
        print(f"  clock_offset_ns:   {session.clock_offset_ns}")
        print(f"  stats:             {session.stats}")

        if session.running:
            session.send_comment("cerelink_test_ok")
            print("\nSent test comment 'cerelink_test_ok' to NSP.")
            print("\nCONNECTION OK")
        else:
            print("\nWARNING: session opened but not running — handshake may have failed.")

except Exception as e:
    print(f"\nFAILED: {e}")

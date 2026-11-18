"""
Timing of NSPMarker.send_at(), with no NSP needed (packets go to a fake socket).

    python test_send_at.py       # compares time.sleep() with send_at() on this Mac
    python -m pytest test_send_at.py
"""

import statistics
import sys
import time

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from nsp_marker import NSPMarker, wait_until


class FakeSocket:
    def __init__(self):
        self.sent = []

    def send(self, pkt):
        self.sent.append((time.perf_counter(), pkt))

    def close(self):
        pass


def offline_marker():
    marker = NSPMarker(dry_run=True)
    marker.dry_run = False
    marker._sock = FakeSocket()
    return marker


def lateness_ms(schedule, n=40, ahead=0.03):
    """How late each of n sends lands, in ms, when scheduled `ahead` seconds out."""
    late = []
    for _ in range(n):
        when = time.perf_counter() + ahead
        late.append((schedule(when) - when) * 1000)
    return sorted(late)


def sleep_then_send(marker):
    def schedule(when):
        time.sleep(max(0.0, when - time.perf_counter()))
        return marker.send("x")
    return schedule


def test_send_at_never_sends_early_and_lands_within_a_millisecond():
    late = lateness_ms(lambda when: offline_marker().send_at("x", when))
    assert late[0] >= 0
    assert statistics.median(late) < 0.5 and late[-1] < 1.0


def test_send_at_sends_the_comment_and_returns_its_send_time():
    marker = offline_marker()
    when = time.perf_counter() + 0.02
    t_sent = marker.send_at("stim_on", when)
    (t_socket, pkt), = marker._sock.sent
    assert b"stim_on" in pkt and len(pkt) == 160
    assert when <= t_sent <= t_socket


def test_a_time_already_past_sends_at_once():
    marker = offline_marker()
    start = time.perf_counter()
    marker.send_at("late", start - 1.0)
    assert time.perf_counter() - start < 0.005 and len(marker._sock.sent) == 1


def test_wait_until_works_on_another_clock():
    ticks = iter(range(100))
    wait_until(5, clock=lambda: next(ticks), spin_s=0)
    assert next(ticks) == 6


if __name__ == "__main__":
    marker = offline_marker()
    for name, schedule in [("time.sleep() then send()", sleep_then_send(marker)),
                           ("send_at()", lambda when: marker.send_at("x", when))]:
        late = lateness_ms(schedule)
        print(f"{name:26s} late by median {statistics.median(late):.2f} ms, max {late[-1]:.2f} ms")

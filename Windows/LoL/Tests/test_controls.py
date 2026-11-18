import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lol_controls import HoldController


class ControlsTest(unittest.TestCase):
    def setUp(self):
        self.now = 0.0
        self.enabled = True
        self.queue, self.events, self.leases = [], [], []
        def start(held):
            self.events.append("hold")
            self.leases.append(held)
        bindings = {"MB5": (lambda: self.events.append("flash"), start,
                            lambda: self.events.append("end"))}
        self.c = HoldController(bindings, self.queue.append, lambda: self.enabled,
                                clock=lambda: self.now)

    def drain(self):
        while self.queue:
            self.queue.pop(0)()

    def test_tap_emits_once_on_release(self):
        self.c.press("MB5")
        self.c.press("MB5")
        self.drain()
        self.assertEqual(self.events, [])
        self.now = .1
        self.c.release("MB5")
        self.c.release("MB5")
        self.drain()
        self.assertEqual(self.events, ["flash"])

    def test_delayed_worker_never_flashes_on_hold(self):
        self.c.press("MB5")
        self.now = .3
        self.c.release("MB5")  # no timer/poll has run
        self.drain()
        self.assertEqual(self.events, [])

    def test_released_pending_hold_never_starts(self):
        self.c.press("MB5")
        self.now = .2
        self.c.poll()
        self.c.release("MB5")
        self.drain()
        self.assertEqual(self.events, [])

    def test_hold_ends_and_does_not_flash(self):
        self.c.press("MB5")
        self.now = .2
        self.c.poll()
        self.drain()
        self.assertTrue(self.leases[0]())
        self.c.release("MB5")
        self.assertFalse(self.leases[0]())
        self.drain()
        self.assertEqual(self.events, ["hold", "end"])

    def test_repress_does_not_revive_old_loop(self):
        self.c.press("MB5")
        self.now = .2
        self.c.poll()
        self.drain()
        self.c.release("MB5")
        self.c.press("MB5")
        self.now = .4
        self.c.poll()
        self.drain()
        self.assertFalse(self.leases[0]())
        self.assertTrue(self.leases[1]())

    def test_focus_loss_cancels_hold_and_queued_click(self):
        self.c.press("MB5")
        self.c.release("MB5")
        self.enabled = False
        self.c.poll()
        self.enabled = True
        self.drain()
        self.assertEqual(self.events, [])

    def test_queued_click_checks_focus_at_execution(self):
        self.c.press("MB5")
        self.c.release("MB5")
        self.enabled = False
        self.drain()
        self.assertEqual(self.events, [])

    def test_focus_loss_invalidates_held_lease_immediately(self):
        self.c.press("MB5")
        self.now = .2
        self.c.poll()
        self.drain()
        self.enabled = False
        self.assertFalse(self.leases[0]())
        self.c.poll()
        self.enabled = True
        self.assertFalse(self.leases[0]())
        self.drain()
        self.assertEqual(self.events, ["hold", "end"])

    def hold_only(self):
        bindings = {"WIN": (lambda: self.events.append("click"),
                            lambda held: self.events.append("start"),
                            lambda: self.events.append("end"), True)}
        return HoldController(bindings, self.queue.append, lambda: self.enabled,
                              clock=lambda: self.now)

    def test_hold_only_with_click_starts_at_press(self):
        c = self.hold_only()
        c.press("WIN")
        self.drain()
        self.assertEqual(self.events, ["start"])
        c.release("WIN")
        import time
        time.sleep(.05)                       # end runs on its own thread
        self.assertEqual(self.events, ["start", "end"])

    def test_hold_only_released_before_start_is_a_click(self):
        c = self.hold_only()
        c.press("WIN")
        c.release("WIN")                      # worker had not run the start yet
        self.drain()
        self.assertEqual(self.events, ["click"])

    def test_disabled_champion_does_not_capture(self):
        self.enabled = False
        self.c.press("MB5")
        self.assertFalse(self.c.down)


if __name__ == "__main__":
    unittest.main()

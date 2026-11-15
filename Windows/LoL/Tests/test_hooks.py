"""Mocked hook integration: no input is sent and no listeners are started."""
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
if sys.platform == "win32":
    import lol


@unittest.skipUnless(sys.platform == "win32", "Windows hook integration")
class HookTest(unittest.TestCase):
    def setUp(self):
        self.patches = [patch.object(lol, "macros_active", return_value=True),
                        patch.object(lol, "kb_listener", Mock(), create=True),
                        patch.object(lol, "mouse_listener", Mock(), create=True)]
        self.active = self.patches[0].start()
        for p in self.patches[1:]:
            p.start()
        self.addCleanup(lambda: [p.stop() for p in reversed(self.patches)])
        lol.pressed.clear()
        lol.captured.clear()
        lol.controls.cancel()
        lol.controls.enabled = lambda: lol.macros_active()
        while not lol.actions.empty():
            lol.actions.get_nowait()

    def key(self, msg):
        lol.kb_filter(msg, SimpleNamespace(flags=0, vkCode=lol.VK_B))

    def test_cancelled_key_never_leaks_repeat_or_release(self):
        self.key(lol.WM_KEYDOWN)
        self.active.return_value = False
        lol.controls.poll()
        self.key(lol.WM_KEYDOWN)
        self.key(lol.WM_KEYUP)
        self.assertEqual(lol.kb_listener.suppress_event.call_count, 3)
        self.assertFalse(lol.captured)

    def test_non_kalista_keys_pass_through(self):
        self.active.return_value = False
        self.key(lol.WM_KEYDOWN)
        self.key(lol.WM_KEYUP)
        lol.kb_listener.suppress_event.assert_not_called()
        self.assertFalse(lol.macro_down)

    def test_cancelled_mb5_release_is_suppressed(self):
        data = SimpleNamespace(flags=0, mouseData=2 << 16)
        lol.mouse_filter(lol.WM_XBUTTONDOWN, data)
        self.active.return_value = False
        lol.controls.poll()
        lol.mouse_filter(lol.WM_XBUTTONUP, data)
        self.assertEqual(lol.mouse_listener.suppress_event.call_count, 2)
        self.assertFalse(lol.captured)

    def test_inactive_outputs_send_nothing(self):
        self.active.return_value = False
        with patch.object(lol, "_send") as send, patch.object(lol.user32, "SendInput") as mouse:
            lol.tap("f10")
            lol.right_click()
            lol.mask_win()
            send.assert_not_called()
            mouse.assert_not_called()


if __name__ == "__main__":
    unittest.main()

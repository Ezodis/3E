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

    def test_mb5_always_reaches_league(self):
        data = SimpleNamespace(flags=0, mouseData=2 << 16)
        lol.mouse_filter(lol.WM_XBUTTONDOWN, data)
        lol.mouse_filter(lol.WM_XBUTTONUP, data)
        lol.mouse_listener.suppress_event.assert_not_called()
        self.assertFalse(lol.macro_down)

    def test_kite_key_starts_at_once_and_is_blocked(self):
        with patch.object(lol, "kite_start") as start:
            lol.MACRO_KEYS[lol.VK_F13] = (None, start, None, True)
            key = SimpleNamespace(flags=0, vkCode=lol.VK_F13)
            lol.kb_filter(lol.WM_KEYDOWN, key)
            lol.actions.get_nowait()()           # queued at press time, no hold wait
            start.assert_called_once()
            lol.kb_filter(lol.WM_KEYUP, key)
            self.assertEqual(lol.kb_listener.suppress_event.call_count, 2)
            self.assertFalse(lol.captured)
            lol.MACRO_KEYS[lol.VK_F13] = (None, lol.kite_start, None, True)

    def test_win_is_the_camera_key_and_never_reaches_windows(self):
        key = SimpleNamespace(flags=0, vkCode=lol.VK_LWIN)
        with patch.object(lol, "camera_hold_start") as start:
            lol.MACRO_KEYS[lol.VK_LWIN] = (lol.toggle_camera, start, lol.camera_hold_end, True)
            lol.kb_filter(lol.WM_KEYDOWN, key)
            lol.actions.get_nowait()()           # starts at press time: no hold wait
            start.assert_called_once()
            with patch.object(lol, "camera_hold_end"):
                lol.kb_filter(lol.WM_KEYUP, key)
            self.assertEqual(lol.kb_listener.suppress_event.call_count, 2)
        lol.MACRO_KEYS[lol.VK_LWIN] = (lol.toggle_camera, lol.camera_hold_start, lol.camera_hold_end, True)

    def test_b_tap_sends_b_and_hold_opens_the_shop(self):
        click, start, _ = lol.MACRO_KEYS[lol.VK_B]
        with patch.object(lol, "tap", return_value=True) as tap:
            click()
            tap.assert_called_once_with("b")
            tap.reset_mock()
            start(lambda: True)
            tap.assert_called_once_with(lol.SHOP_KEY)
        self.assertEqual(lol.SHOP_KEY, "v")

    def test_m_tap_sends_m_and_hold_holds_r_alone(self):
        click, start, end = lol.MACRO_KEYS[lol.VK_M]
        sent = []
        with patch.object(lol, "tap", side_effect=lambda k: sent.append(("tap", k)) or True), \
                patch.object(lol, "key_down", side_effect=lambda k: sent.append(("down", k)) or True), \
                patch.object(lol, "key_up", side_effect=lambda k: sent.append(("up", k))):
            click()
            start(lambda: True)
            end()
        self.assertEqual(sent, [("tap", "m"), ("down", "f8"), ("up", "f8")])

    def test_injected_win_is_masked_so_start_never_opens(self):
        with patch.object(lol, "_send") as send:
            lol.key_down("lwin")
        flags = [c.kwargs.get("flags", 0) for c in send.call_args_list]
        self.assertTrue(flags[0] & lol.KEYEVENTF_EXTENDEDKEY)
        self.assertEqual([c.kwargs.get("vk") for c in send.call_args_list[1:]], [0xE8, 0xE8])

    def test_hold_keys_match_league_binds(self):
        import lol_settings
        self.assertEqual(lol_settings.SET["evtOpenShop"], f"[{lol.SHOP_KEY}]")
        self.assertEqual(lol_settings.SET["evtPlayerStopPosition"], f"[{lol.STOP_KEY}]")
        self.assertIn(f"[{lol.R_KEY.upper()}]", lol_settings.SET["evtCastSpell4"])
        self.assertEqual(lol_settings.SET["evtCameraLockToggle"], "[L Win]")

    def test_n_reaches_league(self):
        key = SimpleNamespace(flags=0, vkCode=0x4E)
        lol.kb_filter(lol.WM_KEYDOWN, key)
        lol.kb_filter(lol.WM_KEYUP, key)
        lol.kb_listener.suppress_event.assert_not_called()

    def test_camera_click_and_hold(self):
        sent = []
        with patch.object(lol, "tap", side_effect=lambda k: sent.append(("tap", k)) or True), \
                patch.object(lol, "key_down", side_effect=lambda k: sent.append(("down", k)) or True), \
                patch.object(lol, "key_up", side_effect=lambda k: sent.append(("up", k))), \
                patch.object(lol.time, "sleep"):
            for locked, held_for, end_locked in ((True, .05, False), (False, .05, True),
                                                 (True, .5, True), (False, .5, False)):
                with self.subTest(locked=locked, held_for=held_for):
                    sent.clear()
                    lol.camera_locked = locked
                    lol.camera_hold_start(lambda: True)
                    lol.cam["t0"] -= held_for
                    lol.camera_hold_end()
                    self.assertEqual(lol.camera_locked, end_locked)
                    self.assertIn(("down", lol.PAN_KEY), sent)   # the drag starts at once
                    self.assertIn(("up", lol.PAN_KEY), sent)

    def test_kite_key_is_a_normal_key_outside_league(self):
        self.active.return_value = False
        key = SimpleNamespace(flags=0, vkCode=lol.VK_PAUSE)
        lol.kb_filter(lol.WM_KEYDOWN, key)
        lol.kb_filter(lol.WM_KEYUP, key)
        lol.kb_listener.suppress_event.assert_not_called()

    def test_inactive_outputs_send_nothing(self):
        self.active.return_value = False
        with patch.object(lol, "_send") as send, patch.object(lol.user32, "SendInput") as mouse:
            lol.tap("f10")
            lol.right_click()
            send.assert_not_called()
            mouse.assert_not_called()


if __name__ == "__main__":
    unittest.main()

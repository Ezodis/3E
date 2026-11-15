"""Render the actual marker into a fake canvas, without windows or input hooks."""
import sys
import unittest
from pathlib import Path
from unittest.mock import Mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
if sys.platform == "win32":
    import lol


@unittest.skipUnless(sys.platform == "win32", "Windows overlay renderer")
class MarkerTest(unittest.TestCase):
    def draw(self, hp, damage, max_hp=1000, scale=1, origin=(100, 200), **changes):
        result = dict(hp=hp, dmg=damage, max_hp=max_hp, stacks=36, state=None,
                      bar=(origin[0] + 317 * scale, origin[1] + 61 * scale,
                           origin[0] + 540 * scale, origin[1] + 91 * scale))
        result.update(changes)
        canvas = Mock()
        marker = lol.draw_rend_marker(canvas, result, origin, scale)
        if marker:
            # All three strokes must use the reported coordinate, not a stale position.
            self.assertEqual(canvas.create_line.call_count, 3)
            for call in canvas.create_line.call_args_list:
                self.assertEqual(call.args[0], marker["x"])
                self.assertEqual(call.args[2], marker["x"])
        return marker, canvas

    def test_line_sits_at_kill_hp_from_left(self):
        marker, _ = self.draw(900, 300)
        self.assertAlmostEqual(marker["coverage"], .3)
        self.assertAlmostEqual(marker["x"], 317 + .3 * 223)

    def test_line_ignores_current_hp(self):
        for hp in (1000, 600, 201, 1):
            with self.subTest(hp=hp):
                marker, _ = self.draw(hp, 200)
                self.assertAlmostEqual(marker["x"], 317 + .2 * 223)

    def test_added_spears_move_right(self):
        first, _ = self.draw(900, 100)
        second, _ = self.draw(900, 500)
        self.assertGreater(second["x"], first["x"])

    def test_kill_colour(self):
        _, canvas = self.draw(100, 200, state="kill")
        self.assertEqual(canvas.create_line.call_args_list[1].kwargs["fill"], "#ff3b5c")

    def test_overkill_clamps_to_right_edge(self):
        marker, _ = self.draw(1, 10000, state="kill")
        self.assertEqual(marker["x"], marker["bar_right"])

    def test_no_spears_resets_to_left_edge(self):
        marker, _ = self.draw(500, 0, stacks=0)
        self.assertEqual(marker["x"], 317)

    def test_target_switch_has_no_previous_position(self):
        self.draw(1, 900, state="kill")
        marker, _ = self.draw(800, 100)
        self.assertAlmostEqual(marker["x"], 317 + .1 * 223)

    def test_pending_read_stays_muted(self):
        marker, canvas = self.draw(100, 200, pending=True)
        self.assertAlmostEqual(marker["coverage"], .2)
        self.assertEqual(canvas.create_line.call_args_list[1].kwargs["fill"], "#91a5a0")

    def test_window_offsets_and_hud_scales(self):
        for scale in (.5, 1, 1.5, 2):
            for origin in ((0, 0), (500, 100), (-2048, -300)):
                with self.subTest(scale=scale, origin=origin):
                    marker, _ = self.draw(750, 250, scale=scale, origin=origin)
                    self.assertAlmostEqual(marker["x"], (317 + 223 / 4) * scale)

    def test_invalid_or_missing_bar_draws_nothing(self):
        for changes in (dict(max_hp=0), dict(bar=None)):
            marker, canvas = self.draw(1, 100, **changes)
            self.assertIsNone(marker)
            canvas.create_line.assert_not_called()
        marker, canvas = self.draw(0, 100)
        self.assertIsNone(marker)
        canvas.create_line.assert_not_called()

    def test_lightning_requires_fresh_confirmed_lethal_hit(self):
        res = dict(hp=100, dmg=100, stacks=1, state="kill", observed_at=10)
        self.assertTrue(lol.show_lethal_lightning(res, 10.1))
        for changes in (dict(state="close"), dict(state=None), dict(pending=True),
                        dict(hp=101), dict(hp=0), dict(stacks=0), dict(observed_at=9)):
            self.assertFalse(lol.show_lethal_lightning(dict(res, **changes), 10.1), changes)


if __name__ == "__main__":
    unittest.main()

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

    def test_reported_one_hp_target_draws_at_empty_edge(self):
        marker, canvas = self.draw(1, 730.4, state="kill")
        self.assertEqual(marker["remaining_hp"], 0)
        self.assertEqual(marker["x"], 317)
        self.assertEqual(canvas.create_line.call_args_list[1].kwargs["fill"], "#ff3b5c")

    def test_falling_health_moves_left_with_same_damage(self):
        for hp, expected in [(1000, 800), (600, 400), (201, 1), (200, 0), (1, 0)]:
            with self.subTest(hp=hp):
                marker, _ = self.draw(hp, 200)
                self.assertEqual(marker["remaining_hp"], expected)
                self.assertAlmostEqual(marker["x"], 317 + expected * 223 / 1000)

    def test_added_spears_move_left_without_waiting_for_hp_change(self):
        first, _ = self.draw(900, 100)
        second, _ = self.draw(900, 500)
        self.assertLess(second["x"], first["x"])

    def test_damage_over_maximum_never_pushes_marker_right(self):
        marker, _ = self.draw(1, 10000, state="kill")
        self.assertEqual(marker["x"], marker["bar_left"])

    def test_no_spears_aligns_with_current_fill(self):
        marker, _ = self.draw(500, 0, stacks=0)
        self.assertEqual(marker["x"], (317 + 540) / 2)

    def test_target_switch_and_healing_have_no_previous_position(self):
        self.draw(1, 900, state="kill")
        marker, _ = self.draw(800, 100)
        self.assertAlmostEqual(marker["x"], 317 + .7 * 223)

    def test_pending_read_updates_hp_but_stays_muted(self):
        marker, canvas = self.draw(100, 200, pending=True)
        self.assertEqual(marker["remaining_hp"], 0)
        self.assertEqual(canvas.create_line.call_args_list[1].kwargs["fill"], "#91a5a0")

    def test_window_offsets_and_hud_scales(self):
        for scale in (.5, 1, 1.5, 2):
            for origin in ((0, 0), (500, 100), (-2048, -300)):
                with self.subTest(scale=scale, origin=origin):
                    marker, _ = self.draw(750, 250, scale=scale, origin=origin)
                    self.assertAlmostEqual(marker["x"], (317 + 223 * .5) * scale)

    def test_invalid_or_missing_bar_draws_nothing(self):
        for changes in (dict(max_hp=0), dict(bar=None)):
            marker, canvas = self.draw(1, 100, **changes)
            self.assertIsNone(marker)
            canvas.create_line.assert_not_called()


if __name__ == "__main__":
    unittest.main()

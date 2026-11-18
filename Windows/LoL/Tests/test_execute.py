import sys
import unittest
from pathlib import Path
from PIL import Image, ImageDraw
import numpy as np
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import lol_execute as e


ME = dict(e_level=5, ad=200, ap=0, pen_pct=0, flat_pen=0, coup=False, cutdown=False)
OBS = dict(present=True, ally=False, fill=.1, hp=100, max_hp=1000,
           armor=0, mr=0, stacks=1, monster=False)


class ExecuteTest(unittest.TestCase):
    def setUp(self):
        # Exercise the reader decisions without starting hooks, capture or background threads.
        self.w = e.ExecuteWatcher.__new__(e.ExecuteWatcher)
        self.w.result = None

    def observe(self, **changes):
        self.w._observe(ME, dict(OBS, **changes))
        return self.w.result

    def test_rend_ranks_and_extra_spears(self):
        for rank, base, extra, ratio in zip(range(1, 6), e.E_BASE, e.E_STACK_BASE, e.E_STACK_AD):
            expected = base + .7 * 200 + .65 * 80 + 3 * (extra + ratio * 200 + .5 * 80)
            self.assertAlmostEqual(e.rend_damage(4, rank, 200, 80), expected)

    def test_armor_penetration_and_negative_armor(self):
        self.assertAlmostEqual(e.armor_multiplier(100, .2, 20), 100 / 160)
        self.assertEqual(e.armor_multiplier(10, 0, 99), 1)
        self.assertAlmostEqual(e.armor_multiplier(-50, .2, 20), 2 - 100 / 150)

    def test_epic_and_runes(self):
        target = dict(OBS, epic=True)
        result = e.evaluate(dict(ME, coup=True), target)
        self.assertAlmostEqual(result["dmg"], 185 * .5 * 1.08)
        target.update(hp=700, epic=False)
        self.assertAlmostEqual(e.evaluate(dict(ME, cutdown=True), target)["dmg"], 185 * 1.08)

    def test_exact_kill(self):
        self.assertEqual(self.observe()["state"], "kill")

    def test_zero_spears_and_dead_target_never_kill(self):
        self.assertIsNone(self.observe(stacks=0)["state"])
        self.assertIsNone(self.observe(hp=0, fill=0)["state"])

    def test_identical_target_stats_do_not_keep_old_spears(self):
        self.observe(stacks=10)
        result = self.observe(stacks=0)
        self.assertEqual(result["dmg"], 0)
        self.assertEqual(result["stacks"], 0)
        self.assertIsNone(result["state"])

    def test_ally_or_missing_target_clears_immediately(self):
        for changes in ({"ally": True}, {"present": False}, {"max_hp": None}, {"fill": None}):
            self.observe()
            self.assertIsNone(self.observe(**changes), changes)

    def test_new_number_on_same_target_keeps_a_muted_line_without_lightning(self):
        for changes in ({"armor": None, "stacks": 4}, {"stacks": None}):
            self.observe(identity=b"dummy", stacks=4)
            result = self.observe(identity=b"dummy", **changes)
            self.assertTrue(result["pending"], changes)
            self.assertEqual(result["stacks"], 4)
            self.assertNotEqual(result["state"], "kill")

    def test_estimate_requires_three_consecutive_frames(self):
        self.assertEqual(self.observe(hp=None)["state"], "close")
        self.assertEqual(self.observe(hp=None)["state"], "close")
        self.assertEqual(self.observe(hp=None)["state"], "kill")
        self.observe(stacks=None)
        self.assertEqual(self.observe(hp=None)["state"], "close")

    def test_bar_disagreement_blocks_lightning(self):
        self.assertNotEqual(self.observe(fill=.8)["state"], "kill")

    def test_red_only_across_hud_scales(self):
        for scale in (.5, 1, 1.5, 2):
            for colour, reject in (("#aa2020", False), ("#20aa20", True),
                                   ("#202020", True), ("#2099aa", True)):
                frame = Image.new("RGB", (int(602 * scale), int(258 * scale)))
                draw = ImageDraw.Draw(frame)
                draw.rectangle(tuple(int(x * scale) for x in e.HEALTH_BAR), fill=colour)
                self.assertEqual(e.target_is_enemy(frame, scale, None), not reject, (scale, colour))

    def test_one_hp_requires_enemy_evidence_and_never_overrides_green(self):
        frame = Image.new("RGB", (602, 258), "#202020")
        self.assertFalse(e.target_is_enemy(frame, 1, None))
        self.assertTrue(e.target_is_enemy(frame, 1, (504, 198, 551, 245)))
        ImageDraw.Draw(frame).rectangle(e.HEALTH_BAR, fill="#20aa20")
        self.assertFalse(e.target_is_enemy(frame, 1, (504, 198, 551, 245)))

    def test_identical_portrait_never_borrows_unreadable_spears(self):
        self.observe(identity=b"dummy", stacks=60)
        held = self.observe(identity=b"dummy", stacks=None)
        self.assertTrue(held["pending"])
        self.assertNotEqual(held["state"], "kill")
        result = self.observe(identity=b"dummy", stacks=1)
        self.assertEqual(result["stacks"], 1)
        self.assertEqual(result["dmg"], 185)

    def test_monster_portrait_not_hp_determines_damage(self):
        normal = self.observe(monster=True, monster_kind=("sru_gromp", False),
                              hp=2695, max_hp=2870, fill=2695/2870, armor=42)
        self.assertAlmostEqual(normal["dmg"], 185 * 100/142)
        epic = self.observe(monster=True, monster_kind=("sru_baron", True),
                            hp=2695, max_hp=2870, fill=2695/2870, armor=42)
        self.assertAlmostEqual(epic["dmg"], normal["dmg"] / 2)
        unknown = self.observe(monster=True, monster_kind=None, identity=b"unknown monster")
        self.assertTrue(unknown["pending"])
        self.assertNotEqual(unknown["state"], "kill")

    def test_unreadable_badges_never_default_to_one(self):
        for texts in ([], [None], ["■"], ["1x"], ["1", "7"], ["0"], ["1000"]):
            self.assertIsNone(e.spear_count(texts), texts)
        for value in (1, 17, 60, 254):
            self.assertEqual(e.spear_count([str(value)]), value)

    def test_target_or_stack_switch_resets_estimated_kill_confirmation(self):
        for _ in range(3): self.observe(identity=b"a", hp=None, stacks=4)
        self.assertEqual(self.w.result["state"], "kill")
        self.assertEqual(self.observe(identity=b"b", hp=None, stacks=1)["state"], "close")

    def test_unknown_digit_after_switch_never_retains_line(self):
        self.observe(identity=b"enemy1")
        self.assertIsNone(self.observe(identity=b"enemy2", stacks=None))

    def test_result_publishes_a_complete_immutable_bar_snapshot(self):
        self.w.rect = (100, 200, 2148, 2760)
        first = self.observe(identity=b"enemy1")
        self.assertEqual(first["bar"], (417, 261, 640, 291))
        self.w.origin = (20, 30)
        second = self.observe(identity=b"enemy1")
        self.assertEqual(second["bar"], (437, 291, 660, 321))
        self.assertEqual(first["bar"], (417, 261, 640, 291))

    def test_misread_max_hp_never_moves_the_line(self):
        first = self.observe(identity=b"dummy", hp=1959, max_hp=3120, fill=1959/3120)
        for bad in (dict(hp=42298, max_hp=73120), dict(hp=None, max_hp=875270),
                    dict(hp=290, max_hp=1120)):
            with self.subTest(bad=bad):
                result = self.observe(identity=b"dummy", fill=1959/3120, **bad)
                self.assertEqual(result["max_hp"], 3120)
                self.assertAlmostEqual(result["dmg"] / result["max_hp"], first["dmg"] / 3120)
                self.assertEqual(result["target"], first["target"])

    def test_real_max_hp_change_is_taken_after_three_frames(self):
        self.observe(identity=b"dummy", hp=1000, max_hp=2000, fill=.5)
        for _ in range(2):
            self.assertEqual(self.observe(identity=b"dummy", hp=1100, max_hp=2200, fill=.5)["max_hp"], 2000)
        self.assertEqual(self.observe(identity=b"dummy", hp=1100, max_hp=2200, fill=.5)["max_hp"], 2200)

    def test_new_target_waits_for_its_armor(self):
        self.observe(identity=b"enemy1", armor=200)
        self.assertIsNone(self.observe(identity=b"enemy2", armor=None))

    def test_digit_learning_reads_new_combinations_without_ocr(self):
        one = np.array([[0,1,0], [1,1,0], [0,1,0], [0,1,0], [1,1,1]], dtype=bool)
        two = np.array([[1,1,1], [0,0,1], [1,1,1], [1,0,0], [1,1,1]], dtype=bool)
        gap = np.zeros((5, 1), dtype=bool)
        with patch.dict(e._digit_cache, {}, clear=True), patch.dict(e._group_cache, {}, clear=True):
            e._remember_digits("stacks", np.hstack((one, gap, two)), "12")
            self.assertEqual(e._known_text("stacks", "new", np.hstack((two, gap, one))), "21")
            self.assertIsNone(e._known_text("armor", "new", one))
            e._remember_digits("stacks", one, "7")  # ambiguous training never guessed
            self.assertIsNone(e._known_text("stacks", "new", one))


if __name__ == "__main__":
    unittest.main()

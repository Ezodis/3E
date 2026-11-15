"""Replay the user's failing frames through the actual OCR and fast reader."""
import json
from pathlib import Path
import sys
import unittest

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import lol_execute as e
import lol_monsters as monsters

FIXTURES = Path(__file__).parent / "fixtures"


class TargetFramesTest(unittest.TestCase):
    def test_gromp_announcement_does_not_become_epic_or_one_spear(self):
        with Image.open(FIXTURES / "gromp-announcement.png") as frame:
            obs, _ = e.read_target(frame, 1)
            quick = e.quick_read(frame, 1)
        for value in (obs, quick):
            self.assertEqual(value["hp"], 2695)
            self.assertEqual(value["max_hp"], 2870)
            self.assertEqual(value["monster_kind"], ("sru_gromp", False))
            self.assertIsNone(value["stacks"])

    def test_actual_one_hp_frame_reads_seventeen_spears(self):
        with Image.open(FIXTURES / "dummy-1hp-17spears.png") as frame:
            obs, _ = e.read_target(frame, 1)
            quick = e.quick_read(frame, 1)
        for value in (obs, quick):
            self.assertEqual((value["hp"], value["max_hp"], value["stacks"]), (1, 1000, 17))
            self.assertFalse(value["monster"])

    def test_monster_classifier_at_hud_scales_and_unknowns(self):
        frame = Image.open(FIXTURES / "gromp-announcement.png").convert("RGB")
        for scale in (.5, .75, 1, 1.5, 2):
            scaled = frame.resize((round(frame.width*scale), round(frame.height*scale)))
            self.assertEqual(monsters.identify_monster(scaled, scale), ("sru_gromp", False))
        for color in ("black", "red", "white"):
            self.assertIsNone(monsters.identify_monster(Image.new("RGB", (602, 258), color), 1))

    def test_bundled_epic_and_ordinary_art_and_obscured_portraits(self):
        root = Path(monsters.__file__).parent
        entries = json.loads((root / "lol_monsters.json").read_text())["entries"]
        with Image.open(root / "lol_monsters.png") as atlas:
            for entry in entries:
                frame = Image.new("RGB", (602, 258))
                frame.paste(atlas.crop(entry["box"]).resize((90, 90)), (219, 26))
                result = monsters.identify_monster(frame, 1)
                self.assertIsNotNone(result, entry["name"])
                self.assertEqual(result[1], entry["epic"], entry["name"])
                ImageDraw.Draw(frame).rectangle((220, 28, 308, 110), fill="black")
                self.assertIsNone(monsters.identify_monster(frame, 1))


if __name__ == "__main__":
    unittest.main()

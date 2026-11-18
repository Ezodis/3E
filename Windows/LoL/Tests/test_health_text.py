"""The HP text reader on drawn target panels: slash, current-HP tick, bar edges, lost-HP trail."""
import sys
import unittest
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import lol_execute as e

FONT = ImageFont.truetype("segoeuib.ttf", 25)   # ~18 px digits, like the HUD at reference size


def panel(hp, max_hp, tick=True, trail=0.0, tick_through=False, edges=False):
    """A target panel at reference scale: red bar to hp/max (plus a darker lost-HP trail),
    the white 'hp / max' text, the cyan current-HP tick, optional bar edge lines."""
    frame = Image.new("RGB", (602, 258), (8, 14, 14))
    d = ImageDraw.Draw(frame)
    x0, y0, x1, y1 = e.HEALTH_BAR
    w = x1 - x0
    cur = x0 + round(w * hp / max_hp)
    if trail:
        d.rectangle((cur, y0, x0 + round(w * trail), y1), fill=(100, 10, 10))
    if cur > x0:
        d.rectangle((x0, y0, cur - 1, y1), fill=(170, 30, 25))
    text = f"{hp} / {max_hp}"
    tw = d.textlength(text, font=FONT)
    tx = (x0 + x1) / 2 - tw / 2
    if edges:
        d.line((x0 + 4, y0, x0 + 4, y1), fill=(230, 230, 230), width=2)
    if tick:   # the HUD draws the tick under the text
        tick_x = cur if not tick_through else round(tx + d.textlength(f"{hp} / ", font=FONT) + 5)
        d.line((tick_x, y0 - 1, tick_x, y1), fill=(150, 235, 245), width=3)
    d.text((tx, y0 + 2), text, font=FONT, fill=(245, 245, 245))
    return frame


class HealthTextTest(unittest.TestCase):
    def read(self, frame):
        obs, raw = e.read_target(frame, 1)
        return obs["hp"], obs["max_hp"], raw

    def test_plain_text_reads_both_numbers(self):
        for hp, mx in ((1528, 2660), (592, 2368), (6, 1000), (2980, 5270)):
            with self.subTest(hp=hp):
                self.assertEqual(self.read(panel(hp, mx))[:2], (hp, mx))

    def test_tick_through_a_digit_is_not_part_of_it(self):
        frame = panel(1660, 3063, tick_through=True)
        texts = e.read_numbers(frame.crop(e.REGIONS["health"]), "health", 1)
        self.assertEqual(texts, ["1660", "/", "3063"])

    def test_bar_edge_lines_are_not_digits(self):
        texts = e.read_numbers(panel(55, 1060, edges=True).crop(e.REGIONS["health"]), "health", 1)
        self.assertEqual(texts, ["55", "/", "1060"])

    def test_trail_without_tick_still_accepts_the_real_text(self):
        frame = panel(6, 1000, tick=False, trail=0.045)
        self.assertEqual(self.read(frame)[:2], (6, 1000))

    def test_tick_is_the_bar_position_not_the_trail(self):
        frame = panel(592, 2368, trail=0.62)
        self.assertAlmostEqual(e.bar_fill(frame, 1), 592 / 2368, delta=0.01)

    def test_text_that_disagrees_with_the_tick_is_rejected(self):
        frame = panel(592, 2368)
        self.assertFalse(e.health_agrees((42, 68), frame, 1, e.bar_fill(frame, 1)))
        self.assertTrue(e.health_agrees((592, 2368), frame, 1, e.bar_fill(frame, 1)))

    def test_only_digits_slash_digits_parse(self):
        for groups in (["55/", "1060"], ["[", "16", "1200"], ["1", "/", ""], ["1660", "/"],
                       ["4b4", "/", "1463"], ["1200", "/", "16"]):
            self.assertIsNone(e.parse_health(groups), groups)
        self.assertEqual(e.parse_health(["592", "/", "2368"]), (592, 2368))


if __name__ == "__main__":
    unittest.main()

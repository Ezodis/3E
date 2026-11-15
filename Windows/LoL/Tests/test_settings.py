import copy
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import lol_settings as s


class SettingsTest(unittest.TestCase):
    def test_mb5_and_n_migrate_in_chords(self):
        self.assertEqual(s.convert("evtCastAvatarSpell1", "[Button 5],[Alt][Button 5]"),
                         "[F10],[Alt][F10]")
        self.assertEqual(s.convert("evtUseItem6", "[n],[Alt][n]"), "[j],[Alt][j]")
        self.assertEqual(s.convert("evtCameraSnap", "[Button 5]"), "[F10]")

    def test_ini_idempotent_and_wasd_untouched(self):
        before = "[GameEvents]\nevtCastAvatarSpell1=[Button 5]\nevtUseItem6=[n]\n[WASD]\nevtCameraSnap=[Button 5]\n"
        after = s.patch_ini(before)
        self.assertEqual(s.patch_ini(after), after)
        self.assertIn("evtCastAvatarSpell1=[F10]", after)
        self.assertIn("[WASD]\nevtCameraSnap=[Button 5]", after)
        self.assertIn("evtPlayerPingRadialDanger=[.]", after)

    def test_json_idempotent_and_wasd_untouched(self):
        before = {"files": [{"name": "Input.ini", "sections": [
            {"name": "GameEvents", "settings": [{"name": "evtCastAvatarSpell1", "value": "[Button 5]"}]},
            {"name": "WASD", "settings": [{"name": "evtCameraSnap", "value": "[Button 5]"}]}]}]}
        after = s.patch_json(copy.deepcopy(before))
        self.assertEqual(s.patch_json(copy.deepcopy(after)), after)
        self.assertEqual(after["files"][0]["sections"][1], before["files"][0]["sections"][1])


if __name__ == "__main__":
    unittest.main()

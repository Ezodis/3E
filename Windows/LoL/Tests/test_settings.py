import copy
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import lol_settings as s


class SettingsTest(unittest.TestCase):
    def test_win_binds_move_to_n_in_chords(self):
        self.assertEqual(s.convert("evtCastSpell4", "[L Win]"), "[n]")
        self.assertEqual(s.convert("evtCastAvatarSpell2", "[L Win],[Alt][L Win]"), "[n],[Alt][n]")
        self.assertEqual(s.convert("evtUseItem1", "[j],[L Win]"), "[n]")

    def test_mb5_stays_on_league(self):
        self.assertEqual(s.convert("evtCastAvatarSpell1", "[Button 5]"), "[Button 5]")
        self.assertEqual(s.convert("evtCameraSnap", "[Button 5]"), "[Button 5]")

    def test_j_is_only_recall_and_unused_binds_are_removed(self):
        for name in ("evtUseItem6", "evtSmartCastItem6", "evtCastRoleBound", "evtEmoteTaunt",
                     "evtReciprocityMyBadTrigger", "evtChampMasteryDisplay"):
            self.assertEqual(s.convert(name, "[j]"), "", name)
        self.assertEqual(s.convert("evtUseItem7", "[j]"), "[j]")
        self.assertEqual(s.convert("evtSmartCastSpell4", "[j],[o]"), "[o]")

    def test_m_opens_both_quick_wheels(self):
        self.assertIn("[m]", s.convert("evtRadialEmoteInstantOpen", "[Cmd][Button 1],[Cmd][Button 2]"))
        self.assertIn("[m]", s.convert("evntPlayerPing", ""))
        self.assertEqual(s.convert("evtRadialEmoteOpen", "[m]"), "")

    def test_ini_idempotent_and_wasd_untouched(self):
        before = ("[GameEvents]\nevtCastSpell4=[L Win]\nevtUseItem6=[j]\nevtRadialEmoteOpen=[m]\n"
                  "[WASD]\nevtCastSpell4=[L Win]\n")
        after = s.patch_ini(before)
        self.assertEqual(s.patch_ini(after), after)
        self.assertIn("evtCastSpell4=[n]", after)
        self.assertIn("evtUseItem6=\n", after)
        self.assertIn("[WASD]\nevtCastSpell4=[L Win]", after)
        self.assertIn("evtRadialEmoteInstantOpen=[m],[Cmd][Button 2]", after)

    def test_json_idempotent_and_wasd_untouched(self):
        before = {"files": [{"name": "Input.ini", "sections": [
            {"name": "GameEvents", "settings": [{"name": "evtCastSpell4", "value": "[L Win]"}]},
            {"name": "WASD", "settings": [{"name": "CastSpell4", "value": "[L Win]"}]}]}]}
        after = s.patch_json(copy.deepcopy(before))
        self.assertEqual(s.patch_json(copy.deepcopy(after)), after)
        self.assertEqual(after["files"][0]["sections"][1], before["files"][0]["sections"][1])
        game = {st["name"]: st["value"] for st in after["files"][0]["sections"][0]["settings"]}
        self.assertEqual(game["evtCastSpell4"], "[n]")
        self.assertNotIn("evtUseItem6", game)   # unbound keys are not added


if __name__ == "__main__":
    unittest.main()

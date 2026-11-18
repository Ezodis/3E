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
        self.assertEqual(s.convert("evtUseItem1", "[j],[L Win]"), "[b],[n]")

    def test_mb5_stays_on_league(self):
        self.assertEqual(s.convert("evtCastAvatarSpell1", "[Button 5]"), "[Button 5]")
        self.assertEqual(s.convert("evtCameraSnap", "[Button 5]"), "[Button 5]")

    def test_b_and_n_keep_everything_they_did_at_once(self):
        b = {"evtUseItem7", "evtCastRoleBound", "evtUseItem1", "evtSmartCastItem6",
             "evtReciprocityMyBadTrigger"}
        n = {"evtSmartCastSpell4", "evtUseItem1", "evtUseItem6", "evtEmoteTaunt"}
        for name in b:
            self.assertIn("[b]", s.convert(name, ""), name)
        self.assertEqual(s.convert("evtOpenShop", "[b]"), "[F11]")   # a B tap never opens the shop
        for name in n | {"evtCastSpell4", "evtCastAvatarSpell2", "evtSmartCastAvatarSpell2"}:
            self.assertIn("[n]", s.convert(name, "[L Win]"), name)
        self.assertEqual(s.convert("evtChampMasteryDisplay", ""), "[Button 5]")
        self.assertEqual(s.convert("evtSmartCastSpell1", ""), "[Tab]")
        self.assertEqual(s.convert("evtSmartCastSpell3", ""), "[space]")

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
        self.assertIn("evtUseItem6=[n]\n", after)
        self.assertIn("evtRadialEmoteOpen=\n", after)
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
        self.assertEqual(game["evtEmoteTaunt"], "[n]")          # missing binds are added
        self.assertNotIn("evtRadialEmoteOpen", game)            # unbound keys are not added


if __name__ == "__main__":
    unittest.main()

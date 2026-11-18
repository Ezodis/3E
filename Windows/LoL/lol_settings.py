"""Patch League keybinds in input.ini AND PersistedSettings.json (backs both up first).

lol.py applies this by itself whenever League and its client are closed (the client rewrites
both files while it runs). It can also be run by hand, with League closed:
    python lol_settings.py
Applying it again changes nothing.
"""
import json, re, shutil, time
from pathlib import Path

CFG = Path(r"C:\Riot Games\League of Legends\Config")
INI = CFG / "input.ini"
JSON = CFG / "PersistedSettings.json"

# 1) Key moves applied to every binding. Win is now lol.py's camera key (tap = lock/unlock,
#    hold = drag), so everything League had on Win (R, summoner 2, item 1) moves to N, which the
#    macros no longer use. A move, not a swap: running setup twice must do nothing.
SWAP = {"[L Win]": "[n]"}

# 2) Explicit bindings set after the move ("" = unbound)
SET = {
    "evtOpenShop": "[b]",                         # B hold = shop (sent by lol.py)
    "evtRadialEmoteOpen": "",                     # M opens the quick emote wheel below instead
    "evtRadialEmoteInstantOpen": "[m],[Cmd][Button 2]",  # M = quick emote wheel
    "evntPlayerPing": "[Cmd][Button 1],[m]",      # M = quick ping wheel too
    "evntPlayerPingCursorDanger": "",
    "evtChatHistory": "[Alt][k],[Button 3]",      # MB3 = chat history
    "evtHoldShowScoreBoard": "[Alt][k],[Button 3]",  # MB3 = scoreboard
    "evtPlayerStopPosition": "[v]",               # stop (sent by lol.py while holding Space)
    "evtPlayerAttackMove": "[space],[F9]",        # F9: attack-move sent by the kite button
    "evtCameraLockToggle": "[y]",                 # sent by lol.py (Win tap toggles, Win hold drags)
    "FreeDynamicCameraToggle": "",                # off: on h it flipped camera modes on every pan
    "evtOnUIMouse4Pan": "[h]",                    # lol.py holds h while Win is held
    # J is only Recall now (B tap sends J). Its other binds fired together with Recall.
    "evtUseItem7": "[j]",                         # Recall
    "evtUseItem1": "[n]",                         # item 1 (was J + Win)
    "evtUseItem6": "",                            # item 6 on J
    "evtSmartCastItem6": "",                      # item 6 smart cast on J
    "evtSmartCastSpell4": "[o]",                  # R smart cast on J (R stays on N, quick cast)
    "evtCastRoleBound": "",                       # role quest teleport on J
    "evtEmoteTaunt": "",                          # taunt emote on J
    "evtReciprocityMyBadTrigger": "",             # "my bad" on Win
    "evtChampMasteryDisplay": "",                 # mastery badge on MB5 (every Flash)
    # Same key as the plain cast, which is already quick cast (Quickbinds = 1)
    "evtSmartCastAvatarSpell2": "",
    "evtSmartCastSpell1": "",
    "evtSmartCastSpell3": "",
}

# What SET unbinds, for the summary lol.py logs and the README.
REMOVED = {
    "evtRadialEmoteOpen": "M: normal emote wheel (M now opens the quick one)",
    "evtUseItem6": "J: item 6", "evtSmartCastItem6": "J: item 6 smart cast",
    "evtSmartCastSpell4": "J: R smart cast", "evtUseItem1": "J: item 1",
    "evtCastRoleBound": "J: role quest teleport", "evtEmoteTaunt": "J: taunt emote",
    "evtReciprocityMyBadTrigger": "Win: \"my bad\"", "evtChampMasteryDisplay": "MB5: mastery badge",
    "evtSmartCastAvatarSpell2": "Win: duplicate summoner 2 smart cast",
    "evtSmartCastSpell1": "Tab: duplicate Q smart cast", "evtSmartCastSpell3": "Space: duplicate E smart cast",
}


def convert(name, value):
    if name in SET:
        return SET[name]
    if not value:
        return value
    return re.sub(r"\[L Win\]", lambda m: SWAP[m[0]], value)


def patch_ini(text):
    out = []
    section = None
    for line in text.splitlines():
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1]
        m = re.match(r"^(evt\w+|evnt\w+|FreeDynamicCameraToggle)=(.*)$", line)
        if m and section in ("GameEvents", "HUDEvents"):
            line = f"{m[1]}={convert(m[1], m[2])}"
        out.append(line)
    section, seen = None, set()
    for line in out:
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1]
        elif section in ("GameEvents", "HUDEvents") and "=" in line:
            seen.add(line.split("=", 1)[0])
    # add any bound SET keys missing from [GameEvents]
    missing = [k for k in SET if k not in seen and SET[k]]
    if missing:
        i = out.index("[GameEvents]") + 1
        out[i:i] = [f"{k}={SET[k]}" for k in missing]
    return "\n".join(out) + "\n"


def patch_json(data):
    # Only the normal-mode sections of Input.ini (leaves the WASD profile alone)
    for f in data["files"]:
        if f["name"].lower() != "input.ini":
            continue
        secs = [s for s in f["sections"] if s["name"] in ("GameEvents", "HUDEvents")]
        names = {st["name"] for s in secs for st in s["settings"]}
        for s in secs:
            for st in s["settings"]:
                st["value"] = convert(st["name"], st["value"])
        game = next(s for s in secs if s["name"] == "GameEvents")
        for k, v in SET.items():
            if k not in names and v:
                game["settings"].append({"name": k, "value": v})
    return data


LEAGUE_PROCESSES = ("LeagueClient.exe", "LeagueClientUx.exe", "League of Legends.exe")


def league_running():
    import subprocess
    out = subprocess.check_output(["tasklist", "/FO", "CSV", "/NH"], text=True,
                                  creationflags=subprocess.CREATE_NO_WINDOW).lower()
    return any(f'"{p.lower()}"' in out for p in LEAGUE_PROCESSES)


def apply():
    """Writes the binds if they differ (backing both files up first). Returns True if it wrote.
    Never writes while League or its client runs."""
    if league_running():
        return False
    ini_text = INI.read_text(encoding="utf-8")
    json_text = JSON.read_text(encoding="utf-8")
    new_ini = patch_ini(ini_text)
    data = json.loads(json_text)
    before = json.dumps(data, sort_keys=True)
    data = patch_json(data)
    json_changed = json.dumps(data, sort_keys=True) != before
    if new_ini == ini_text and not json_changed:
        return False
    stamp = time.strftime("%Y%m%d-%H%M%S")
    for f in (INI, JSON):
        shutil.copy2(f, f.with_name(f"{f.name}.bak-{stamp}"))
    INI.write_text(new_ini, encoding="utf-8")
    if json_changed:
        JSON.write_text(json.dumps(data, indent=4), encoding="utf-8")
    return True


def main():
    if league_running():
        raise SystemExit("Close League and its client before updating keybinds. No files changed.")
    print("Patched (backups *.bak-<time> in the Config folder)." if apply() else "Already up to date.")


if __name__ == "__main__":
    main()

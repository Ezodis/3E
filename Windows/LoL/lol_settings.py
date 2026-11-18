"""Patch League keybinds in input.ini AND PersistedSettings.json (backs both up first).

lol.py applies this by itself whenever no match is running, then keeps both files read-only:
the League client otherwise replaces them with Riot's online copy each time it opens.
It can also be run by hand outside a match:
    python lol_settings.py
Applying it again changes nothing.
"""
import json, re, shutil, time
from pathlib import Path

CFG = Path(r"C:\Riot Games\League of Legends\Config")
INI = CFG / "input.ini"
JSON = CFG / "PersistedSettings.json"

# 1) Key moves applied to every other binding: Win is the camera key, so what League had on
#    Win (R, summoner 2, item 1) lives on M; N (where it sat before) moves to M too. A move, not
#    a swap: running setup twice must do nothing.
SWAP = {"[L Win]": "[m]", "[n]": "[m]"}

# 2) Explicit bindings set after the move ("" = unbound). A macro key's tap sends the key
#    itself, so its binds sit on that key; a hold sends the separate key noted.
SET = {
    "evtOpenShop": "[v]",                         # B hold = shop (lol.py sends V)
    "evtRadialEmoteOpen": "",                     # N opens the quick emote wheel below instead
    "evtRadialEmoteInstantOpen": "[n],[Cmd][Button 2]",  # N = quick emote wheel
    "evntPlayerPing": "[Cmd][Button 1],[n]",      # N = quick ping wheel too
    "evntPlayerPingCursorDanger": "",
    "evtChatHistory": "[Alt][k],[Button 3]",      # MB3 = chat history
    "evtHoldShowScoreBoard": "[Alt][k],[Button 3]",  # MB3 = scoreboard
    "evtPlayerStopPosition": "[c]",               # Space hold = stop (lol.py sends C)
    "evtPlayerAttackMove": "[space],[F9]",        # F9: attack-move sent by the kite button
    "evtCameraLockToggle": "[L Win]",             # Win tap = Win itself (lol.py stops Start opening)
    "evtCastSpell4": "[m],[F8]",                  # R on M; F8 = R alone (M hold)
    "evtCastAvatarSpell2": "[m]",                 # summoner 2 on M (a tap only)
    "FreeDynamicCameraToggle": "",                # off: on h it flipped camera modes on every pan
    "evtOnUIMouse4Pan": "[h]",                    # lol.py holds h while Win is held
    # Everything a key did at once still happens at once:
    # B tap: Recall, role quest teleport, item 1, item 6 smart cast and "my bad".
    "evtUseItem7": "[b]",                         # Recall
    "evtCastRoleBound": "[b]",                    # role quest teleport
    "evtSmartCastItem6": "[b]",                   # item 6 smart cast
    "evtReciprocityMyBadTrigger": "[b]",          # "my bad" (was on Win)
    "evtUseItem1": "[b],[m]",                     # item 1 on B and M
    # M tap: R, summoner 2, item 1, plus R smart cast, item 6 and taunt.
    "evtSmartCastSpell4": "[m],[o]",              # R smart cast
    "evtUseItem6": "[m]",                         # item 6
    "evtEmoteTaunt": "[m]",                       # taunt emote
    "evtSmartCastAvatarSpell2": "[m]",            # summoner 2 smart cast (with M's cast)
    "evtSmartCastSpell1": "[Tab]",
    "evtSmartCastSpell3": "[space]",
    "evtChampMasteryDisplay": "[Button 5]",       # MB5 shows the mastery badge, as before
}

# What lol.py logs once the binds are written.
SUMMARY = ("B tap: Recall, role quest teleport, item 1, item 6 smart cast, my bad; B hold: shop (V); "
           "M tap: R, R smart cast, summoner 2, item 1, item 6, taunt; M hold: R alone (F8); "
           "N: quick ping and quick emote wheels; Win tap: camera lock (Win), hold: drag; "
           "Space hold: stop (C); MB5: League's binds + mastery badge")


def convert(name, value):
    if name in SET:
        return SET[name]
    if not value:
        return value
    return re.sub(r"\[L Win\]|\[n\]", lambda m: SWAP[m[0]], value)


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


def game_running():
    import subprocess
    out = subprocess.check_output(["tasklist", "/FO", "CSV", "/NH"], text=True,
                                  creationflags=subprocess.CREATE_NO_WINDOW).lower()
    return '"league of legends.exe"' in out


def set_read_only(path, on):
    import stat
    mode = path.stat().st_mode
    path.chmod(mode & ~stat.S_IWRITE if on else mode | stat.S_IWRITE)


def apply():
    """Writes the binds if they differ (backing both files up first), then keeps both files
    read-only. Returns True if it wrote. The League client replaces these files with the
    settings Riot stores online every time it opens; read-only files keep these binds. (Binds
    changed in League's own settings then don't save: the macros' binds always win.)
    Never writes during a match; the client may be open."""
    if game_running():
        return False
    ini_text = INI.read_text(encoding="utf-8")
    json_text = JSON.read_text(encoding="utf-8")
    new_ini = patch_ini(ini_text)
    data = json.loads(json_text)
    before = json.dumps(data, sort_keys=True)
    data = patch_json(data)
    json_changed = json.dumps(data, sort_keys=True) != before
    wrote = False
    if new_ini != ini_text or json_changed:
        stamp = time.strftime("%Y%m%d-%H%M%S")
        for f in (INI, JSON):
            shutil.copy2(f, f.with_name(f"{f.name}.bak-{stamp}"))
            set_read_only(f, False)
        INI.write_text(new_ini, encoding="utf-8")
        if json_changed:
            JSON.write_text(json.dumps(data, indent=4), encoding="utf-8")
        wrote = True
    for f in (INI, JSON):
        set_read_only(f, True)
    return wrote


def main():
    if game_running():
        raise SystemExit("Finish the League match before updating keybinds. No files changed.")
    print("Patched (backups *.bak-<time> in the Config folder)." if apply() else "Already up to date.")


if __name__ == "__main__":
    main()

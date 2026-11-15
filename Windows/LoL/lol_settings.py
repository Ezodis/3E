"""Patch League keybinds in input.ini AND PersistedSettings.json (backs both up first).

Run with League (client + game) CLOSED, otherwise the client may overwrite the files:
    python lol_settings.py
"""
import json, re, shutil, time
from pathlib import Path

CFG = Path(r"C:\Riot Games\League of Legends\Config")
INI = CFG / "input.ini"
JSON = CFG / "PersistedSettings.json"

# 1) Key swaps applied to every binding (simultaneously, so B->N doesn't then become N->Win).
#    Later change: lol.py now uses N itself, so the binds on [n] were moved again to [j]
#    (B clicks send j). MB5's binds were moved to [F10] too: League reads mouse buttons below
#    the input hook, so only the macro (an MB5 click) may send them.
# Final migration, not a repeated key swap: running setup twice must do nothing.
SWAP = {"[n]": "[j]", "[Button 5]": "[F10]"}

# 2) Explicit bindings set after the swap
SET = {
    "evtOpenShop": "[b]",                         # B = shop
    "evtRadialEmoteOpen": "[m]",                  # M = emote wheel
    "evntPlayerPing": "[Cmd][Button 1],[m]",      # M = ping wheel too
    "evtPlayerPingRadialDanger": "[.]",           # . = danger (retreat) ping wheel
    "evntPlayerPingCursorDanger": "",
    "evtCameraSnap": "[F10]",                     # emitted only on an MB5 tap
    "evtChatHistory": "[Alt][k],[Button 3]",      # MB3 = chat history
    "evtHoldShowScoreBoard": "[Alt][k],[Button 3]",  # MB3 = scoreboard
    "evtPlayerStopPosition": "[v]",               # stop (sent by lol.py while holding Space)
    "evtPlayerAttackMove": "[space],[F9]",        # F9: attack-move sent by the MB5 kite
    "evtCameraLockToggle": "[y]",                 # sent by lol.py (N click toggles, N hold drags)
    "FreeDynamicCameraToggle": "",                # off: on h it flipped camera modes on every Space pan
    "evtOnUIMouse4Pan": "[h]",                    # lol.py holds h while N is held
}


def convert(name, value):
    if name in SET:
        return SET[name]
    if not value:
        return value
    return re.sub(r"\[n\]|\[Button 5\]", lambda m: SWAP[m[0]], value)


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
    # add any SET keys missing from [GameEvents]
    missing = [k for k in SET if k not in seen]
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
            if k not in names:
                game["settings"].append({"name": k, "value": v})
    return data


def main():
    import subprocess
    for process in ("LeagueClient.exe", "LeagueClientUx.exe", "League of Legends.exe"):
        running = subprocess.check_output(
            ["tasklist", "/FI", f"IMAGENAME eq {process}", "/FO", "CSV", "/NH"],
            text=True, creationflags=subprocess.CREATE_NO_WINDOW)
        if process.lower() in running.lower():
            raise SystemExit("Close League and its client before updating keybinds. No files changed.")
    stamp = time.strftime("%Y%m%d-%H%M%S")
    for f in (INI, JSON):
        shutil.copy2(f, f.with_name(f"{f.name}.bak-{stamp}"))
    INI.write_text(patch_ini(INI.read_text(encoding="utf-8")), encoding="utf-8")
    data = json.loads(JSON.read_text(encoding="utf-8"))
    JSON.write_text(json.dumps(patch_json(data), indent=4), encoding="utf-8")
    print(f"Patched. Backups: *.bak-{stamp} in {CFG}")


if __name__ == "__main__":
    main()

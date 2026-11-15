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
#    (B clicks send j).
SWAP = {"[n]": "[L Win]", "[b]": "[n]"}

# 2) Explicit bindings set after the swap
SET = {
    "evtOpenShop": "[b]",                         # B = shop
    "evtRadialEmoteOpen": "[m]",                  # M = emote wheel
    "evntPlayerPing": "[Cmd][Button 1],[m]",      # M = ping wheel too
    "evtPlayerPingRadialDanger": "",              # no retreat wheel
    "evntPlayerPingCursorDanger": "[.]",          # . = retreat ping at the cursor
    "evtCameraSnap": "[Button 5]",                # MB5 = center camera
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
    parts = value.split(",")
    return ",".join(SWAP.get(p.strip(), p) for p in parts)


def patch_ini(text):
    out = []
    for line in text.splitlines():
        m = re.match(r"^(evt\w+|evnt\w+|FreeDynamicCameraToggle)=(.*)$", line)
        if m:
            line = f"{m[1]}={convert(m[1], m[2])}"
        out.append(line)
    seen = {re.match(r"^([^=]+)=", l)[1] for l in out if re.match(r"^[^=\[]+=", l)}
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
    stamp = time.strftime("%Y%m%d-%H%M%S")
    for f in (INI, JSON):
        shutil.copy2(f, f.with_name(f"{f.name}.bak-{stamp}"))
    INI.write_text(patch_ini(INI.read_text(encoding="utf-8")), encoding="utf-8")
    data = json.loads(JSON.read_text(encoding="utf-8"))
    JSON.write_text(json.dumps(patch_json(data), indent=4), encoding="utf-8")
    print(f"Patched. Backups: *.bak-{stamp} in {CFG}")


if __name__ == "__main__":
    main()

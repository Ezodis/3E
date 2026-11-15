# 3£ LoL macros

Run through **3£ → LoL macros** (the `3£ LoL macros` scheduled task).
Do not run another copy alongside it. Runtime files go in
`%LOCALAPPDATA%\3EWindows\LoL`; the installed scripts stay read-only.

The controls activate only for Kalista while the League game has focus. N toggles
camera lock on tap and pans on hold; B taps J and holds to open the shop; Space
taps Space and holds Stop; MB5 taps F10 and holds to kite. Scroll cycles the held
number keys. Release, focus loss, or leaving Kalista cancels a hold permanently.

`lol_settings.py` migrates N bindings to J and MB5 bindings to F10, including
modified chords. It backs up both League configuration files before writing,
refuses to run while League or its client is open, and can be rerun without
moving bindings again. League must restart to load changed bindings; an in-memory
MB5 → Flash binding cannot be suppressed reliably by a Windows mouse hook.

The Rend line shows **current-health coverage**: `damage / current HP`, capped at
100%. It moves right as damage rises or HP falls. Halfway means Rend removes half
of the selected target's current HP; the far right means it covers all of it.
For example, 600/1000 HP with 300 damage puts the line halfway across;
1/1000 HP with 730 damage puts it at the far right. Positions are never smoothed
across target switches. This is a coverage gauge, not the underlying bar's HP scale.

Rend uses cached whole numbers and learned individual digit shapes. An unreadable
spear count clears the result immediately, including identical portraits: two
dummies or minions can look the same. It never guesses one spear from an obscured
badge. Lightning requires a fresh, confirmed lethal calculation; there is no
almost-lethal flashing border. Readings older than 250 ms are hidden. Green ally
bars are excluded. An almost empty bar requires enemy evidence (a red bar or a
Rend debuff). Local portrait matching identifies standard jungle monsters using
the artwork and epic-monster tags documented in `lol_monsters.json`. An unrecognized
monster hides the estimate instead of inferring its class from maximum HP. The
25 portrait references are bundled: no network downloads happen during play.
The reader does not detect shields, invulnerability or every temporary damage
modifier; its lethal indication is based on the readable HP, armor, spears and
supported damage modifiers. It never casts Rend automatically.

Diagnostics:

- `lol_runtime.log`: bounded, rotating launcher, thread and rendering errors.
- `lol_status.json`: active state, camera state, current result, rendered marker position
  and current-health coverage, and rendered frame count.
- `lol_execute_log.csv`: results used by the overlay, rather than a separate OCR estimate.
- `lol_debug/kill_*.png`: bounded target snapshots; unchanged kills are throttled.

The overlay is excluded from captures to avoid covering the digits it reads.
Saved target images and status/log files verify the reader; physical observation
is needed to confirm the visible overlay.

Run the regression suite without starting the macros or sending input:

```powershell
py -3.12 -m unittest discover -s Windows/LoL/Tests -v
```

It needs the existing Python 3.12 LoL dependencies (NumPy, Pillow and pynput).
Tests cover timer delays, rapid re-press, focus cancellation, mocked Windows
hooks, idempotent configuration, digit learning and Rend warning decisions.
They do not substitute for physical key/MB5 tests in Practice Tool.

Updates must follow the host's installation policy. A restricted/USB-only update
gate requires review; neither this module nor its tests bypasses that gate.

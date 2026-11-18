# 3£ LoL macros

Run through **3£ → LoL macros** (the `3£ LoL macros` scheduled task).
Do not run another copy alongside it. Runtime files go in
`%LOCALAPPDATA%\3EWindows\LoL`; the installed scripts stay read-only.

The controls activate only for Kalista while the League game has focus. Win toggles
camera lock on tap and pans on hold; the pan starts the instant Win goes down and a
quick release counts as the tap. N reaches League untouched. B taps J (Recall) and
holds to open the shop; Space taps Space and holds Stop; the kite button (F13/Pause)
kites while held. Scroll cycles the held number keys. Release, focus loss, or leaving
Kalista cancels a hold permanently.

`lol_settings.py` moves Win bindings to N (including modified chords), makes M open
both quick wheels (ping and emote), and removes binds nothing uses: J's item 6, item 6
smart cast, R smart cast, item 1, role quest teleport and taunt (J is only Recall),
Win's "my bad", MB5's mastery badge, the normal emote wheel, and smart-cast duplicates
of keys that already quick cast (Tab, Space, Win summoner 2). MB5 stays on League.
lol.py applies it by itself whenever League and its client are closed, backing up
both configuration files before writing; applying it again changes nothing. League
loads the new binds on its next start.

The Clicks accent picker never opens over League or any full-screen window, so held
keys in game stay game input.

The Rend line marks **the HP where Rend kills**: `damage / max HP` along the bar,
capped at 100%. It starts at the left edge and moves right as spears add up; the
red fill shrinks toward it and Rend kills once the fill reaches the line.
HP is read as exactly *digits / digits*: the slash is found by its shape (never OCR'd,
so it can't turn into a 7 or 1), digits are trimmed to the text's own rows, the cyan
current-HP tick and bar edge lines are removed before reading, and a number OCR
can't read as one digit per glyph is unknown rather than guessed. The bar position
comes from League's bright current-HP tick, not the red fill, which still includes
the fading lost-HP trail right after a hit; the HP text must match that tick within
2%, or (with no tick drawn) be no more than the red. Learned digit shapes are saved
in `lol_digits.pkl`, so new targets read instantly from the first second of a game.
A new target never borrows numbers from the last one; until its own are read (or
while a frame is unreadable) the last line stays, muted, no lightning, for at most
250 ms. The line glides to every new position (~80 ms at 60 fps): more spears, a
different target, anything; it only appears in place.
For example, 300 damage on a 1000 max HP target puts the line 30% across.
Positions are never smoothed across target switches.

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

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

Rend uses cached whole numbers and learned individual digit shapes. On a briefly
unreadable number for the same portrait, the threshold stays muted for at most
300 ms; lightning is withheld until a new reading confirms the kill. Green ally
bars are excluded. An almost empty bar requires enemy evidence (a red bar or a
Rend debuff). The existing HP-based epic-monster classification remains a
heuristic; this release does not add target-name or shield recognition.

Diagnostics:

- `lol_runtime.log`: bounded, rotating launcher, thread and rendering errors.
- `lol_status.json`: active state, camera state, current result and rendered frame count.
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

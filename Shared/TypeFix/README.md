# TypeFix

Offline AI correction for fast, messy typing in mixed Spanish (Mexican, Spain, Colombian),
French and English. Shared by the Windows app (now), the Mac app and edy.chat (later).

1. The app remembers the paragraph being typed (memory only; dropped on any cursor move,
   click, shortcut or window switch).
2. Double-tap the red Clicks key. `hints.py` / `KeyboardHints` (C#) find, for each garbled
   chunk, the dictionary words it most likely came from on a QWERTY keyboard.
3. The paragraph and hints go to a local llama.cpp server with `prompt.txt`; it streams three
   readings as JSON, shown as they finish.
4. 1–3 replaces the paragraph; Esc cancels.

| File | Purpose |
|---|---|
| `prompt.txt` | The system prompt. Windows embeds it (a test checks they match). |
| `hints.py` | Reference keyboard-hint matcher (same scoring as the C# one). |
| `samples.json`, `bench.py` | Compare models: `python bench.py http://127.0.0.1:8089 [--hints]`. |

Model: Google Gemma 4 26B-A4B instruct, Q4 (`unsloth/gemma-4-26B-A4B-it-GGUF`). On the test
PC (Core Ultra 9 285H, Arc 140T + RTX PRO 2000 8 GB, both used) it beat Qwen 3.5 9B and
Gemma 4 12B on the samples: 0.90 average similarity, ~6 s for all three readings, the first
sooner. It keeps every word in the language it was written in.

Windows setup: `Windows/TypeFix/Setup-TypeFix.ps1` (downloads to `%LOCALAPPDATA%\3EWindows\AI`).
Word lists: hermitdave/FrequencyWords (MIT).

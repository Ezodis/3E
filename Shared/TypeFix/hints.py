"""Keyboard-aware word hints for TypeFix.

For every typed token that is not a known word, find the dictionary words (English, Spanish,
French) it most likely came from, given QWERTY neighbours: extra keys hit next to the intended
key, neighbour substitutions, missing letters. Also tries joining a token with the next one
(a stray space). The hints are given to the model with the typed text.

    python hints.py "tyhikoloiunmg wjth berjuinhg"
"""
import math, sys, unicodedata
from functools import lru_cache
from pathlib import Path

ROWS = ["1234567890", "qwertyuiop", "asdfghjkl", "zxcvbnm"]
POS = {c: (r, i + (0.5 * r if r else 0)) for r, row in enumerate(ROWS) for i, c in enumerate(row)}


def near(a, b):
    if a == b:
        return True
    if a not in POS or b not in POS:
        return False
    (r1, c1), (r2, c2) = POS[a], POS[b]
    return abs(r1 - r2) <= 1 and abs(c1 - c2) <= 1.5


def fold(s):
    return "".join(c for c in unicodedata.normalize("NFD", s.lower()) if unicodedata.category(c) != "Mn")


def cost(typed, word):
    """Edit cost of producing `typed` when meaning `word` (both folded)."""
    n, m = len(typed), len(word)
    prev = [j * 1.5 for j in range(m + 1)]  # missing letters cost 1.5
    for i in range(1, n + 1):
        t = typed[i - 1]
        cur = [prev[0] + 1.0] + [0.0] * m
        for j in range(1, m + 1):
            w = word[j - 1]
            sub = prev[j - 1] + (0 if t == w else 0.6 if near(t, w) else 2.0)
            # an extra key next to the intended letter (or a repeat) is cheap
            extra = prev[j] + (0.35 if near(t, w) or (i > 1 and near(t, typed[i - 2])) else 1.2)
            miss = cur[j - 1] + 1.5
            cur[j] = min(sub, extra, miss)
        prev = cur
    return prev[m]


class Dictionary:
    def __init__(self, folder):
        self.words = {}  # folded -> (best spelling, log frequency, language)
        for lang in ("en", "es", "fr"):
            for line in (Path(folder) / f"{lang}.txt").read_text(encoding="utf-8").splitlines():
                parts = line.split()
                if len(parts) != 2:
                    continue
                word, freq = parts[0], math.log10(int(parts[1]) + 1)
                key = fold(word)
                if key not in self.words or self.words[key][1] < freq:
                    self.words[key] = (word, freq, lang)
        self.by_first = {}
        for key in self.words:
            self.by_first.setdefault(key[:1], []).append(key)

    def known(self, token):
        return fold(token) in self.words

    def candidates(self, token, limit=3):
        t = fold("".join(c for c in token if c.isalnum()))
        if not t:
            return []
        starts = [c for c in POS if near(c, t[0])] or [t[0]]
        scored = []
        for s in starts:
            for key in self.by_first.get(s, ()):
                if not (len(t) / 3 <= len(key) <= len(t) + 2):
                    continue
                c = cost(t, key) - 0.25 * self.words[key][1]
                scored.append((c, key))
        scored.sort()
        return [self.words[k][0] for _, k in scored[:limit]]


def hints(text, dictionary):
    tokens = text.split()
    out = []
    for i, tok in enumerate(tokens):
        if dictionary.known(tok) or not any(c.isalpha() for c in tok):
            continue
        cands = dictionary.candidates(tok)
        if i + 1 < len(tokens):
            joined = dictionary.candidates(tok + tokens[i + 1], 2)
            cands += [f"{w} (joined with next)" for w in joined]
        out.append(f"{tok}: {', '.join(cands)}")
    return out


if __name__ == "__main__":
    import os
    d = Dictionary(Path(os.environ["LOCALAPPDATA"]) / "3EWindows" / "AI" / "words")
    for line in hints(" ".join(sys.argv[1:]), d):
        print(line)

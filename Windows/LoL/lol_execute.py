"""Kalista Rend (E) execute calculator.

Your stats  -> League Live Client Data API (https://127.0.0.1:2999, only works in a game).
Target info -> read from the target frame (top-left) with RapidOCR:
               current HP, armor, magic resist and the spear stack count on the buff icon.

Rend damage (physical, from the in-game tooltip):
    first spear : [5/15/25/35/45] + 70% AD + 65% AP
    each extra  : [7/14/21/28/35] + [20/27.5/35/42.5/50]% AD + 50% AP
Armor after pen = armor * (1 - %pen) - flat pen/lethality  (magic pen / MR don't matter: it's physical)

Calibrate:  python lol_execute.py --calibrate   (in game, with a target selected)
            -> saves lol_calibration.png in 3£'s data folder (LOCALAPPDATA/3EWindows/LoL).
"""
import json
import re
import ssl
import sys
import threading
import time
import logging
import urllib.request
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageGrab, ImageOps
from lol_monsters import identify_monster

# 3£ installs these scripts read-only under Program Files; logs, snapshots and the pid file go here.
import os
DATA = Path(os.environ.get("LOCALAPPDATA", Path.home())) / "3EWindows" / "LoL"
DATA.mkdir(parents=True, exist_ok=True)

# --- Rend numbers (update if Riot changes Kalista) ---
E_BASE = [5, 15, 25, 35, 45]
E_STACK_BASE = [7, 14, 21, 28, 35]
E_STACK_AD = [0.20, 0.275, 0.35, 0.425, 0.50]
E_AD, E_AP, E_STACK_AP = 0.70, 0.65, 0.50

# --- target-frame regions, in pixels of a 2048-px-wide game (scaled to the real width) ---
REF_WIDTH = 2048
REGIONS = {
    "armor":  (48, 63, 128, 95),
    "mr":     (143, 63, 236, 95),
    "health": (314, 63, 540, 93),
    "buffs":  (150, 195, 600, 256),   # buff row under the frame (searched for the spear icon)
}
HEALTH_BAR = (317, 61, 540, 91)   # target-frame health bar (left edge = 0 HP, right = max HP)
FILL_TOLERANCE = 0.06             # OCR'd HP must match how full the bar looks (rejects misreads)
COUP_DE_GRACE = 8014     # rune id: +8% damage to targets below 40% max HP
CUT_DOWN = 8017          # rune id: +8% damage to targets above 60% max HP
KDA_ROW = (325, 22, 560, 56)  # yellow gold/KDA text above the bar: champions, minions, dummy
REGION_SCALE = None   # set a number to override the automatic scale if boxes are off

GAME_TITLE = "League of Legends (TM) Client"
API = "https://127.0.0.1:2999/liveclientdata/"
_ssl = ssl.create_default_context()
_ssl.check_hostname = False
_ssl.verify_mode = ssl.CERT_NONE  # local game API uses Riot's self-signed cert


# ---------------- math ----------------
def rend_damage(stacks, e_level, ad, ap):
    if stacks < 1 or e_level < 1:
        return 0.0
    i = min(e_level, 5) - 1
    first = E_BASE[i] + E_AD * ad + E_AP * ap
    extra = E_STACK_BASE[i] + E_STACK_AD[i] * ad + E_STACK_AP * ap
    return first + (stacks - 1) * extra


def armor_multiplier(armor, pen_pct, flat_pen):
    eff = armor * (1 - pen_pct) - flat_pen
    eff = max(eff, 0) if armor >= 0 else armor  # flat pen can't push armor below 0
    return 100 / (100 + eff) if eff >= 0 else 2 - 100 / (100 - eff)


def evaluate(me, tgt):
    """Returns dict with damage, hp, and state: 'kill', 'close' (one more spear kills) or None."""
    mult = armor_multiplier(tgt["armor"], me["pen_pct"], me["flat_pen"])
    if tgt.get("epic"):
        mult *= 0.5  # "Cette competence inflige 50% de degats aux monstres epiques"
    if me.get("coup") and tgt["hp"] < 0.4 * tgt["max_hp"]:
        mult *= 1.08
    if me.get("cutdown") and tgt["hp"] > 0.6 * tgt["max_hp"]:
        mult *= 1.08
    dmg = rend_damage(tgt["stacks"], me["e_level"], me["ad"], me["ap"]) * mult
    one_more = rend_damage(tgt["stacks"] + 1, me["e_level"], me["ad"], me["ap"]) * mult
    hp = tgt["hp"]
    margin = tgt["max_hp"] * 0.006 if tgt.get("hp_estimated") else 0  # bar is ~0.5% per pixel
    state = None
    if hp > 0 and tgt["stacks"] > 0 and me["e_level"] > 0:
        state = "kill" if dmg >= hp + margin else ("close" if one_more >= hp else None)
    return {"dmg": dmg, "hp": hp, "max_hp": tgt["max_hp"], "stacks": tgt["stacks"],
            "pct": dmg / hp if hp else 0, "state": state, "mult": mult}


# ---------------- live client API ----------------
def _get(path):
    with urllib.request.urlopen(API + path, timeout=0.5, context=_ssl) as r:
        return json.load(r)


def read_attack_speed():
    """Your current attacks per second (changes mid-fight with stacking items), or None."""
    try:
        return float(_get("activeplayer/championStats")["attackSpeed"]) or None
    except Exception:
        return None


BOOTS_T1 = {1001}                                            # Boots
BOOTS_T2 = {3006, 3009, 3020, 3047, 3111, 3117, 3158, 2422}  # Berserker's ... Lucidity, Magical
BOOTS_T2_NAMES = ("greaves", "boots", "shoes", "treads", "steelcaps", "soles", "souls")


def boots_tier(items):
    """0 no boots, 1 Boots, 2 finished boots, 3 upgraded (tier 3) boots. Tier 3 boots are told
    apart by not being a known tier 1/2 item while still being boots-like by name."""
    tier = 0
    for it in items:
        iid, name = it.get("itemID"), (it.get("displayName") or "").lower()
        if iid in BOOTS_T1:
            tier = max(tier, 1)
        elif iid in BOOTS_T2:
            tier = max(tier, 2)
        elif any(n in name for n in BOOTS_T2_NAMES) or name in (
                "swiftmarch", "armored advance", "chainlaced crushers", "forever forward",
                "gunmetal greaves", "spellslinger's shoes", "crimson lucidity"):
            tier = max(tier, 3)
    return tier


def read_me():
    """Your stats from the game, or None if not in game / not Kalista."""
    try:
        ap = _get("activeplayer")
        players = _get("playerlist")
    except Exception:
        return None
    me_id = ap.get("riotId") or ap.get("summonerName")
    mine = next((p for p in players if (p.get("riotId") or p.get("summonerName")) == me_id), {})
    champ = mine.get("rawChampionName", "")
    s = ap["championStats"]
    pct = s.get("armorPenetrationPercent", 1.0)
    pen_pct = 0.0 if pct in (0, 1) else (1 - pct if pct < 1 else 0.0)  # API gives a multiplier
    return {
        "kalista": "kalista" in champ.lower(),
        "ad": s.get("attackDamage", 0.0),
        "ap": s.get("abilityPower", 0.0),
        "pen_pct": pen_pct,
        "flat_pen": max(s.get("armorPenetrationFlat", 0.0), s.get("physicalLethality", 0.0)),
        "magic_pen": s.get("magicPenetrationFlat", 0.0),
        "attack_speed": s.get("attackSpeed", 0.0),
        "boots_tier": boots_tier(mine.get("items", [])),
        "e_level": ap.get("abilities", {}).get("E", {}).get("abilityLevel", 0),
        "coup": any(r.get("id") == COUP_DE_GRACE
                    for r in ap.get("fullRunes", {}).get("generalRunes", [])),
        "cutdown": any(r.get("id") == CUT_DOWN
                       for r in ap.get("fullRunes", {}).get("generalRunes", [])),
    }


# ---------------- OCR ----------------
# RapidOCR (recognition model only) on tight crops of digit-sized blobs: ~10-30 ms per number.
# Text heights in a 2048-px-wide game:
DIGIT_H = {"armor": 15, "mr": 15, "health": 18, "stacks": 18}
_engine = None


def _ocr_engine():
    global _engine
    if _engine is None:
        from rapidocr_onnxruntime import RapidOCR
        _engine = RapidOCR()
    return _engine


_rec_cache, _region_cache = {}, {}


def _rec(mask):
    """mask: bool array of glyph pixels -> recognized text (cached: same pixels = same text)."""
    key = (mask.shape, mask.tobytes())
    if key in _rec_cache:
        return _rec_cache[key]
    if len(_rec_cache) > 20000:
        _rec_cache.clear()
    img = Image.fromarray(np.where(mask, 0, 255).astype(np.uint8))
    img = ImageOps.expand(img, border=4, fill=255)
    img = img.resize((max(8, int(img.width * 48 / img.height)), 48), Image.LANCZOS).convert("RGB")
    res, _ = _ocr_engine()(np.array(img), use_det=False, use_cls=False)
    _rec_cache[key] = res[0][0] if res else ""
    return _rec_cache[key]


def _fix(t):
    return (t.replace("O", "0").replace("o", "0").replace("D", "0").replace("l", "1")
             .replace("I", "1").replace("|", "1").replace("i", "1").replace("S", "5"))


_group_cache, _digit_cache = {}, {}


def _glyph_keys(mask):
    columns = np.flatnonzero(mask.any(axis=0))
    if not len(columns):
        return []
    groups = np.split(columns, np.where(np.diff(columns) > 1)[0] + 1)
    keys = []
    for xs in groups:
        glyph = mask[:, xs[0]:xs[-1] + 1]
        ys = np.flatnonzero(glyph.any(axis=1))
        glyph = glyph[ys[0]:ys[-1] + 1]
        keys.append((glyph.shape, np.packbits(glyph).tobytes()))
    return keys


def _remember_digits(name, mask, text):
    keys = _glyph_keys(mask)
    if not re.fullmatch(r"[0-9]+", text) or len(keys) != len(text):
        return
    if len(_digit_cache) > 10000:
        _digit_cache.clear()
    for key, digit in zip(keys, text):
        key = (name, key)
        previous = _digit_cache.get(key, digit)
        _digit_cache[key] = digit if previous == digit else None  # ambiguous shape: OCR must decide


def _known_text(name, key, mask):
    text = _group_cache.get(key)
    if text is not None:
        return text
    digits = [_digit_cache.get((name, k)) for k in _glyph_keys(mask)]
    return "".join(digits) if digits and None not in digits else None


def _group_masks(crop, name, scale, cut=150):
    """Digit-height blobs grouped into numbers. Returns (cache key, mask) per number, left to
    right. The key is the number's exact pixel shape, so the same number always has the same key
    wherever it is drawn (e.g. max HP keeps its key when the current HP loses a digit)."""
    import cv2
    if scale < 0.98:  # small HUD: enlarge the digits to the reference size before reading
        k = 1.0 / scale
        crop = crop.resize((max(1, round(crop.width * k)), max(1, round(crop.height * k))), Image.LANCZOS)
        scale = 1.0
    g = np.array(crop.convert("L"))
    b = (g > cut).astype(np.uint8)
    if name == "stacks":
        # Game announcements can overlap the badge. Gold announcement letters are
        # not white stack digits, even when their luminance passes the OCR cutoff.
        rgb = np.array(crop.convert("RGB")).astype(int)
        b &= (rgb.max(axis=2) - rgb.min(axis=2) < 65).astype(np.uint8)
    n, lab, st, _ = cv2.connectedComponentsWithStats(b, 8)
    H = DIGIT_H[name] * scale
    comps = [(i, *st[i][:4]) for i in range(1, n)
             if 0.82 * H <= st[i][3] <= 1.35 * H and st[i][2] <= 1.2 * st[i][3]]
    comps.sort(key=lambda c: c[1])
    groups, cur = [], []
    for c in comps:
        if cur and c[1] - (cur[-1][1] + cur[-1][3]) > 0.5 * H:
            groups.append(cur)
            cur = []
        cur.append(c)
    if cur:
        groups.append(cur)
    out = []
    for grp in groups:
        x0 = min(c[1] for c in grp); x1 = max(c[1] + c[3] for c in grp)
        y0 = min(c[2] for c in grp); y1 = max(c[2] + c[4] for c in grp)
        mask = np.isin(lab[y0:y1, x0:x1], [c[0] for c in grp])
        out.append(((mask.shape, np.packbits(mask).tobytes()), mask))
    return out


def read_numbers(crop, name, scale, cut=150):
    """Find digit-height blobs, group neighbours into numbers, recognise each group (each number's
    pixel shape is recognised once, then remembered)."""
    texts = []
    for key, mask in _group_masks(crop, name, scale, cut):
        if key not in _group_cache:
            if len(_group_cache) > 50000:
                _group_cache.clear()
            text = _known_text(name, key, mask)
            _group_cache[key] = text if text is not None else _fix(_rec(mask))
            _remember_digits(name, mask, _group_cache[key])
        texts.append(_group_cache[key])
    return texts


def known_numbers(crop, name, scale, cut=150):
    """Like read_numbers but never runs OCR: numbers not seen before come back as None."""
    return [_known_text(name, key, mask) for key, mask in _group_masks(crop, name, scale, cut)]


def spear_count(texts):
    """One complete numeric badge, never a guessed spear or a fragment of other text."""
    if len(texts) == 1 and texts[0] and re.fullmatch(r"[0-9]{1,3}", texts[0]):
        value = int(texts[0])
        if 0 < value < 1000:
            return value
    return None


EPIC_MIN_HP = 2800   # unrecognised monster portrait this big: treat as epic (Rend does 50%)


def _same_portrait(a, b, bits=6):
    """Portrait fingerprints of the same target (allows a few flickering pixels)."""
    if not (isinstance(a, tuple) and isinstance(b, tuple)):
        return a == b
    if a[0] != b[0] or len(a[1]) != len(b[1]):
        return False
    diff = np.bitwise_xor(np.frombuffer(a[1], np.uint8), np.frombuffer(b[1], np.uint8))
    return int(np.unpackbits(diff).sum()) <= bits


_kind_cache = {}


def quick_read(frame, scale):
    """Everything about the target that can be known this instant without OCR: bar fill, and any
    number whose exact pixel shape was read before (max HP, armor, MR, spears, often current HP).
    Unknown values are None; the OCR thread reads them once and from then on they're instant."""
    def crop(box):
        x0, y0, x1, y1 = box
        return frame.crop((int(x0 * scale), int(y0 * scale), int(x1 * scale), int(y1 * scale)))

    def first_int(texts):
        for t in texts:
            if t is None:
                return None
            m = re.search(r"\d+", t)
            if m:
                return int(m[0])
        return None

    fill = bar_fill(frame, scale)
    # Portrait pixels distinguish target switches from a new, not-yet-learned number.
    portrait = np.array(crop((224, 38, 286, 90)).resize((8, 8), Image.Resampling.BOX))
    identity = (frame.size, np.packbits(portrait > 96).tobytes())
    out = {"present": False, "ally": False, "identity": identity, "fill": fill, "hp": None, "max_hp": None,
           "armor": None, "mr": 0, "stacks": None, "monster": False}
    if fill is None:
        return out
    hcrop = crop(REGIONS["health"])
    # same brightness cut-offs as read_target, so whatever OCR read is recognised here
    for cut in (150, 120, 180, 100):
        ht = known_numbers(hcrop, "health", scale, cut)
        if len(ht) < 2:
            continue
        out["present"] = True
        if None not in ht:
            pair = parse_health(ht)
            if pair and abs(pair[0] / pair[1] - fill) <= FILL_TOLERANCE:
                out["max_hp"], out["hp"] = pair[1], pair[0]
                break
        if not out["max_hp"] and ht[-1] and ht[-1].isdigit():
            out["max_hp"] = int(ht[-1])   # max HP known, current HP new: HP comes from the bar
    if not out["present"]:
        return out
    icon = find_spear_slot(frame, scale)
    if not target_is_enemy(frame, scale, icon):
        out["ally"] = True
        return out
    if out["max_hp"] and out["max_hp"] < 10:
        out["max_hp"] = None
    out["armor"] = first_int(known_numbers(crop(REGIONS["armor"]), "armor", scale))
    mr = first_int(known_numbers(crop(REGIONS["mr"]), "mr", scale))
    out["mr"] = mr or 0
    out["monster"] = not has_kda_row(frame, scale)
    if out["monster"]:
        kind = _kind_cache.get(identity)
        if kind is None:
            kind = identify_monster(frame, scale)
            if kind is not None:
                if len(_kind_cache) > 2000:
                    _kind_cache.clear()
                _kind_cache[identity] = kind
        out["monster_kind"] = kind
    else:
        out["monster_kind"] = None
    if not icon:
        out["stacks"] = 0
    else:
        x0, y0, x1, y1 = icon
        st = known_numbers(crop((x0 - 3, y0 + 20, x1 + 6, y1 + 4)), "stacks", scale)
        out["stacks"] = spear_count(st)
    return out


# Buff icons sit in fixed slots under the frame, right-aligned: slot 0 is the rightmost.
ICON_SLOT0 = (504, 198, 551, 245)
ICON_STEP = 51
ICON_SLOTS = 8


def _mean(frame, box, scale):
    x0, y0, x1, y1 = (int(v * scale) for v in box)
    px = np.array(frame.crop((x0, y0, x1, y1))).reshape(-1, 3).astype(int)
    return px.mean(axis=0) if len(px) else np.zeros(3)


def find_spear_slot(frame, scale):
    """Returns the Rend buff icon box (x0, y0, x1, y1) in reference coords, or None.
    Icons in the buff row have red-brown borders: find the vertical border lines, pair them
    into icons by width, and pick the dark-blue one (the spear art is animated, so colour is
    far more reliable than matching a picture). Works at any HUD size."""
    bx0, by0, bx1, by1 = REGIONS["buffs"]
    iy0, iy1 = ICON_SLOT0[1], ICON_SLOT0[3]
    a = np.array(frame.crop((int(bx0 * scale), int((iy0 + 6) * scale),
                             int(bx1 * scale), int((iy1 - 6) * scale)))).astype(int)
    if a.size == 0:
        return None
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    red = (r > 95) & (r - g > 30) & (r - b > 30)
    cols = np.where(red.mean(axis=0) > 0.45)[0]
    # merge neighbouring columns into border lines (x centres, frame px)
    lines, run = [], [cols[0]] if len(cols) else []
    for c in cols[1:]:
        if c - run[-1] <= 2:
            run.append(c)
        else:
            lines.append(sum(run) / len(run)); run = [c]
    if run:
        lines.append(sum(run) / len(run))
    width = (ICON_SLOT0[2] - ICON_SLOT0[0]) * scale
    used = set()
    for i in range(len(lines) - 1, 0, -1):        # right to left
        for j in range(i - 1, -1, -1):
            d = lines[i] - lines[j]
            if d > width * 1.25:
                break
            if d >= width * 0.75 and i not in used and j not in used:
                used.update((i, j))
                left = bx0 + lines[j] / scale
                right = bx0 + lines[i] / scale
                rr, gg, bb = _mean(frame, (left + 4, iy0 + 4, right - 3, iy0 + 20), scale)
                if bb - rr > 25 and bb - gg > 15:
                    return left, iy0, right, iy1
                break
    # Some frames (e.g. monsters) draw the icon with a light border instead of the red one:
    # fall back to the fixed slots and recognise the spear art itself (bright spear-blue
    # with white highlights; empty slots and the map behind have neither).
    for k in range(ICON_SLOTS):
        box = (ICON_SLOT0[0] - k * ICON_STEP, iy0, ICON_SLOT0[2] - k * ICON_STEP, iy1)
        if box[0] < bx0:
            break
        x0, y0, x1, y1 = (int(v * scale) for v in box)
        px = np.array(frame.crop((x0, y0, x1, y1))).astype(int).reshape(-1, 3)
        if not len(px):
            break
        r, g, b = px[:, 0], px[:, 1], px[:, 2]
        blue = ((b > 110) & (b - r > 45) & (b >= g)).mean()     # bright spear art
        navy = ((b > 60) & (b - r > 30) & (b >= g)).mean()       # dark icon background
        white = ((r > 200) & (g > 200) & (b > 200)).mean()      # highlights / stack number
        if (blue >= 0.05 or navy >= 0.08) and white >= 0.01:
            return box
    return None


def bar_team(frame, scale):
    """Ally bars are green, enemy/monster bars red. Looks only at the coloured (filled) part of
    the strip above the HP text, so the empty dark-teal part can't fool it."""
    x0, y0, x1, y1 = HEALTH_BAR
    box = (int(x0 * scale), int((y0 + 3) * scale), int(x1 * scale), int((y0 + 7) * scale))
    px = np.array(frame.crop(box)).reshape(-1, 3).astype(int)
    if not len(px):
        return None
    mx, mn = px.max(axis=1), px.min(axis=1)
    fill = px[(mx > 55) & (mx - mn > 35)]
    if len(fill) < max(1, round(6 * scale * scale)):
        return None
    r, g, b = np.median(fill, axis=0)
    if r > g * 1.15 and r > b * 1.1:
        return "enemy"
    if g > r and g > b * 0.9:
        return "ally"
    return None


def target_is_enemy(frame, scale, spear_icon):
    team = bar_team(frame, scale)
    # At 1 HP the filled bar can be narrower than one pixel. A Rend debuff is
    # additional enemy evidence in that case, but never overrides a green ally bar.
    return team == "enemy" or (team is None and spear_icon is not None)


def has_kda_row(frame, scale):
    """Champions, minions and the dummy show yellow gold/KDA text above the bar; monsters don't."""
    x0, y0, x1, y1 = KDA_ROW
    a = np.array(frame.crop((int(x0 * scale), int(y0 * scale), int(x1 * scale), int(y1 * scale)))).astype(int)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    return int(((r > 170) & (g > 140) & (b < 110) & (r - b > 90)).sum()) >= 20 * scale * scale


def parse_health(groups):
    """'590 / 1000' -> (590, 1000). The slash is often read as '1', so with 3+ separate groups
    the first is current HP and the last is max HP."""
    joined = " ".join(groups)
    m = re.search(r"(\d+)\s*/\s*(\d+)", joined)
    if m:
        hp, mx = int(m[1]), int(m[2])
    else:
        nums = [g for g in groups if g.isdigit()]
        if len(groups) < 3 or not groups[0].isdigit() or not groups[-1].isdigit():
            return None
        hp, mx = int(groups[0]), int(groups[-1])
    if mx <= 0 or hp > mx:
        return None
    return hp, mx


def bar_fill(frame, scale):
    """Fraction of the health bar that is filled (red/green), read from the strip above the text."""
    x0, y0, x1, y1 = HEALTH_BAR
    box = (int(x0 * scale), int((y0 + 3) * scale), int(x1 * scale), int((y0 + 6) * scale))
    px = np.array(frame.crop(box)).astype(int)
    if px.size == 0:
        return None
    mx, mn = px.max(axis=2), px.min(axis=2)
    filled = ((mx > 55) & (mx - mn > 35)).mean(axis=0) > 0.5   # per column
    if not filled.any():
        return 0.0
    # rightmost filled column (fill grows from the left)
    return float((np.where(filled)[0].max() + 1) / filled.size)


def read_target(frame, scale):
    """frame = screenshot of the game client area (from its top-left corner).
    Returns (obs, raw). obs has whatever could be read this frame; missing values are None:
      present, ally, hp, max_hp (only when they agree with the bar), fill, armor, mr, stacks."""
    def crop(box):
        x0, y0, x1, y1 = box
        return frame.crop((int(x0 * scale), int(y0 * scale), int(x1 * scale), int(y1 * scale)))

    nums = lambda ts: [int(x) for t in ts for x in re.findall(r"\d+", t)]
    fill = bar_fill(frame, scale)
    raw = {"fill": fill}
    hp = max_hp = None
    pair = None
    # Antialiased text reads differently at each brightness cut-off (thin "1"s vanish, close
    # digits merge). Try a few; keep the first HP/max pair that agrees with the bar.
    for cut in (150, 120, 180, 100):
        groups = read_numbers(crop(REGIONS["health"]), "health", scale, cut)
        raw["health"] = " ".join(groups)
        pair = parse_health(groups)
        if pair and fill is not None and abs(pair[0] / pair[1] - fill) <= FILL_TOLERANCE:
            hp, max_hp = pair
            break
        if pair:
            raw["rejected"] = f"text {pair[0]}/{pair[1]} vs bar {fill}"
    raw["armor"] = read_numbers(crop(REGIONS["armor"]), "armor", scale)
    raw["mr"] = read_numbers(crop(REGIONS["mr"]), "mr", scale)
    armor, mr = nums(raw["armor"]), nums(raw["mr"])
    obs = {
        # target shown = readable HP pair, or (garbled HP text but armor + bar are readable)
        "present": bool(pair) or (bool(armor) and fill is not None
                                  and len(raw["health"].replace(" ", "")) >= 3),
        "ally": False, "hp": hp, "max_hp": max_hp, "fill": fill,
        "armor": armor[0] if armor else None, "mr": mr[0] if mr else 0, "stacks": 0,
        "monster": False,
    }
    if not obs["present"]:
        return obs, raw
    icon = find_spear_slot(frame, scale)
    if not target_is_enemy(frame, scale, icon):
        obs["ally"] = raw["ally"] = True
        return obs, raw
    obs["monster"] = raw["monster"] = not has_kda_row(frame, scale)
    obs["monster_kind"] = identify_monster(frame, scale) if obs["monster"] else None
    raw["icon"] = icon
    if icon:
        x0, y0, x1, y1 = icon
        # stack number sits on the lower half of the icon (the spear art is on the upper half)
        raw["stacks"] = read_numbers(crop((x0 - 3, y0 + 20, x1 + 6, y1 + 4)), "stacks", scale)
        obs["stacks"] = spear_count(raw["stacks"])
    return obs, raw


# ---------------- game window ----------------
def game_rect():
    import ctypes
    import ctypes.wintypes as wt
    u = ctypes.windll.user32
    hwnd = u.FindWindowW(None, GAME_TITLE)
    if not hwnd:
        return None
    r = wt.RECT()
    u.GetClientRect(hwnd, ctypes.byref(r))
    pt = wt.POINT(0, 0)
    u.ClientToScreen(hwnd, ctypes.byref(pt))
    return pt.x, pt.y, pt.x + r.right, pt.y + r.bottom


def scale_for(width):
    return REGION_SCALE or width / REF_WIDTH


# ---------------- finding the target frame at any size ----------------
# Every coordinate above is for a 2048-px-wide window at the smallest HUD scale. League sizes its
# HUD from the window size AND the HUD-scale slider, so instead of guessing, look for the frame's
# fixed stat icons (attack, armor, attack speed, crit) in the window's top-left corner at many sizes.
FRAME_ICONS = Path(__file__).with_name("lol_frame_icons.png")
FRAME_ICONS_BOX = (20, 22, 46, 170)   # where those icons sit in reference coordinates
FRAME_MATCH = 0.70                    # no target selected scores ~0.2, the frame ~0.9+
_icons = None


def locate_frame(window, hint=None):
    """window: screenshot of the game's top-left corner. Returns (scale, origin_x, origin_y, score)
    or None. `hint` (a scale) is tried first so the usual case costs one match."""
    import cv2
    global _icons
    if _icons is None:
        _icons = cv2.cvtColor(np.array(Image.open(FRAME_ICONS).convert("RGB")), cv2.COLOR_RGB2GRAY)
    g = cv2.cvtColor(np.array(window.convert("RGB")), cv2.COLOR_RGB2GRAY)

    def match(sc):
        t = cv2.resize(_icons, (max(4, round(_icons.shape[1] * sc)), max(8, round(_icons.shape[0] * sc))),
                       interpolation=cv2.INTER_AREA)
        if t.shape[0] >= g.shape[0] or t.shape[1] >= g.shape[1]:
            return -1, (0, 0)
        _, score, _, loc = cv2.minMaxLoc(cv2.matchTemplate(g, t, cv2.TM_CCOEFF_NORMED))
        return score, loc

    def result(sc, score, loc):
        return sc, loc[0] - FRAME_ICONS_BOX[0] * sc, loc[1] - FRAME_ICONS_BOX[1] * sc, score

    if hint:
        score, loc = match(hint)
        if score >= FRAME_MATCH:
            return result(hint, score, loc)
    best = (-1, None, None)
    for sc in np.arange(0.35, 2.6, 0.05):          # coarse
        score, loc = match(sc)
        if score > best[0]:
            best = (score, sc, loc)
    if best[0] < FRAME_MATCH * 0.8:
        return None
    for sc in np.arange(best[1] - 0.05, best[1] + 0.051, 0.01):   # fine
        score, loc = match(sc)
        if score > best[0]:
            best = (score, sc, loc)
    return result(best[1], best[0], best[2]) if best[0] >= FRAME_MATCH else None


# ---------------- background watcher ----------------
class ExecuteWatcher:
    """`.result` holds the latest evaluate() output (or None).

    Three threads: the API (your stats), OCR (the target's numbers, ~0.1 s per changed read) and a
    fast loop that grabs the frame every 20 ms. The fast loop re-reads only the health bar's fill,
    so the line and the lightning follow HP as soon as the bar moves instead of waiting for OCR;
    OCR then replaces the bar estimate with the exact number."""

    def __init__(self, focused_fn, interval=0.02):
        self.focused = focused_fn
        self.interval = interval
        self.result = None
        self.me = None
        self._latest = None       # newest frame for the OCR thread
        self._ocr_wake = threading.Event()
        threading.Thread(target=self._api_loop, daemon=True).start()
        threading.Thread(target=self._ocr_loop, daemon=True).start()
        # load the OCR model now, not on the first target (the first read took over a second)
        threading.Thread(target=lambda: _rec(np.ones((18, 10), bool)), daemon=True).start()
        threading.Thread(target=self._run, daemon=True).start()

    _last_log = None
    _snapshot_key = None
    _snapshot_time = 0.0
    _kill_streak = 0
    rect = None
    scale = 1.0

    origin = (0, 0)
    _layouts = None
    _next_locate = 0.0

    def _layout(self, rect, gw, gh):
        """(scale, origin_x, origin_y) of the target frame for this window size. Found by
        locate_frame() the first time a target is shown, then reused; re-checked if it stops
        matching (HUD scale changed). REGION_SCALE forces a scale at the window's corner."""
        if REGION_SCALE:
            return REGION_SCALE, 0, 0
        if self._layouts is None:
            self._layouts = {}
        known = self._layouts.get((gw, gh))
        now = time.time()
        if now < self._next_locate:
            return known
        # search the top-left quarter-ish of the window (frame + some slack)
        shot = self._mss.grab({"left": rect[0], "top": rect[1], "width": max(64, int(gw * 0.35)),
                               "height": max(64, int(gh * 0.25))})
        corner = Image.frombytes("RGB", shot.size, shot.bgra, "raw", "BGRX")
        found = locate_frame(corner, hint=known[0] if known else scale_for(gw))
        if found:
            self._layouts[(gw, gh)] = found[:3]
            self._next_locate = now + 5   # cheap re-check every 5 s while a target is shown
            return found[:3]
        if known:
            # No target right now. Keep the known position so the next target shows at once;
            # quick_read sees "no target" by itself. Re-check the position now and then.
            self._next_locate = now + 2
            return known
        self._next_locate = now + 0.15    # never found yet -> look again shortly
        return None

    def bar_on_screen(self):
        """Health bar of the target frame in screen pixels (x0, y0, x1, y1), or None."""
        if not self.rect:
            return None
        s = self.scale
        gx, gy = self.rect[0] + self.origin[0], self.rect[1] + self.origin[1]
        x0, y0, x1, y1 = HEALTH_BAR
        return gx + x0 * s, gy + y0 * s, gx + x1 * s, gy + y1 * s

    def _log(self, me, tgt, res, frame):
        """Append every new reading to lol_execute_log.csv; snapshot the frame when it lights up."""
        key = (tuple(tgt.values()), res["state"], me["ad"], me["e_level"])
        if key == self._last_log:
            return
        self._last_log = key
        log = DATA / "lol_execute_log.csv"
        new = not log.exists()
        with log.open("a", encoding="utf-8") as f:
            if new:
                f.write("time,hp,max_hp,armor,mr,spears,ad,ap,pen_pct,flat_pen,e_level,coup,mult,dmg,state\n")
            f.write(f"{time.strftime('%H:%M:%S')},{tgt['hp']},{tgt['max_hp']},{tgt['armor']},{tgt['mr']},"
                    f"{tgt['stacks']},{me['ad']:.0f},{me['ap']:.0f},{me['pen_pct']:.2f},{me['flat_pen']:.0f},"
                    f"{me['e_level']},{int(bool(me.get('coup')))},{res['mult']:.3f},{res['dmg']:.0f},"
                    f"{res['state'] or ''}\n")
        snapshot_key = (tgt["max_hp"], tgt["stacks"])
        now = time.monotonic()
        if res["state"] not in ("kill", "kill-bar"):
            self._snapshot_key = None
        elif snapshot_key != self._snapshot_key or now - self._snapshot_time >= 1:
            self._snapshot_key, self._snapshot_time = snapshot_key, now
            d = DATA / "lol_debug"
            d.mkdir(exist_ok=True)
            # date first, so the "keep the newest 40" cleanup below really keeps the newest
            frame.save(d / f"kill_{time.strftime('%Y%m%d-%H%M%S')}_{res['state']}_{tgt['hp']}hp_{tgt['stacks']}sp.png")
            for old in sorted(d.glob("kill_*.png"))[:-40]:
                old.unlink()

    def _api_loop(self):  # own thread so a slow API call never delays the screen reads
        while True:
            self.me = read_me()
            time.sleep(0.25 if self.me else 2)

    def _run(self):
        while True:
            try:
                self._step()
            except Exception as e:
                self.result = None
                logging.exception("Execute watcher failed")
                time.sleep(1)
            time.sleep(self.interval)

    def _step(self):
        me = self.me
        if not me or not me["kalista"] or me["e_level"] < 1 or not self.focused():
            self._clear_result()
            time.sleep(0.2)
            return
        rect = game_rect()
        if not rect:
            self.result = None
            return
        if not hasattr(self, "_mss"):  # mss must be created on the thread that uses it
            import mss
            self._mss = getattr(mss, "MSS", mss.mss)()
        gw, gh = rect[2] - rect[0], rect[3] - rect[1]
        layout = self._layout(rect, gw, gh)
        if not layout:
            self._latest = None
            self._clear_result()
            return
        scale, ox, oy = layout
        self.rect, self.scale, self.origin = rect, scale, (ox, oy)
        # grab only the target-frame corner, not the whole screen
        w = int(max(r[2] for r in REGIONS.values()) * scale) + 2
        h = int(max(r[3] for r in REGIONS.values()) * scale) + 2
        shot = self._mss.grab({"left": int(rect[0] + ox), "top": int(rect[1] + oy), "width": w, "height": h})
        frame = Image.frombytes("RGB", shot.size, shot.bgra, "raw", "BGRX")
        self._latest = (frame, scale)
        self._ocr_wake.set()
        q = quick_read(frame, scale)
        tgt = self._observe(me, q)
        if tgt:
            self._log(me, tgt, self.result, frame)

    def _clear_result(self):
        self.result = None
        self._q_key = None
        self._kill_streak = 0

    def _observe(self, me, q):
        # Never carry a kill or spear count to another target. Within the same target, a
        # number that changed (new spear count, new armor) keeps the last value for a moment
        # while it is read, shown muted and never lightning, instead of hiding the line.
        if q["ally"] or not q["present"] or q["fill"] is None or not q["max_hp"]:
            self._clear_result()
            return None
        now = time.monotonic()
        kind = q.get("monster_kind")
        same = (self._held and _same_portrait(self._held["identity"], q.get("identity"))
                and self._held["max_hp"] == q["max_hp"] and now - self._held["t"] < 1.5)
        pending = False
        if q["armor"] is None:
            # new target whose armor isn't read yet (~0.1 s): draw at once with the last armor
            # seen (or none), grey and never lightning, until the real number is in
            q["armor"], pending = (self._held["armor"] if self._held else 0), True
            if same:
                q["mr"] = self._held["mr"]
        if q["stacks"] is None:
            if not same:
                self._clear_result()
                return None
            q["stacks"], pending = self._held["stacks"], True
        if q["monster"] and kind is None:
            kind = self._held["kind"] if same and self._held["kind"] else None
            if kind is None:
                kind, pending = ("?", q["max_hp"] >= EPIC_MIN_HP), True
        if not pending:
            self._held = {"identity": q.get("identity"), "max_hp": q["max_hp"], "armor": q["armor"],
                          "mr": q["mr"], "stacks": q["stacks"], "kind": kind, "t": now}
        elif same:
            self._held["t"] = now
        max_hp = q["max_hp"]
        key = (q.get("identity"), max_hp, q["armor"], q["mr"], q["stacks"], kind)
        if key != self._q_key:
            self._q_key, self._kill_streak = key, 0
        est = q["hp"] is None
        tgt = {"hp": round(q["fill"] * max_hp) if est else q["hp"], "max_hp": max_hp,
               "armor": q["armor"], "mr": q["mr"], "stacks": q["stacks"], "hp_estimated": est,
               "epic": bool(kind and kind[1])}
        res = evaluate(me, tgt)
        # The bar itself must agree with a kill too (catches a misread HP number).
        if res["state"] == "kill" and q["fill"] * max_hp > res["dmg"] + 0.01 * max_hp:
            res["state"] = "close"
        # exact HP lights it at once; an HP taken from the bar must agree on 3 frames (60 ms)
        self._kill_streak = self._kill_streak + 1 if res["state"] == "kill" and not pending else 0
        if res["state"] == "kill" and (pending or (est and self._kill_streak < 3)):
            res["state"] = "close"
        # Publish the calculation and its bar together. The renderer must never
        # observe a new result before its coordinates have been attached.
        self.result = dict(res, bar=self.bar_on_screen(), pending=pending,
                           monster=kind[0] if kind else None, hp_estimated=est,
                           observed_at=time.monotonic())
        return None if pending else tgt

    _held = None
    _q_key = None

    def _ocr_loop(self):
        while True:
            self._ocr_wake.wait()
            self._ocr_wake.clear()
            latest, self._latest = self._latest, None
            if not latest:
                continue
            frame, scale = latest
            try:
                # Only teach number shapes here. The fast loop alone owns result/state and
                # logs exactly what the overlay uses, never an older OCR frame's kill.
                read_target(frame, scale)
            except Exception as e:
                logging.exception("Execute OCR failed")
                time.sleep(0.5)


# ---------------- calibration ----------------
def calibrate(image_path=None):
    import ctypes
    ctypes.windll.shcore.SetProcessDpiAwareness(2)
    if image_path:
        frame = Image.open(image_path).convert("RGB")
    else:
        rect = game_rect()
        if not rect:
            print("League game window not found.")
            return
        frame = ImageGrab.grab(bbox=rect, all_screens=True)
    found = locate_frame(frame.crop((0, 0, int(frame.width * 0.35), int(frame.height * 0.25))))
    print("frame located:", found)
    if found:
        scale, ox, oy, _ = found
        frame = frame.crop((int(ox), int(oy), frame.width, frame.height))
    else:
        scale = scale_for(frame.width)
    tgt, raw = read_target(frame, scale)
    d = ImageDraw.Draw(frame)
    for k, (x0, y0, x1, y1) in REGIONS.items():
        d.rectangle((x0 * scale, y0 * scale, x1 * scale, y1 * scale), outline="red", width=2)
        d.text((x0 * scale, y1 * scale + 2), k, fill="red")
    if raw.get("icon"):
        x0, y0, x1, y1 = (v * scale for v in raw["icon"])
        d.rectangle((x0, y0, x1, y1), outline="yellow", width=2)
        d.text((x0, y1 + 2), "spear", fill="yellow")
    out = DATA / "lol_calibration.png"
    frame.save(out)
    print("frame", frame.size, "scale", round(scale, 4))
    print("OCR raw:", raw)
    print("target:", tgt)
    me = read_me()
    print("me:", me)
    if tgt and me and tgt.get("max_hp") and tgt.get("armor") is not None:
        print("result:", evaluate(me, tgt))
    print("saved", out)


if __name__ == "__main__":
    if "--calibrate" in sys.argv:
        args = [a for a in sys.argv[1:] if a != "--calibrate"]
        calibrate(args[0] if args else None)
    else:
        print(__doc__)

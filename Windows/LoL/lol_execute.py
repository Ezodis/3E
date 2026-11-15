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
import urllib.request
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageGrab, ImageOps

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
EPIC_MIN_HP = 2800       # a monster (no gold/KDA row in its frame) this big = epic: Rend does 50%
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


def read_me():
    """Your stats from the game, or None if not in game / not Kalista."""
    try:
        ap = _get("activeplayer")
        players = _get("playerlist")
    except Exception:
        return None
    me_id = ap.get("riotId") or ap.get("summonerName")
    champ = next((p.get("rawChampionName", "") for p in players
                  if (p.get("riotId") or p.get("summonerName")) == me_id), "")
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


_group_cache = {}


def read_numbers(crop, name, scale, cut=150):
    """Find digit-height blobs, group neighbours into numbers, recognise each group."""
    import cv2
    if scale < 0.98:  # small HUD: enlarge the digits to the reference size before reading
        k = 1.0 / scale
        crop = crop.resize((max(1, round(crop.width * k)), max(1, round(crop.height * k))), Image.LANCZOS)
        scale = 1.0
    g = np.array(crop.convert("L"))
    b = (g > cut).astype(np.uint8)
    rkey = (name, cut, b.shape, np.packbits(b).tobytes())
    if rkey in _region_cache:  # box looks exactly like last time -> no work
        return _region_cache[rkey]
    if len(_region_cache) > 5000:
        _region_cache.clear()
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
    texts = []
    for grp in groups:
        x0 = min(c[1] for c in grp); x1 = max(c[1] + c[3] for c in grp)
        y0 = min(c[2] for c in grp); y1 = max(c[2] + c[4] for c in grp)
        mask = np.isin(lab[y0:y1, x0:x1], [c[0] for c in grp])
        gkey = (mask.shape, np.packbits(mask).tobytes())   # e.g. max HP: same pixels while HP moves
        if gkey not in _group_cache:
            if len(_group_cache) > 20000:
                _group_cache.clear()
            _group_cache[gkey] = _fix(_rec(mask))
        texts.append(_group_cache[gkey])
    _region_cache[rkey] = texts
    return texts


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
    if not len(cols):
        return None
    # merge neighbouring columns into border lines (x centres, frame px)
    lines, run = [], [cols[0]]
    for c in cols[1:]:
        if c - run[-1] <= 2:
            run.append(c)
        else:
            lines.append(sum(run) / len(run)); run = [c]
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
    return None


def bar_is_ally(frame, scale):
    """Ally bars are green, enemy/monster bars red. Looks only at the coloured (filled) part of
    the strip above the HP text, so the empty dark-teal part can't fool it."""
    x0, y0, x1, y1 = HEALTH_BAR
    box = (int(x0 * scale), int((y0 + 3) * scale), int(x1 * scale), int((y0 + 7) * scale))
    px = np.array(frame.crop(box)).reshape(-1, 3).astype(int)
    if not len(px):
        return False
    mx, mn = px.max(axis=1), px.min(axis=1)
    fill = px[(mx > 55) & (mx - mn > 35)]
    if len(fill) < 6:
        return False  # bar (almost) empty: can't tell, treat as enemy
    r, g, b = np.median(fill, axis=0)
    return g > r and g > b * 0.9


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
    if bar_is_ally(frame, scale):
        obs["ally"] = raw["ally"] = True
        return obs, raw
    obs["monster"] = raw["monster"] = not has_kda_row(frame, scale)
    icon = find_spear_slot(frame, scale)
    raw["icon"] = icon
    if icon:
        x0, y0, x1, y1 = icon
        # stack number sits on the lower half of the icon (the spear art is on the upper half)
        raw["stacks"] = read_numbers(crop((x0 - 3, y0 + 20, x1 + 6, y1 + 4)), "stacks", scale)
        st = [v for v in nums(raw["stacks"]) if 0 < v < 1000]
        obs["stacks"] = st[-1] if st else 1  # icon without a number = 1 spear
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
        self._tgt = None          # newest target from OCR (+ the fill/stats pixels it was read from)
        self._latest = None       # newest frame for the OCR thread
        self._ocr_wake = threading.Event()
        threading.Thread(target=self._api_loop, daemon=True).start()
        threading.Thread(target=self._ocr_loop, daemon=True).start()
        threading.Thread(target=self._run, daemon=True).start()

    _prev = None
    _last_log = None
    _last_ok = 0.0
    _max_ok = None
    _max_seen = None
    _spears = 0
    _kill_streak = 0
    _armor = None
    _spear_cand = None
    _zero_since = None
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
        if known and now < self._next_locate:
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
        self._next_locate = now + 0.15    # no frame visible (no target) -> look again shortly
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
        if res["state"] == "kill":
            d = DATA / "lol_debug"
            d.mkdir(exist_ok=True)
            frame.save(d / f"kill_{time.strftime('%H%M%S')}_{tgt['hp']}hp_{tgt['stacks']}sp.png")
            for old in sorted(d.glob("kill_*.png"))[:-40]:
                old.unlink()

    def _reset(self):
        self.result, self._prev = None, None
        self._max_ok = self._max_seen = self._armor = None
        self._spears, self._spear_cand, self._zero_since, self._kill_streak = 0, None, None, 0

    def _track(self, obs):
        """Fuse this frame's reading with what we already know about the same target, so one
        unreadable digit never hides or moves the line. Returns the target dict to use, or None."""
        now = time.time()
        if obs["ally"] or not obs["present"]:
            if obs["ally"] or now - self._last_ok > 0.25:
                self._reset()
            return None
        self._last_ok = now
        # target identity = max HP. read_target only returns an HP/max pair that matches the bar's
        # fill, so one read is enough: a new target shows at once even when switching quickly.
        mx = obs["max_hp"]
        if mx is not None and mx != self._max_ok:
            self._reset()
            self._max_ok = mx
            self._spears = obs["stacks"]
            self._spear_cand = obs["stacks"]
        if self._max_ok is None:
            return None
        max_hp = self._max_ok
        if obs["hp"] is not None and obs["max_hp"] == max_hp:
            hp, est = obs["hp"], False
        elif obs["fill"] is not None:
            hp, est = round(obs["fill"] * max_hp), True   # digits unreadable: read the bar instead
        else:
            return None
        if obs["armor"] is not None:
            self._armor = obs["armor"]
        if self._armor is None:
            return None
        # spear count: a change must be read twice in a row; dropping to 0 needs 0.2 s of no icon
        v = obs["stacks"]
        if v == self._spears:
            self._zero_since = None
        elif v == 0:
            self._zero_since = self._zero_since or now
            if now - self._zero_since >= 0.2:
                self._spears = 0
        else:
            self._zero_since = None
            if v == self._spears + 1 or v == self._spear_cand:   # one more spear: show it at once
                self._spears = v
        self._spear_cand = v
        return {"hp": hp, "max_hp": max_hp, "armor": self._armor, "mr": obs["mr"],
                "stacks": self._spears, "hp_estimated": est,
                "epic": obs["monster"] and max_hp >= EPIC_MIN_HP}

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
                print("execute watcher:", e)
                time.sleep(1)
            time.sleep(self.interval)

    def _step(self):
        me = self.me
        if not me or not me["kalista"] or me["e_level"] < 1 or not self.focused():
            self.result = None
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
            self._tgt = None
            self._latest = None
            self.result = None
            self._track({"ally": False, "present": False})
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
        known = self._tgt
        if not known:
            self.result = None
            return
        tgt, ocr_fill, ocr_sig = known
        fill = bar_fill(frame, scale)
        if fill is None:
            return                     # bar not readable this frame: keep the last result
        if self._stats_sig(frame, scale) != ocr_sig:
            self.result = None         # armor/MR pixels changed: maybe another target, wait for OCR
            return
        if abs(fill - ocr_fill) * (HEALTH_BAR[2] - HEALTH_BAR[0]) * scale >= 1:   # bar moved >= 1 px
            tgt = dict(tgt, hp=round(fill * tgt["max_hp"]), hp_estimated=True)
        res = evaluate(me, tgt)
        # lightning: exact OCR HP lights it at once; a bar estimate must agree on two frames (40 ms)
        self._kill_streak = self._kill_streak + 1 if res["state"] == "kill" else 0
        if res["state"] == "kill" and tgt.get("hp_estimated") and self._kill_streak < 2:
            res["state"] = "close"
        self.result = res

    @staticmethod
    def _stats_sig(frame, scale):
        """Pixels of the armor + MR numbers: same target -> same pixels (cheap identity check)."""
        x0, y0, _, y1 = REGIONS["armor"]
        x1 = REGIONS["mr"][2]
        return hash(frame.crop((int(x0 * scale), int(y0 * scale), int(x1 * scale), int(y1 * scale))).tobytes())

    def _ocr_loop(self):
        while True:
            self._ocr_wake.wait()
            self._ocr_wake.clear()
            latest, self._latest = self._latest, None
            if not latest:
                continue
            frame, scale = latest
            try:
                obs, raw = read_target(frame, scale)
                tgt = self._track(obs)
                if not tgt or obs["fill"] is None:
                    if not tgt:
                        self._tgt = None
                    continue
                self._tgt = (tgt, obs["fill"], self._stats_sig(frame, scale))
                stable = tgt == self._prev
                self._prev = tgt
                me = self.me
                if stable and me:
                    self._log(me, tgt, evaluate(me, tgt), frame)
            except Exception as e:
                print("execute OCR:", e)
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

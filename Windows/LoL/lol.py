"""League of Legends macro helper (Windows).

Features (only active while the League game window is focused):
  Macro keys never reach the game themselves: a quick click does one thing, holding another.
  * Win           -> click: lock / unlock the camera.
                     hold while locked: unlock, drag the camera with the mouse, lock again on release.
                     hold while unlocked: just drag (stays unlocked until you click Win again).
                     The drag starts the instant Win goes down (no tap/hold wait); a quick
                     release turns it into the click. The Start menu never opens in game.
                     The real lock state is read from the HUD camera button (crossed = locked).
  * N             -> untouched: League's own binds (R, summoner 2, item 1), moved from Win.
  * B             -> click: Recall (RECALL_KEY).   hold: open the shop.
  * Space         -> click: Space as usual (E, attack-move, item 3).   hold: Stop every 0.35 s.
  * MB5           -> untouched: League's own MB5 binds (Flash, centre camera) as always.
  * Kite button   -> the mouse's macro-only side button, set in the mouse app to send F13
                     (or Pause). Hold (Kalista, in League): kite at once. Elsewhere, or with
                     the macros off, it is a normal key. Attack (attack-move), one move order to the cursor
                     during the windup (= a Martial Poise hop), wait for the hop to land and the
                     attack timer, repeat. Uses your live attack speed and boots tier.
  * Scroll wheel  -> holds 1, next scroll releases it and holds 2, then 3, 4, back to 1.
                     Scroll up = next, scroll down = previous. Any other key/click releases it.
  * Kalista E     -> line on the target's health bar at the HP Rend kills at (starts at the
                     left, moves right with more spears). Lightning only for a fresh,
                     confirmed lethal reading. See lol_execute.py.

Keybinds it relies on are set by lol_settings.py (stop = v, camera lock = y, pan = h,
recall = j, shop = b, attack-move = F9, Win's binds on n). They are applied by themselves
whenever League and its client are closed.

Setup:  pip install pynput rapidocr_onnxruntime mss
Run:    3£ tray menu -> LoL macros (no separate launcher or tray icon).
"""
import ctypes
import ctypes.wintypes as wt
import threading
import time
import queue
import logging
import json
import os

ctypes.windll.shcore.SetProcessDpiAwareness(2)  # real pixels for overlays/screen reads

import random

from pynput import keyboard, mouse

import lol_execute
from lol_controls import HoldController

# ---------------- config ----------------
GAME_TITLE = "League of Legends (TM) Client"
CYCLE_KEYS = ["1", "2", "3", "4"]
STOP_KEY = "v"            # must match evtPlayerStopPosition
STOP_INTERVAL = 0.35
HOLD_TIME = 0.18          # a macro key held longer than this is a hold, shorter is a click
RECALL_KEY = "j"          # must match evtUseItem7 (Recall)
SHOP_KEY = "b"            # must match evtOpenShop
ATTACK_KEY = "f9"         # must match evtPlayerAttackMove (attack-move at the cursor)
CAM_LOCK_KEY = "y"        # must match evtCameraLockToggle
PAN_KEY = "h"             # must match evtOnUIMouse4Pan
CAMERA_STARTS_LOCKED = True
KITE_AS_POLL = 0.05       # how often attack speed is re-read while kiting
# Kalista's attack and Martial Poise (League wiki: List of champions/Basic attacks and
# Template:Data Kalista/Martial Poise).
KAL_BASE_AS = 0.694       # base attack speed
KAL_WINDUP = 0.36         # windup = 36% of the attack at base attack speed
KAL_WINDUP_MOD = 0.75     # only 75% of the attack-speed change shortens the windup
HOP_RANGE = (240, 263, 280, 300)     # max hop distance by boots tier 0-3
HOP_SPEED = (1025, 1025, 1100, 1160)  # hop speed by boots tier (wiki lists 3 values)
MOVE_AT = 0.6             # the move order goes in at 60% of the windup (latest move wins)
KITE_MARGIN = 0.03        # extra wait after the hop lands before the next attack
watcher = None

# ---------------- Win32 SendInput (scan codes, games read these reliably) -------------
user32 = ctypes.WinDLL("user32", use_last_error=True)
user32.GetForegroundWindow.restype = wt.HWND
user32.GetWindowTextW.argtypes = [wt.HWND, wt.LPWSTR, ctypes.c_int]
user32.GetParent.argtypes = [wt.HWND]
user32.GetParent.restype = wt.HWND
user32.GetWindowLongW.argtypes = [wt.HWND, ctypes.c_int]
user32.SetWindowLongW.argtypes = [wt.HWND, ctypes.c_int, wt.LONG]
user32.SetWindowPos.argtypes = [wt.HWND, wt.HWND, ctypes.c_int, ctypes.c_int,
                                ctypes.c_int, ctypes.c_int, wt.UINT]
SCAN = {"1": 0x02, "2": 0x03, "3": 0x04, "4": 0x05, "5": 0x06, "v": 0x2F, "y": 0x15, "h": 0x23,
        "j": 0x24, "b": 0x30, "space": 0x39, "f9": 0x43, "f10": 0x44}
KEYEVENTF_EXTENDEDKEY = 0x0001
KEYEVENTF_KEYUP, KEYEVENTF_SCANCODE = 0x0002, 0x0008
ULONG_PTR = ctypes.c_size_t


class KEYBDINPUT(ctypes.Structure):
    _fields_ = [("wVk", wt.WORD), ("wScan", wt.WORD), ("dwFlags", wt.DWORD),
                ("time", wt.DWORD), ("dwExtraInfo", ULONG_PTR)]


class MOUSEINPUT(ctypes.Structure):
    _fields_ = [("dx", wt.LONG), ("dy", wt.LONG), ("mouseData", wt.DWORD),
                ("dwFlags", wt.DWORD), ("time", wt.DWORD), ("dwExtraInfo", ULONG_PTR)]


class _U(ctypes.Union):
    _fields_ = [("ki", KEYBDINPUT), ("mi", MOUSEINPUT)]


class INPUT(ctypes.Structure):
    _fields_ = [("type", wt.DWORD), ("u", _U)]


MOUSEEVENTF_RIGHTDOWN, MOUSEEVENTF_RIGHTUP = 0x0008, 0x0010


def right_click():
    if not macros_active():
        return
    for f in (MOUSEEVENTF_RIGHTDOWN, MOUSEEVENTF_RIGHTUP):
        inp = INPUT(type=0, u=_U(mi=MOUSEINPUT(0, 0, 0, f, 0, 0)))
        user32.SendInput(1, ctypes.byref(inp), ctypes.sizeof(INPUT))


def _send(vk=0, scan=0, flags=0):
    inp = INPUT(type=1, u=_U(ki=KEYBDINPUT(vk, scan, flags, 0, 0)))
    user32.SendInput(1, ctypes.byref(inp), ctypes.sizeof(INPUT))


def key_down(k):
    if not macros_active():
        return False
    _send(scan=SCAN[k], flags=KEYEVENTF_SCANCODE)
    return True


def key_up(k):
    _send(scan=SCAN[k], flags=KEYEVENTF_SCANCODE | KEYEVENTF_KEYUP)


def tap(k):
    if not key_down(k):
        return False
    time.sleep(0.02)
    key_up(k)
    return True


def game_focused():
    hwnd = user32.GetForegroundWindow()
    buf = ctypes.create_unicode_buffer(256)
    user32.GetWindowTextW(hwnd, buf, 256)
    return buf.value == GAME_TITLE


def macros_active():
    return bool(game_focused() and watcher and watcher.me and watcher.me.get("kalista"))


# ---------------- state ----------------
VK_LWIN, VK_B, VK_SPACE, VK_Y = 0x5B, 0x42, 0x20, 0x59
WM_KEYDOWN, WM_KEYUP, WM_SYSKEYDOWN, WM_SYSKEYUP = 0x100, 0x101, 0x104, 0x105
WM_MOUSEWHEEL = 0x020A
WM_RBUTTONDOWN = 0x0204
WM_XBUTTONDOWN, WM_XBUTTONUP, XBUTTON2 = 0x020B, 0x020C, 2
MOUSE_DOWNS = {0x0201, 0x0204, 0x0207, 0x020B}  # L, R, M, X button down
LLKHF_INJECTED, LLMHF_INJECTED = 0x10, 0x01

actions = queue.Queue()          # hook callbacks must be fast -> do the work on a worker
lock = threading.Lock()
pressed = set()                  # physical keys currently down
captured = set()                 # suppressed presses still need a suppressed release after Alt+Tab
last_down = {}                   # vk -> time of its latest key-down (auto-repeats included)


def _repeat_gap():
    """Longest normal pause between key-downs of a held key (Windows repeat delay + period).
    A longer pause before another key-down means its key-up was lost."""
    v = wt.UINT()
    delay = 1
    speed = 31
    try:
        if user32.SystemParametersInfoW(0x16, 0, ctypes.byref(v), 0):   # SPI_GETKEYBOARDDELAY
            delay = v.value
        if user32.SystemParametersInfoW(0x0A, 0, ctypes.byref(v), 0):   # SPI_GETKEYBOARDSPEED
            speed = v.value
    except Exception:
        pass
    period = 1.0 / (2.5 + speed * 27.5 / 31)
    return (delay + 1) * 0.25 + period + 0.15


REPEAT_GAP = _repeat_gap()
cycle_idx = -1                   # index into CYCLE_KEYS, -1 = none
held_num = None                  # number key we are holding
camera_locked = CAMERA_STARTS_LOCKED
cam = {"dragging": False, "relock": False, "quiet_until": 0.0, "clicks": 0}


def release_num(reset=False):
    global held_num, cycle_idx
    if held_num:
        key_up(held_num)
        held_num = None
    if reset:
        cycle_idx = -1  # next scroll starts again at 1


def do_scroll(direction):
    global cycle_idx, held_num
    release_num()
    if not macros_active():
        return
    cycle_idx = (cycle_idx + direction) % len(CYCLE_KEYS) if cycle_idx >= 0 else (0 if direction > 0 else len(CYCLE_KEYS) - 1)
    held_num = CYCLE_KEYS[cycle_idx]
    key_down(held_num)


# ---- camera (Win) ----
cam_lock = threading.Lock()      # a release never interleaves with a start still unlocking


def toggle_camera():
    global camera_locked
    if tap(CAM_LOCK_KEY):
        camera_locked = not camera_locked
        cam["quiet_until"] = time.monotonic() + 0.25


def camera_hold_start(held):
    """Runs the instant Win goes down. Locked: unlock and drag. Unlocked: just drag.
    camera_hold_end then decides: a quick release was a click, a longer one a hold."""
    with cam_lock:
        cam["t0"] = time.monotonic()
        cam["relock"] = camera_locked
        if camera_locked:
            toggle_camera()
            time.sleep(0.02)                 # let the game unlock before the pan key goes down
        if held() and key_down(PAN_KEY):
            cam["dragging"] = True


def camera_hold_end():
    with cam_lock:
        if cam["dragging"]:
            key_up(PAN_KEY)
            cam["dragging"] = False
        click = time.monotonic() - cam.get("t0", 0) < HOLD_TIME
        was_locked, cam["relock"] = cam["relock"], False
        if not macros_active():
            return
        if click:
            # A click toggles once: locked was already unlocked at press; unlocked locks now.
            if not was_locked:
                toggle_camera()
        elif was_locked and not camera_locked:
            toggle_camera()                  # hold while locked: lock again on release


# ---- stop (Space) ----


def stop_spam(held):
    while held():
        tap(STOP_KEY)
        time.sleep(STOP_INTERVAL)


def stop_start(held):
    threading.Thread(target=stop_spam, args=(held,), daemon=True).start()


# ---- kite (MB5) ----
kite = {"as": None}


def kite_as_loop(held):
    """Keeps kite["as"] fresh while kiting (items like Rageblade change it every attack)."""
    while held():
        a = lol_execute.read_attack_speed()
        if a and held():
            kite["as"] = a
        time.sleep(KITE_AS_POLL)


def windup_time(attack_speed):
    """League's windup rule: base windup + (windup at this speed - base windup) * modifier."""
    base = KAL_WINDUP / KAL_BASE_AS
    return base + (KAL_WINDUP / attack_speed - base) * KAL_WINDUP_MOD


def _wait_until(when_fn, held):
    """Sleep until when_fn() (re-evaluated, so a new attack speed counts at once) or release."""
    while held() and time.perf_counter() < when_fn():
        time.sleep(0.003)
    return held()


def kite_loop(held):
    """attack -> move order inside the windup (hop) -> hop lands + attack ready -> attack ..."""
    while held():
        t0 = time.perf_counter()
        tap(ATTACK_KEY)
        cam["clicks"] += 1
        AS = lambda: kite["as"] or 1.0
        if not _wait_until(lambda: t0 + MOVE_AT * windup_time(AS()), held):
            break
        if not held():
            break
        right_click()
        tier = ((watcher.me or {}).get("boots_tier") or 0) if watcher else 0
        hop = HOP_RANGE[tier] / HOP_SPEED[tier]
        if not _wait_until(lambda: t0 + max(1.0 / AS(), windup_time(AS()) + hop + KITE_MARGIN), held):
            break


def kite_start(held):
    me = watcher.me if watcher else None
    if not (me and me.get("kalista")):
        return
    kite["as"] = me.get("attack_speed") or kite["as"]
    threading.Thread(target=kite_as_loop, args=(held,), daemon=True).start()
    threading.Thread(target=kite_loop, args=(held,), daemon=True).start()


# Every macro key: a quick click does one thing, holding does another, and the key itself never
# reaches the game (so its own League binds can't fire on top of the macro).
#   key: (on click, on hold start, on hold end)
MACRO_KEYS = {
    # hold-only with a click: the drag starts at once, a quick release (or one before the
    # worker started it) is the click
    VK_LWIN: (toggle_camera, camera_hold_start, camera_hold_end, True),
    VK_B: (lambda: tap(RECALL_KEY), lambda held: tap(SHOP_KEY) if held() else None, None),
    VK_SPACE: (lambda: tap("space"), stop_start, None),
}
# The mouse's macro-only side button sends one of these keys (set in the mouse app).
VK_F13, VK_PAUSE = 0x7C, 0x13
KITE_KEYS = (VK_F13, VK_PAUSE)
for _vk in KITE_KEYS:
    MACRO_KEYS[_vk] = (None, kite_start, None, True)      # hold-only: kites from the first instant
controls = HoldController(MACRO_KEYS, actions.put, macros_active, HOLD_TIME)
macro_down = controls.down
macro_press = controls.press
macro_release = controls.release


# ---- camera lock check: read from the HUD's camera button ----
def camera_watch():
    """Keeps `camera_locked` equal to the game's real camera lock, read from the HUD's camera
    button (next to the options gear): a plain camera = unlocked, a crossed-out camera = locked.
    The gear is found by template matching once per window size (any size / HUD scale)."""
    global camera_locked
    import cv2
    import mss
    import numpy as np
    from PIL import Image
    from pathlib import Path
    here = Path(__file__).resolve().parent
    gray = lambda im: cv2.cvtColor(np.array(im.convert("RGB")), cv2.COLOR_RGB2GRAY)
    gear_t = gray(Image.open(here / "lol_hud_gear.png"))          # 41x41 at a 2048-px-wide game
    cam_t = gray(Image.open(here / "lol_hud_cam_unlocked.png"))   # 46x41, plain camera
    grabber = getattr(mss, "MSS", mss.mss)()
    layout = {}                       # (w, h) -> (scale, gear x, gear y) in window pixels
    while True:
        time.sleep(0.05)
        try:
            if not macros_active() or time.monotonic() < cam["quiet_until"]:
                continue
            r = lol_execute.game_rect()
            if not r:
                continue
            w, h = r[2] - r[0], r[3] - r[1]
            top = int(h * 0.85)
            shot = grabber.grab({"left": r[0], "top": r[1] + top, "width": w // 2, "height": h - top})
            g = cv2.cvtColor(np.frombuffer(shot.bgra, np.uint8).reshape(shot.height, shot.width, 4),
                             cv2.COLOR_BGRA2GRAY)
            known = layout.get((w, h))
            if known:
                s, gx, gy = known
                t = cv2.resize(gear_t, (round(41 * s), round(41 * s)), interpolation=cv2.INTER_AREA)
                patch = g[max(0, gy - 3):gy + t.shape[0] + 3, max(0, gx - 3):gx + t.shape[1] + 3]
                if patch.shape[0] < t.shape[0] or patch.shape[1] < t.shape[1] or \
                        cv2.matchTemplate(patch, t, cv2.TM_CCOEFF_NORMED).max() < 0.6:
                    known = None      # HUD moved (HUD scale changed?) -> search again
            if not known:
                best = (-1, 0, (0, 0))
                s0 = w / 2048
                for s in np.arange(max(0.3, s0 - 0.25), s0 + 0.26, 0.01):
                    t = cv2.resize(gear_t, (round(41 * s), round(41 * s)), interpolation=cv2.INTER_AREA)
                    if t.shape[0] >= g.shape[0] or t.shape[1] >= g.shape[1]:
                        continue
                    _, sc, _, loc = cv2.minMaxLoc(cv2.matchTemplate(g, t, cv2.TM_CCOEFF_NORMED))
                    if sc > best[0]:
                        best = (sc, s, loc)
                if best[0] < 0.6:
                    time.sleep(0.5)   # HUD hidden (dead screen, shop full-screen...): try later
                    continue
                known = (best[1], best[2][0], best[2][1])
                layout[(w, h)] = known
            s, gx, gy = known
            cx, m = gx + round(45 * s), max(2, round(5 * s))
            area = g[max(0, gy - m):gy + round(41 * s) + m, max(0, cx - m):cx + round(46 * s) + m]
            ct = cv2.resize(cam_t, (round(46 * s), round(41 * s)), interpolation=cv2.INTER_AREA)
            if area.shape[0] < ct.shape[0] or area.shape[1] < ct.shape[1]:
                continue
            score = cv2.matchTemplate(area, ct, cv2.TM_CCOEFF_NORMED).max()
            if score >= 0.88:
                camera_locked = False
            elif score < 0.85:
                camera_locked = True
        except Exception as e:
            print("camera watch:", e)
            time.sleep(1)


def settings_keeper():
    """Applies lol_settings' binds whenever League and its client are closed (the client
    rewrites its config files while it runs, so they can't be changed during a session)."""
    import lol_settings
    while True:
        try:
            if lol_settings.apply():
                logging.warning("League keybinds updated: Win's binds on N, M opens both quick "
                                "wheels, unused binds removed (%s)",
                                "; ".join(lol_settings.REMOVED.values()))
        except Exception:
            logging.exception("Could not update League keybinds")
            time.sleep(300)
        time.sleep(20)


def worker():
    while True:
        try:
            controls.poll()
            if not macros_active():
                release_num(reset=True)
            fn = actions.get(timeout=0.01)
            fn()
        except queue.Empty:
            pass
        except Exception:
            logging.exception("Macro action failed")


# ---------------- hooks ----------------
def kb_filter(msg, data):
    global camera_locked
    if data.flags & LLKHF_INJECTED:
        return True  # our own SendInput events
    vk = data.vkCode
    down = msg in (WM_KEYDOWN, WM_SYSKEYDOWN)
    up = msg in (WM_KEYUP, WM_SYSKEYUP)
    first_down = down and vk not in pressed
    if down:
        pressed.add(vk)
    elif up:
        pressed.discard(vk)

    # key-up handling always runs (even if focus changed) so nothing gets stuck
    if up:
        if vk in captured:
            captured.discard(vk)
            macro_release(vk)
            kb_listener.suppress_event()
        return True

    now = time.monotonic()
    gap = now - last_down.get(vk, now)
    if down:
        last_down[vk] = now
    if down and vk in captured:
        if gap <= REPEAT_GAP:
            kb_listener.suppress_event()     # auto-repeat of a held macro key
            return True
        # Windows dropped this key's release (it can when the PC is busy): end the old
        # press now and treat this one as a new press instead of swallowing it.
        logging.warning("missed key-up for vk %#x after %.2fs; recovered", vk, gap)
        captured.discard(vk)
        macro_release(vk)
        first_down = True

    if not macros_active():
        return True

    if vk in MACRO_KEYS:
        if first_down:
            if held_num:
                actions.put(lambda: release_num(reset=True))
            macro_press(vk)
        if vk in macro_down:
            captured.add(vk)
            kb_listener.suppress_event()     # the game only sees what the macro sends
        return True

    if first_down:
        if vk == VK_Y:         # you toggled the camera lock yourself
            camera_locked = not camera_locked
            cam["quiet_until"] = time.monotonic() + 0.25
        if held_num:
            actions.put(lambda: release_num(reset=True))  # any other key releases the number
    return True


def mouse_filter(msg, data):
    if data.flags & LLMHF_INJECTED:
        return True
    if not macros_active():
        return True
    if msg == WM_RBUTTONDOWN:
        cam["clicks"] += 1
    if msg == WM_MOUSEWHEEL:
        delta = ctypes.c_short(data.mouseData >> 16).value
        actions.put(lambda d=(1 if delta > 0 else -1): do_scroll(d))
        mouse_listener.suppress_event()  # don't zoom the camera
    elif msg in MOUSE_DOWNS and held_num:
        actions.put(lambda: release_num(reset=True))
    return True


def cleanup():
    controls.cancel()
    release_num()
    if cam["dragging"]:
        key_up(PAN_KEY)


SPEAR_ON = "#33f0b0"    # spectral green = macros active
SPEAR_IDLE = "#8a9599"  # grey = running, game not focused
SPEAR_EDGE = "#06332a"


def spear_polys(size, pad=2):
    """Spear pointing to the top-right corner, as lists of (x, y) points."""
    # shapes in spear-space: x = 0 (butt) .. 1 (tip), y = sideways offset
    shapes = [
        [(0.10, -0.032), (0.62, -0.032), (0.62, 0.032), (0.10, 0.032)],               # shaft
        [(0.60, 0), (0.70, -0.075), (1.0, 0), (0.70, 0.075)],                         # blade
        [(0.60, 0), (0.67, -0.05), (0.53, -0.12)], [(0.60, 0), (0.67, 0.05), (0.53, 0.12)],  # barbs
        [(0.0, -0.09), (0.16, 0), (0.0, 0.09), (0.06, 0)],                             # tail
    ]
    L = (size - 2 * pad) * 2 ** 0.5
    sx, sy = pad, size - pad          # butt at bottom-left
    ux, uy = 0.7071, -0.7071          # along the spear
    nx, ny = 0.7071, 0.7071           # sideways
    return [[(sx + (x * ux + y * nx) * L, sy + (x * uy + y * ny) * L) for x, y in s] for s in shapes]


def _click_through(win):
    """Make a Tk window click-through, topmost-capable and hidden from taskbar/Alt+Tab."""
    GWL_EXSTYLE, WS_EX_LAYERED, WS_EX_TRANSPARENT, WS_EX_TOOLWINDOW = -20, 0x80000, 0x20, 0x80
    WS_EX_NOACTIVATE = 0x08000000
    win.update_idletasks()
    hwnd = user32.GetParent(win.winfo_id())
    style = user32.GetWindowLongW(hwnd, GWL_EXSTYLE)
    user32.SetWindowLongW(hwnd, GWL_EXSTYLE,
                         style | WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE)
    return hwnd


HWND_TOPMOST, SWP_KEEP = -1, 0x0001 | 0x0002 | 0x0010  # NOSIZE|NOMOVE|NOACTIVATE
KEY_COLOR = "#010101"  # painted pixels of this colour are fully transparent
BOLT_COLORS = [(16, "#0b4f44"), (9, "#1fd1a0"), (3, "#eafff9")]  # glow -> core


def rend_coverage(res):
    """Where the line belongs: the HP Rend kills at, as a fraction of the bar."""
    return min(1, max(0, res["dmg"]) / res["max_hp"])


MARKER_EASE = 0.45   # share of the remaining distance the line moves per frame (~80 ms total)


def eased_coverage(prev, res):
    """Glide the line within one target; jump on a new target, a kill, or no previous frame."""
    target = rend_coverage(res)
    if not prev or prev[0] != res.get("target") or res.get("state") == "kill":
        return target
    shown = prev[1] + (target - prev[1]) * MARKER_EASE
    return target if abs(target - shown) < 0.002 else shown


def draw_rend_marker(canvas, res, origin, dpi, coverage=None):
    """Draw the execute line at the HP where Rend kills (dmg / max HP along the bar).

    `coverage` (the eased position) defaults to the exact one for this result.
    Returns the rendered position for diagnostics; creates no windows or input hooks.
    """
    bar = res.get("bar")
    if not bar or res["max_hp"] <= 0 or res["hp"] <= 0:
        return None
    ox, oy = origin
    x0, y0, x1, y1 = bar[0] - ox, bar[1] - oy, bar[2] - ox, bar[3] - oy
    # The line sits at the HP Rend kills at: left edge with no damage, sliding right as
    # spears add up. The red fill shrinks toward it; Rend kills once the fill reaches it.
    if coverage is None:
        coverage = rend_coverage(res)
    x = x0 + coverage * (x1 - x0)
    kill = res["state"] == "kill"
    core = "#ffffff" if kill else "#eafff9"
    glow = "#ff3b5c" if kill else "#1fd1a0"
    if res.get("pending"):
        glow = core = "#91a5a0"
    ext = 5 * dpi
    canvas.create_line(x, y0 - ext, x, y1 + ext, fill="#06332a", width=max(1, int(7 * dpi)))
    canvas.create_line(x, y0 - ext, x, y1 + ext, fill=glow, width=max(1, int(4 * dpi)))
    canvas.create_line(x, y0 - ext, x, y1 + ext, fill=core, width=max(1, int(1.5 * dpi)))
    t = 5 * dpi
    canvas.create_polygon(x - t, y0 - ext - t, x + t, y0 - ext - t, x, y0 - ext, fill=glow)
    canvas.create_polygon(x - t, y1 + ext + t, x + t, y1 + ext + t, x, y1 + ext, fill=glow)
    canvas.create_text(x, y0 - ext - t - 2 * dpi, anchor="s",
                       text=f"{res['stacks']}" + ("…" if res.get("pending") else ""),
                       fill=glow, font=("Segoe UI", 9, "bold"))
    return {"coverage": coverage, "x": x, "bar_left": x0, "bar_right": x1}


def show_lethal_lightning(res, now=None):
    """Do not animate an almost-kill, stale frame, or unconfirmed reading."""
    if not res:
        return False
    now = time.monotonic() if now is None else now
    return (res.get("state") == "kill" and not res.get("pending")
            and 0 < res["hp"] <= res["dmg"] and res["stacks"] > 0
            and 0 <= now - res.get("observed_at", float("-inf")) <= .25)


def make_indicator():
    """Click-through, always-on-top spear in the bottom-left corner + E damage label.
    Green = game focused (macros active), grey = script running but idle."""
    import tkinter as tk
    dpi = user32.GetDpiForSystem() / 96
    size, margin = int(48 * dpi), int(6 * dpi)
    label_w = int(110 * dpi)
    root = tk.Tk()
    root.report_callback_exception = lambda kind, value, tb: logging.error(
        "Overlay callback failed", exc_info=(kind, value, tb))
    root.overrideredirect(True)
    root.attributes("-topmost", True)
    root.config(bg=KEY_COLOR)
    root.attributes("-transparentcolor", KEY_COLOR)
    # bottom of the work area = just above the taskbar (screen bottom is hidden behind it)
    rect = wt.RECT()
    ctypes.windll.user32.SystemParametersInfoW(0x0030, 0, ctypes.byref(rect), 0)  # SPI_GETWORKAREA
    root.geometry(f"{size + label_w}x{size}+{rect.left + margin}+{rect.bottom - size - margin}")
    c = tk.Canvas(root, width=size + label_w, height=size, bg=KEY_COLOR, highlightthickness=0)
    c.pack()
    for poly in spear_polys(size):
        c.create_polygon([v for p in poly for v in p], fill=SPEAR_ON, outline=SPEAR_EDGE, tags="spear")
    label = c.create_text(size + 4, size // 2, anchor="w", text="", fill=SPEAR_ON,
                          font=("Segoe UI", 11, "bold"))
    hwnd = _click_through(root)

    # full-screen lightning overlay (hidden until Rend can kill)
    ov = tk.Toplevel(root)
    ov.overrideredirect(True)
    ov.attributes("-topmost", True)
    ov.config(bg=KEY_COLOR)
    ov.attributes("-transparentcolor", KEY_COLOR)
    oc = tk.Canvas(ov, bg=KEY_COLOR, highlightthickness=0)
    oc.pack(fill="both", expand=True)
    ov_hwnd = _click_through(ov)
    # invisible to screen capture (WDA_EXCLUDEFROMCAPTURE), so the line never covers the numbers
    # the reader looks at. Side effect: screenshots won't show the line/lightning either.
    user32.SetWindowDisplayAffinity(ov_hwnd, 0x11)
    ov.withdraw()
    ov_state = {"shown": False, "rect": None, "frame": 0, "marker": None, "eased": None}
    last_status = 0.0

    def place_overlay():
        r = lol_execute.game_rect() or (0, 0, user32.GetSystemMetrics(0), user32.GetSystemMetrics(1))
        if r != ov_state["rect"]:
            ov.geometry(f"{r[2] - r[0]}x{r[3] - r[1]}+{r[0]}+{r[1]}")
            ov_state["rect"] = r
        return r[2] - r[0], r[3] - r[1]

    def bolt(x0, y0, x1, y1, inward, jitter, step):
        """Jagged line from (x0,y0) to (x1,y1); offsets only go `inward` (unit vector)."""
        import math
        length = math.hypot(x1 - x0, y1 - y0)
        n = max(2, int(length / step))
        pts = []
        for i in range(n + 1):
            t = i / n
            off = 0 if i in (0, n) else random.uniform(0, jitter)
            pts += [x0 + (x1 - x0) * t + inward[0] * off, y0 + (y1 - y0) * t + inward[1] * off]
        return pts

    def draw_lightning(w, h):
        oc.delete("all")
        d = dpi
        edges = [  # (start, end, inward direction)
            ((0, 4), (w, 4), (0, 1)), ((0, h - 4), (w, h - 4), (0, -1)),
            ((4, 0), (4, h), (1, 0)), ((w - 4, 0), (w - 4, h), (-1, 0)),
        ]
        for (a, b, inward) in edges:
            main = bolt(*a, *b, inward, 28 * d, 45 * d)
            for width, color in BOLT_COLORS:
                oc.create_line(main, fill=color, width=int(width * d * 0.6), capstyle="round",
                               joinstyle="round")
            for _ in range(random.randint(3, 6)):  # branches shooting inward
                i = random.randrange(0, len(main) // 2 - 1) * 2
                sx, sy = main[i], main[i + 1]
                ln = random.uniform(60, 160) * d
                ex = sx + inward[0] * ln + random.uniform(-50, 50) * d * abs(inward[1])
                ey = sy + inward[1] * ln + random.uniform(-50, 50) * d * abs(inward[0])
                br = bolt(sx, sy, ex, ey, (inward[1], inward[0]), 14 * d, 18 * d)
                for width, color in BOLT_COLORS[1:]:
                    oc.create_line(br, fill=color, width=max(1, int(width * d * 0.4)))

    def render():
        res = watcher.result if macros_active() else None
        if res and time.monotonic() - res.get("observed_at", 0) > .25:
            res = None
        if res:
            c.itemconfig(label, text=f"E {res['dmg']:.0f} / {res['hp']}")
        else:
            c.itemconfig(label, text="")
            ov_state["marker"] = ov_state["eased"] = None
        if res:
            w, h = place_overlay()
            if not ov_state["shown"]:
                ov.deiconify()
                ov_state["shown"] = True
            ov_state["frame"] += 1
            if show_lethal_lightning(res):
                draw_lightning(w, h)  # clears the canvas itself
            else:
                oc.delete("all")
            if res["max_hp"] > 0:
                ov_state["eased"] = (res.get("target"), eased_coverage(ov_state["eased"], res))
            ov_state["marker"] = draw_rend_marker(oc, res, ov_state["rect"][:2], dpi,
                                                  ov_state["eased"][1] if ov_state["eased"] else None)
            user32.SetWindowPos(ov_hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_KEEP)
        elif ov_state["shown"]:
            oc.delete("all")
            ov.withdraw()
            ov_state["shown"] = False

    def animate():
        try:
            render()
        except Exception:
            logging.exception("Overlay frame failed")
        finally:
            root.after(16, animate)   # ~60 fps so the line glides instead of stepping

    def tick():
        nonlocal last_status
        # the spear only shows while League's game window is the active window
        if macros_active():
            if root.state() == "withdrawn":
                root.deiconify()
            c.itemconfig("spear", fill=SPEAR_ON)
            user32.SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_KEEP)  # stay above the game
        elif root.state() != "withdrawn":
            root.withdraw()
        now = time.monotonic()
        if now - last_status >= 1:
            last_status = now
            try:
                status = {"pid": os.getpid(), "updated": time.time(), "active": macros_active(),
                          "kalista": bool(watcher and watcher.me and watcher.me.get("kalista")),
                          "camera_locked": camera_locked, "overlay_shown": ov_state["shown"],
                          "overlay_frames": ov_state["frame"], "marker": ov_state["marker"],
                          "result": watcher.result if watcher else None}
                tmp = lol_execute.DATA / "lol_status.tmp"
                tmp.write_text(json.dumps(status), encoding="utf-8")
                tmp.replace(lol_execute.DATA / "lol_status.json")
            except OSError:
                logging.exception("Could not write macro status")
        root.after(100, tick)

    tick()
    animate()
    return root


quit_requested = threading.Event()


if __name__ == "__main__":
    import os
    import sys
    # one copy only: two copies would fire every macro twice
    _mutex = ctypes.windll.kernel32.CreateMutexW(None, False, "Local\\lol_macros")
    if ctypes.windll.kernel32.GetLastError() == 183:  # ERROR_ALREADY_EXISTS
        sys.exit(0)
    # lol.pid lets 3£'s "LoL macros" toggle find and stop this process
    PID_FILE = str(lol_execute.DATA / "lol.pid")
    with open(PID_FILE, "w") as f:
        f.write(str(os.getpid()))
    sys.setswitchinterval(0.002)   # the input hooks get the CPU quickly even while reading the screen
    threading.Thread(target=worker, daemon=True).start()
    threading.Thread(target=camera_watch, daemon=True).start()
    threading.Thread(target=settings_keeper, daemon=True).start()
    kb_listener = keyboard.Listener(win32_event_filter=kb_filter)
    mouse_listener = mouse.Listener(win32_event_filter=mouse_filter)
    kb_listener.start()
    mouse_listener.start()
    print("lol.py running - active only while the League game window is focused. Ctrl+C to quit.")
    watcher = lol_execute.ExecuteWatcher(game_focused)
    root = make_indicator()

    STOP_FILE = os.path.join(os.path.dirname(PID_FILE), "lol.stop")

    def keepalive():  # lets Ctrl+C reach Python while Tk's loop runs; handles 3£'s off switch
        if os.path.exists(STOP_FILE):  # 3£'s "LoL macros" toggle was switched off
            quit_requested.set()
        if quit_requested.is_set():
            root.quit()
            return
        root.after(200, keepalive)

    keepalive()
    try:
        root.mainloop()
    except KeyboardInterrupt:
        pass
    finally:
        cleanup()
        try:
            os.remove(PID_FILE)
        except OSError:
            pass
        kb_listener.stop()
        mouse_listener.stop()

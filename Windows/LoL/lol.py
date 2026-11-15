"""League of Legends macro helper (Windows).

Features (only active while the League game window is focused):
  Macro keys never reach the game themselves: a quick click does one thing, holding another.
  * N             -> click: lock / unlock the camera.
                     hold while locked: unlock, drag the camera with the mouse, lock again on release.
                     hold while unlocked: just drag (stays unlocked until you click N again).
                     The real lock state is re-checked from your own (green) health bar.
  * B             -> click: N's old League binds (recall, item 6, ...), now on RECALL_KEY.
                     hold: open the shop.
  * Space         -> click: Space as usual (E, attack-move, item 3).   hold: Stop every 0.35 s.
  * Win           -> Win as usual (R, item 1, ...); the Start menu never opens in game.
  * MB5           -> click: MB5 as usual (centre camera).
                     hold (Kalista): kite. Attack (attack-move), one move order to the cursor
                     during the windup (= a Martial Poise hop), wait for the hop to land and the
                     attack timer, repeat. Uses your live attack speed and boots tier.
  * Scroll wheel  -> holds 1, next scroll releases it and holds 2, then 3, 4, back to 1.
                     Scroll up = next, scroll down = previous. Any other key/click releases it.
  * Kalista E     -> line on the target's health bar at the HP Rend kills at (moves right
                     with more spears) + lightning around the screen when Rend kills
                     (pulsing border when one more spear would kill). See lol_execute.py.

Keybinds it relies on are set by lol_settings.py (stop = v, camera lock = y, pan = h,
N's old binds = j, shop = b, attack-move = F9).

Setup:  pip install pynput rapidocr_onnxruntime mss
Run:    3£ tray menu -> LoL macros (no tray icon of its own; or: python lol.py, Ctrl+C to quit)
"""
import ctypes
import ctypes.wintypes as wt
import threading
import time
import queue

ctypes.windll.shcore.SetProcessDpiAwareness(2)  # real pixels for overlays/screen reads

import random

from pynput import keyboard, mouse

import lol_execute

# ---------------- config ----------------
GAME_TITLE = "League of Legends (TM) Client"
CYCLE_KEYS = ["1", "2", "3", "4"]
STOP_KEY = "v"            # must match evtPlayerStopPosition
STOP_INTERVAL = 0.35
HOLD_TIME = 0.18          # a macro key held longer than this is a hold, shorter is a click
RECALL_KEY = "j"          # N's old League binds (recall, item 6, ...) live here now
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
        "j": 0x24, "b": 0x30, "space": 0x39, "f9": 0x43}
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
    for f in (MOUSEEVENTF_RIGHTDOWN, MOUSEEVENTF_RIGHTUP):
        inp = INPUT(type=0, u=_U(mi=MOUSEINPUT(0, 0, 0, f, 0, 0)))
        user32.SendInput(1, ctypes.byref(inp), ctypes.sizeof(INPUT))


def _send(vk=0, scan=0, flags=0):
    inp = INPUT(type=1, u=_U(ki=KEYBDINPUT(vk, scan, flags, 0, 0)))
    user32.SendInput(1, ctypes.byref(inp), ctypes.sizeof(INPUT))


def key_down(k):
    _send(scan=SCAN[k], flags=KEYEVENTF_SCANCODE)


def key_up(k):
    _send(scan=SCAN[k], flags=KEYEVENTF_SCANCODE | KEYEVENTF_KEYUP)


def tap(k):
    key_down(k)
    time.sleep(0.02)
    key_up(k)


def mask_win():
    """Send an unassigned VK while Win is down so releasing Win won't open Start."""
    _send(vk=0xE8)
    _send(vk=0xE8, flags=KEYEVENTF_KEYUP)


def game_focused():
    hwnd = user32.GetForegroundWindow()
    buf = ctypes.create_unicode_buffer(256)
    user32.GetWindowTextW(hwnd, buf, 256)
    return buf.value == GAME_TITLE


# ---------------- state ----------------
VK_LWIN, VK_N, VK_B, VK_SPACE, VK_Y = 0x5B, 0x4E, 0x42, 0x20, 0x59
WM_KEYDOWN, WM_KEYUP, WM_SYSKEYDOWN, WM_SYSKEYUP = 0x100, 0x101, 0x104, 0x105
WM_MOUSEWHEEL = 0x020A
WM_RBUTTONDOWN = 0x0204
WM_XBUTTONDOWN, WM_XBUTTONUP, XBUTTON2 = 0x020B, 0x020C, 2
MOUSE_DOWNS = {0x0201, 0x0204, 0x0207, 0x020B}  # L, R, M, X button down
LLKHF_INJECTED, LLMHF_INJECTED = 0x10, 0x01

actions = queue.Queue()          # hook callbacks must be fast -> do the work on a worker
lock = threading.Lock()
pressed = set()                  # physical keys currently down
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
    cycle_idx = (cycle_idx + direction) % len(CYCLE_KEYS) if cycle_idx >= 0 else (0 if direction > 0 else len(CYCLE_KEYS) - 1)
    held_num = CYCLE_KEYS[cycle_idx]
    key_down(held_num)


def mb5_click():
    """MB5 as the game knows it (centre camera)."""
    for f in (0x0080, 0x0100):          # MOUSEEVENTF_XDOWN, XUP; mouseData 2 = XBUTTON2 = MB5
        inp = INPUT(type=0, u=_U(mi=MOUSEINPUT(0, 0, 2, f, 0, 0)))
        user32.SendInput(1, ctypes.byref(inp), ctypes.sizeof(INPUT))
        time.sleep(0.02)


# ---- camera (N) ----
def toggle_camera():
    global camera_locked
    tap(CAM_LOCK_KEY)
    camera_locked = not camera_locked
    cam["quiet_until"] = time.time() + 0.8   # the camera glides after a toggle: don't judge it yet


def camera_hold_start():
    """Locked: unlock, drag while held, lock again on release. Unlocked: just drag."""
    cam["relock"] = camera_locked
    if camera_locked:
        toggle_camera()
        time.sleep(0.05)                     # let the game unlock before the pan key goes down
    key_down(PAN_KEY)
    cam["dragging"] = True


def camera_hold_end():
    if cam["dragging"]:
        key_up(PAN_KEY)
        cam["dragging"] = False
    if cam["relock"]:
        cam["relock"] = False
        if not camera_locked and game_focused():   # never type into another app
            toggle_camera()


# ---- stop (Space) ----
stop_state = {"on": False}


def stop_spam():
    while stop_state["on"]:
        if not game_focused():                      # left League: stop for good
            stop_state["on"] = False
            break
        tap(STOP_KEY)
        time.sleep(STOP_INTERVAL)


def stop_start():
    if not stop_state["on"]:
        stop_state["on"] = True
        threading.Thread(target=stop_spam, daemon=True).start()


def stop_end():
    stop_state["on"] = False


# ---- kite (MB5) ----
kite = {"held": False, "as": None}


def kite_as_loop():
    """Keeps kite["as"] fresh while kiting (items like Rageblade change it every attack)."""
    while kite["held"]:
        a = lol_execute.read_attack_speed()
        if a:
            kite["as"] = a
        time.sleep(KITE_AS_POLL)


def windup_time(attack_speed):
    """League's windup rule: base windup + (windup at this speed - base windup) * modifier."""
    base = KAL_WINDUP / KAL_BASE_AS
    return base + (KAL_WINDUP / attack_speed - base) * KAL_WINDUP_MOD


def _wait_until(when_fn):
    """Sleep until when_fn() (re-evaluated, so a new attack speed counts at once) or release."""
    while kite["held"] and time.perf_counter() < when_fn():
        time.sleep(0.003)
    return kite["held"]


def kite_loop():
    """attack -> move order inside the windup (hop) -> hop lands + attack ready -> attack ..."""
    while kite["held"]:
        if not game_focused():                      # left League: stop for good
            kite["held"] = False
            break
        t0 = time.perf_counter()
        tap(ATTACK_KEY)
        cam["clicks"] += 1
        AS = lambda: kite["as"] or 1.0
        if not _wait_until(lambda: t0 + MOVE_AT * windup_time(AS())):
            break
        if not game_focused():
            kite["held"] = False
            break
        right_click()
        tier = ((watcher.me or {}).get("boots_tier") or 0) if watcher else 0
        hop = HOP_RANGE[tier] / HOP_SPEED[tier]
        if not _wait_until(lambda: t0 + max(1.0 / AS(), windup_time(AS()) + hop + KITE_MARGIN)):
            break


def kite_start():
    if kite["held"]:
        return
    me = watcher.me if watcher else None
    if not (me and me.get("kalista")):
        return
    kite["held"] = True
    kite["as"] = me.get("attack_speed") or kite["as"]
    threading.Thread(target=kite_as_loop, daemon=True).start()
    threading.Thread(target=kite_loop, daemon=True).start()


def kite_end():
    kite["held"] = False


# Every macro key: a quick click does one thing, holding does another, and the key itself never
# reaches the game (so its own League binds can't fire on top of the macro).
#   key: (on click, on hold start, on hold end)
MACRO_KEYS = {
    VK_N: (toggle_camera, camera_hold_start, camera_hold_end),
    VK_B: (lambda: tap(RECALL_KEY), lambda: tap(SHOP_KEY), None),
    VK_SPACE: (lambda: tap("space"), stop_start, stop_end),
    "MB5": (mb5_click, kite_start, kite_end),
}
macro_down = {}                  # vk -> {"t": press time, "hold": hold started}


def _hold_timer(vk, t0):
    time.sleep(HOLD_TIME)
    st = macro_down.get(vk)
    if st and st["t"] == t0 and not st["hold"]:
        st["hold"] = True
        if MACRO_KEYS[vk][1]:
            actions.put(MACRO_KEYS[vk][1])


def macro_press(vk):
    t0 = time.perf_counter()
    macro_down[vk] = {"t": t0, "hold": False}
    threading.Thread(target=_hold_timer, args=(vk, t0), daemon=True).start()


def macro_release(vk):
    st = macro_down.pop(vk, None)
    if not st:
        return
    click, _, hold_end = MACRO_KEYS[vk]
    if st["hold"]:
        if hold_end:
            if vk == "MB5":
                kite_end()           # stop at once, not after queued actions
            actions.put(hold_end)
    elif click and game_focused():                  # a click only ever goes to League
        actions.put(click)


# ---- camera lock check: your own (green) health bar sits still in the middle when locked ----
def camera_watch():
    """Corrects `camera_locked` from the screen, so a missed toggle can never leave N backwards.
    Unlocked for sure: your bar is far from the middle, or it moved while we thought it locked.
    Locked: your bar stays dead centre for 2.5 s while you keep giving move orders."""
    global camera_locked
    import mss
    import numpy as np
    grabber = getattr(mss, "MSS", mss.mss)()
    hist = []
    while True:
        time.sleep(0.12)
        try:
            if not game_focused() or cam["dragging"] or time.time() < cam["quiet_until"]:
                hist.clear()
                continue
            r = lol_execute.game_rect()
            if not r:
                continue
            w, h = r[2] - r[0], r[3] - r[1]
            shot = grabber.grab({"left": r[0], "top": r[1] + int(h * 0.05),
                                 "width": w, "height": int(h * 0.77)})
            a = np.frombuffer(shot.bgra, np.uint8).reshape(shot.height, shot.width, 4)[::2, ::2]
            b_, g_, r_ = (a[..., i].astype(np.int16) for i in range(3))
            green = (g_ > 140) & (g_ - r_ > 60) & (g_ - b_ > 60)
            good = np.nonzero(green.sum(axis=1) > w * 0.01)[0]   # rows with a bar-wide green run
            if len(good) < 3 or (good[-1] - good[0]) * 2 > h * 0.02:  # none, or not one bar
                hist.clear()
                continue
            xs = np.nonzero(green[good].any(axis=0))[0]
            left = xs.min() * 2 / w                              # bar's left end (HP doesn't move it)
            cx = left + 0.054                                     # ~half a full bar: your champion
            top = (good[0] * 2 + h * 0.05) / h
            now = time.time()
            hist.append((now, cx, top, cam["clicks"]))
            hist[:] = [p for p in hist if now - p[0] <= 2.5]
            if camera_locked:
                moved = len(hist) >= 2 and (abs(hist[-1][1] - hist[-2][1]) > 0.01
                                            or abs(hist[-1][2] - hist[-2][2]) > 0.01)
                if abs(cx - 0.5) > 0.08 or moved:
                    camera_locked = False
            elif (len(hist) >= 15 and now - hist[0][0] >= 2.3 and hist[-1][3] - hist[0][3] >= 2
                  and all(abs(p[1] - 0.5) < 0.03 for p in hist)
                  and max(p[2] for p in hist) - min(p[2] for p in hist) < 0.004):
                camera_locked = True
        except Exception as e:
            print("camera watch:", e)
            time.sleep(1)


def worker():
    while True:
        fn = actions.get()
        try:
            fn()
        except Exception as e:  # keep the macro alive
            print("action error:", e)


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
        if vk in macro_down:
            macro_release(vk)
            kb_listener.suppress_event()
        return True

    if not game_focused():
        return True

    if vk in MACRO_KEYS:
        if first_down:
            if held_num:
                actions.put(lambda: release_num(reset=True))
            macro_press(vk)
        if vk in macro_down:
            kb_listener.suppress_event()     # the game only sees what the macro sends
        return True

    if first_down:
        if vk == VK_Y:         # you toggled the camera lock yourself
            camera_locked = not camera_locked
            cam["quiet_until"] = time.time() + 0.8
        if held_num:
            actions.put(lambda: release_num(reset=True))  # any other key releases the number
        if vk == VK_LWIN:
            actions.put(mask_win)
    return True


def mouse_filter(msg, data):
    if data.flags & LLMHF_INJECTED:
        return True
    mb5 = msg in (WM_XBUTTONDOWN, WM_XBUTTONUP) and (data.mouseData >> 16) == XBUTTON2
    if mb5 and msg == WM_XBUTTONUP and "MB5" in macro_down:   # always finish, even if focus moved
        macro_release("MB5")
        mouse_listener.suppress_event()
    if not game_focused():
        return True
    if mb5 and msg == WM_XBUTTONDOWN:
        if "MB5" not in macro_down:
            if held_num:
                actions.put(lambda: release_num(reset=True))
            macro_press("MB5")
        mouse_listener.suppress_event()          # the game only sees what the macro sends
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
    kite["held"] = False
    stop_state["on"] = False
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
    win.update_idletasks()
    hwnd = user32.GetParent(win.winfo_id())
    style = user32.GetWindowLongW(hwnd, GWL_EXSTYLE)
    user32.SetWindowLongW(hwnd, GWL_EXSTYLE, style | WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW)
    return hwnd


HWND_TOPMOST, SWP_KEEP = -1, 0x0001 | 0x0002 | 0x0010  # NOSIZE|NOMOVE|NOACTIVATE
KEY_COLOR = "#010101"  # painted pixels of this colour are fully transparent
BOLT_COLORS = [(16, "#0b4f44"), (9, "#1fd1a0"), (3, "#eafff9")]  # glow -> core


def make_indicator():
    """Click-through, always-on-top spear in the bottom-left corner + E damage label.
    Green = game focused (macros active), grey = script running but idle."""
    import tkinter as tk
    dpi = user32.GetDpiForSystem() / 96
    size, margin = int(48 * dpi), int(6 * dpi)
    label_w = int(110 * dpi)
    root = tk.Tk()
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
    ov_state = {"shown": False, "rect": None, "frame": 0}

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

    def draw_lightning(w, h, state):
        oc.delete("all")
        d = dpi
        edges = [  # (start, end, inward direction)
            ((0, 4), (w, 4), (0, 1)), ((0, h - 4), (w, h - 4), (0, -1)),
            ((4, 0), (4, h), (1, 0)), ((w - 4, 0), (w - 4, h), (-1, 0)),
        ]
        if state == "close":  # pulsing thin border: one more spear kills
            on = (ov_state["frame"] // 6) % 2 == 0
            oc.create_rectangle(3, 3, w - 3, h - 3, outline="#1fd1a0" if on else "#0b4f44",
                                width=int(5 * d))
            return
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

    def draw_marker(res):
        """Line on the target's health bar at the HP where Rend kills; slides right as spears add up."""
        bar = watcher.bar_on_screen()
        if not bar or not res["max_hp"]:
            return
        ox, oy = ov_state["rect"][0], ov_state["rect"][1]
        x0, y0, x1, y1 = bar[0] - ox, bar[1] - oy, bar[2] - ox, bar[3] - oy
        frac = min(res["dmg"] / res["max_hp"], 1.0)
        target_x = x0 + frac * (x1 - x0)
        cur = ov_state.get("lx")
        cur = target_x if cur is None or abs(cur - target_x) > (x1 - x0) * 0.5 else cur + (target_x - cur) * 0.45
        ov_state["lx"] = cur
        d = dpi
        kill = res["state"] == "kill"
        core = "#ffffff" if kill else "#eafff9"
        glow = "#ff3b5c" if kill else "#1fd1a0"
        ext = 5 * d
        oc.create_line(cur, y0 - ext, cur, y1 + ext, fill="#06332a", width=int(7 * d))
        oc.create_line(cur, y0 - ext, cur, y1 + ext, fill=glow, width=int(4 * d))
        oc.create_line(cur, y0 - ext, cur, y1 + ext, fill=core, width=max(1, int(1.5 * d)))
        t = 5 * d  # little arrow heads above and below the bar
        oc.create_polygon(cur - t, y0 - ext - t, cur + t, y0 - ext - t, cur, y0 - ext, fill=glow)
        oc.create_polygon(cur - t, y1 + ext + t, cur + t, y1 + ext + t, cur, y1 + ext, fill=glow)
        oc.create_text(cur, y0 - ext - t - 2 * d, anchor="s", text=f"{res['stacks']}",
                       fill=glow, font=("Segoe UI", 9, "bold"))

    def animate():
        res = watcher.result if watcher else None
        state = res["state"] if res else None
        if res:
            c.itemconfig(label, text=f"E {res['dmg']:.0f} / {res['hp']}")
        else:
            c.itemconfig(label, text="")
            ov_state["lx"] = None
        if res:
            w, h = place_overlay()
            if not ov_state["shown"]:
                ov.deiconify()
                ov_state["shown"] = True
            ov_state["frame"] += 1
            if state:
                draw_lightning(w, h, state)  # clears the canvas itself
            else:
                oc.delete("all")
            draw_marker(res)
            user32.SetWindowPos(ov_hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_KEEP)
        elif ov_state["shown"]:
            oc.delete("all")
            ov.withdraw()
            ov_state["shown"] = False
        root.after(30, animate)

    def tick():
        # the spear only shows while League's game window is the active window
        if game_focused():
            if root.state() == "withdrawn":
                root.deiconify()
            c.itemconfig("spear", fill=SPEAR_ON)
            user32.SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_KEEP)  # stay above the game
        elif root.state() != "withdrawn":
            root.withdraw()
        root.after(500, tick)

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
    threading.Thread(target=worker, daemon=True).start()
    threading.Thread(target=camera_watch, daemon=True).start()
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

"""League of Legends macro helper (Windows).

Features (only active while the League game window is focused):
  * Scroll wheel  -> holds 1, next scroll releases it and holds 2, then 3, 4, back to 1.
                     Scroll up = next, scroll down = previous. Any other key/click releases it.
  * Hold N        -> sends Stop (STOP_KEY) every 0.6 s while N is held.
  * Tab + Win     -> hold both: unlocks camera (if locked) and pans it (holds PAN_KEY)
                     quick tap both: locks the camera again.
  * Win key       -> Start menu is blocked from popping up when you tap Win in game.
  * Kalista E     -> line on the target's health bar at the HP Rend kills at (moves right
                     with more spears) + lightning around the screen when Rend kills
                     (pulsing border when one more spear would kill). See lol_execute.py.

Keybinds it relies on are set by lol_settings.py (stop = v, camera lock = y, pan = h).

Setup:  pip install pynput pystray rapidocr_onnxruntime mss
Run:    3£ tray menu -> LoL macros (or: python lol.py, Ctrl+C to quit)
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
STOP_INTERVAL = 0.6
CAM_LOCK_KEY = "y"        # must match evtCameraLockToggle
PAN_KEY = "h"             # must match evtOnUIMouse4Pan
COMBO_HOLD = 0.25         # Tab+Win held longer than this = unlock + pan; shorter = lock
CAMERA_STARTS_LOCKED = True
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
SCAN = {"1": 0x02, "2": 0x03, "3": 0x04, "4": 0x05, "5": 0x06, "v": 0x2F, "y": 0x15, "h": 0x23}
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
VK_TAB, VK_LWIN, VK_N = 0x09, 0x5B, 0x4E
WM_KEYDOWN, WM_KEYUP, WM_SYSKEYDOWN, WM_SYSKEYUP = 0x100, 0x101, 0x104, 0x105
WM_MOUSEWHEEL = 0x020A
MOUSE_DOWNS = {0x0201, 0x0204, 0x0207, 0x020B}  # L, R, M, X button down
LLKHF_INJECTED, LLMHF_INJECTED = 0x10, 0x01

actions = queue.Queue()          # hook callbacks must be fast -> do the work on a worker
lock = threading.Lock()
pressed = set()                  # physical keys currently down
cycle_idx = -1                   # index into CYCLE_KEYS, -1 = none
held_num = None                  # number key we are holding
n_held = False
combo = {"active": False, "start": 0.0, "panning": False}
camera_locked = CAMERA_STARTS_LOCKED


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


def stop_spam():
    while True:
        time.sleep(STOP_INTERVAL)
        if not n_held:
            return
        actions.put(lambda: tap(STOP_KEY))


def combo_watch(start):
    global camera_locked
    time.sleep(COMBO_HOLD)

    def go():
        global camera_locked
        if combo["active"] and combo["start"] == start:
            if camera_locked:
                tap(CAM_LOCK_KEY)
                camera_locked = False
            key_down(PAN_KEY)
            combo["panning"] = True
    actions.put(go)


def combo_end():
    global camera_locked
    if not combo["active"]:
        return
    combo["active"] = False
    if combo["panning"]:
        key_up(PAN_KEY)
        combo["panning"] = False
    elif time.time() - combo["start"] < COMBO_HOLD and not camera_locked:
        tap(CAM_LOCK_KEY)
        camera_locked = True


def worker():
    while True:
        fn = actions.get()
        try:
            fn()
        except Exception as e:  # keep the macro alive
            print("action error:", e)


# ---------------- hooks ----------------
def kb_filter(msg, data):
    global n_held
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
        if vk == VK_N:
            n_held = False
        if vk in (VK_TAB, VK_LWIN):
            actions.put(combo_end)
        return True

    if not game_focused():
        return True

    if first_down:
        if held_num:
            actions.put(lambda: release_num(reset=True))  # any other key releases the number
        if vk == VK_LWIN:
            actions.put(mask_win)
        if vk == VK_N and not n_held:
            n_held = True
            threading.Thread(target=stop_spam, daemon=True).start()
        if vk in (VK_TAB, VK_LWIN) and VK_TAB in pressed and VK_LWIN in pressed and not combo["active"]:
            start = time.time()
            combo.update(active=True, start=start, panning=False)
            threading.Thread(target=combo_watch, args=(start,), daemon=True).start()
    return True


def mouse_filter(msg, data):
    if data.flags & LLMHF_INJECTED or not game_focused():
        return True
    if msg == WM_MOUSEWHEEL:
        delta = ctypes.c_short(data.mouseData >> 16).value
        actions.put(lambda d=(1 if delta > 0 else -1): do_scroll(d))
        mouse_listener.suppress_event()  # don't zoom the camera
    elif msg in MOUSE_DOWNS and held_num:
        actions.put(lambda: release_num(reset=True))
    return True


def cleanup():
    release_num()
    if combo["panning"]:
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
        c.itemconfig("spear", fill=SPEAR_ON if game_focused() else SPEAR_IDLE)
        user32.SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_KEEP)  # stay above the game
        root.after(500, tick)

    tick()
    animate()
    return root


quit_requested = threading.Event()


def make_tray():
    """System tray icon with a Quit option."""
    import pystray
    from PIL import Image, ImageDraw
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for poly in spear_polys(64, pad=3):
        d.polygon(poly, fill=SPEAR_ON, outline=SPEAR_EDGE, width=2)
    icon = pystray.Icon("lol_macros", img, "LoL macros: running", menu=pystray.Menu(
        pystray.MenuItem("LoL macros running", None, enabled=False),
        pystray.MenuItem("Quit", lambda icon, item: (quit_requested.set(), icon.stop())),
    ))
    icon.run_detached()
    return icon


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
    kb_listener = keyboard.Listener(win32_event_filter=kb_filter)
    mouse_listener = mouse.Listener(win32_event_filter=mouse_filter)
    kb_listener.start()
    mouse_listener.start()
    print("lol.py running - active only while the League game window is focused. Ctrl+C to quit.")
    watcher = lol_execute.ExecuteWatcher(game_focused)
    root = make_indicator()
    tray = make_tray()

    STOP_FILE = os.path.join(os.path.dirname(PID_FILE), "lol.stop")

    def keepalive():  # lets Ctrl+C reach Python while Tk's loop runs; handles tray Quit
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
        tray.stop()
        kb_listener.stop()
        mouse_listener.stop()

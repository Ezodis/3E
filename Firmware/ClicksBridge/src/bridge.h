// Hardware-independent key logic of the Clicks bridge (tested in test/test_bridge.cpp).
// Reports are boot-keyboard reports: [modifiers, reserved, key1..key6].
#pragma once
#include <stdint.h>
#include <string.h>

static const int SLOTS = 6;             // 0-4: hosts (keys 1-5), 5: the watch (key 9)
static const int WATCH_SLOT = 5;
static const int NAME_LEN = 32;
static const int WATCH_BUFFER = 480;
static const uint32_t CONFIG_MAGIC = 0x33454231;  // "3EB1"
static const char* const BRIDGE_NAME = "Power Keyboard Bridge";  // 3£ on Windows matches "Power Keyboard*"
static const char* const WATCH_SERVICE_UUID = "3e0b0001-c11c-4b5e-9a3e-000000000000";
static const char* const WATCH_TEXT_UUID = "3e0b0002-c11c-4b5e-9a3e-000000000000";
static const char* const WATCH_CLEAR_UUID = "3e0b0003-c11c-4b5e-9a3e-000000000000";

enum Os : uint8_t { OS_WINDOWS = 0, OS_APPLE = 1 };

// Modifier bits.
static const uint8_t M_LCTRL = 0x01, M_LSHIFT = 0x02, M_LALT = 0x04, M_LGUI = 0x08,
                     M_RCTRL = 0x10, M_RSHIFT = 0x20, M_RALT = 0x40, M_RGUI = 0x80;
static const uint8_t STICKY_MODS = M_LCTRL | M_LSHIFT | M_LGUI | M_RCTRL | M_RSHIFT | M_RGUI;
// Keys.
static const uint8_t K_K = 0x0E, K_SPACE = 0x2C, K_W = 0x1A, K_M = 0x10, K_1 = 0x1E, K_5 = 0x22, K_9 = 0x26, K_0 = 0x27,
                     K_ENTER = 0x28, K_BACKSPACE = 0x2A, K_TAB = 0x2B;

static const uint32_t DOUBLE_TAP_MS = 400, COMMAND_MS = 3000;
static const uint32_t STICKY_WINDOW_MS = 7000, STICKY_LATE_MS = 2000, STICKY_EXTEND_MS = 3000;

inline bool isClicksName(const char* name) {
  return strncmp(name, "Power Keyboard", 14) == 0 && strncmp(name, BRIDGE_NAME, strlen(BRIDGE_NAME)) != 0;
}

struct Config {
  uint32_t magic = CONFIG_MAGIC;
  uint8_t active = 0;
  uint8_t os[SLOTS] = {OS_WINDOWS, OS_WINDOWS, OS_WINDOWS, OS_WINDOWS, OS_WINDOWS, OS_APPLE};
  char names[SLOTS][NAME_LEN] = {};
};

struct Command {
  enum Kind : uint8_t { None, Slot, Pair, Os } kind = None;
  uint8_t value = 0;
};

struct Output {
  bool hasReport = false;
  uint8_t report[8] = {};
  bool hasRelease = false;   // a second report sent right after the first (sticky release)
  uint8_t release[8] = {};
  Command command;
  char text[16] = {};
  uint8_t textLen = 0;
};

class Bridge {
 public:
  void process(const uint8_t raw[8], uint32_t now, const Config& config, Output& out) {
    out = Output();
    uint8_t mods = raw[0];
    const uint8_t* keys = raw + 2;

    // Double-tap the six-dot key (it sends Alt+K), then one key: a bridge command.
    bool six = (mods & M_LALT) && has(keys, K_K);
    if (six && !prevSix) {
      if (lastSix && now - lastSix <= DOUBLE_TAP_MS) { commandUntil = now + COMMAND_MS; lastSix = 0; }
      else lastSix = now;
    }
    prevSix = six;
    if (commandUntil && (int32_t)(commandUntil - now) < 0) commandUntil = 0;
    for (int i = 0; i < 6; i++) {
      uint8_t k = keys[i];
      if (!k || has(prev + 2, k) || k == K_K) continue;
      if (commandUntil) {
        commandUntil = 0;
        Command c = commandFor(k);
        if (c.kind != Command::None) { out.command = c; consumed[k >> 3] |= 1 << (k & 7); }
      }
    }
    // Keys used for a command are swallowed until released.
    uint8_t keep[6] = {};
    int n = 0;
    for (int k = 0; k < 256; k++)
      if ((consumed[k >> 3] & (1 << (k & 7))) && !has(keys, (uint8_t)k)) consumed[k >> 3] &= ~(1 << (k & 7));
    for (int i = 0; i < 6; i++)
      if (keys[i] && !(consumed[keys[i] >> 3] & (1 << (keys[i] & 7)))) keep[n++] = keys[i];

    uint8_t slot = out.command.kind == Command::Slot ? out.command.value : config.active;
    if (slot == WATCH_SLOT) typeText(mods, keep, out);
    else if (config.os[slot] == OS_APPLE) apple(mods, keep, now, out);
    else { out.hasReport = true; out.report[0] = mods; memcpy(out.report + 2, keep, 6); }

    memcpy(prev, raw, 8);
    memcpy(prevKept, keep, 6);
  }

  // Sticky window expiry (Apple hosts).
  void tick(uint32_t now, const Config& config, Output& out) {
    out = Output();
    if (sticky && (int32_t)(now - deadline) >= 0 && !anyKey(prevKept)) {
      sticky = 0;
      used = false;
      if (config.active != WATCH_SLOT && config.os[config.active] == OS_APPLE) {
        out.hasReport = true;
        out.report[0] = physicalMods;
      }
    }
  }

  uint8_t stickyMods() const { return sticky; }

 private:
  uint8_t prev[8] = {};
  uint8_t prevKept[6] = {};
  uint8_t consumed[32] = {};
  bool prevSix = false;
  uint32_t lastSix = 0, commandUntil = 0;
  // sticky (Apple)
  uint8_t sticky = 0, tapCandidate = 0, physicalMods = 0;
  bool used = false;
  uint32_t deadline = 0;

  static bool has(const uint8_t* keys, uint8_t k) {
    for (int i = 0; i < 6; i++) if (keys[i] == k) return true;
    return false;
  }
  static bool anyKey(const uint8_t* keys) {
    for (int i = 0; i < 6; i++) if (keys[i]) return true;
    return false;
  }
  static Command commandFor(uint8_t k) {
    Command c;
    if (k >= K_1 && k <= K_5) { c.kind = Command::Slot; c.value = k - K_1; }
    else if (k == K_9) { c.kind = Command::Slot; c.value = WATCH_SLOT; }
    else if (k == K_0) c.kind = Command::Pair;
    else if (k == K_W) { c.kind = Command::Os; c.value = OS_WINDOWS; }
    else if (k == K_M) { c.kind = Command::Os; c.value = OS_APPLE; }
    return c;
  }

  // Apple: the six-dot key becomes Cmd+Space; Command/Ctrl/Shift taps are sticky.
  void apple(uint8_t mods, const uint8_t keys[6], uint32_t now, Output& out) {
    uint8_t k[6];
    memcpy(k, keys, 6);
    if (mods & M_LALT) {
      mods &= ~M_LALT;
      for (int i = 0; i < 6; i++) if (k[i] == K_K) { k[i] = K_SPACE; mods |= M_LGUI; }
    }
    uint8_t pressed = mods & ~physicalMods, released = physicalMods & ~mods;
    bool keyDown = false, keyUp = false;
    for (int i = 0; i < 6; i++) if (keys[i] && !has(prevKept, keys[i])) keyDown = true;
    for (int i = 0; i < 6; i++) if (prevKept[i] && !has(keys, prevKept[i])) keyUp = true;
    bool keysHeld = anyKey(keys);

    for (uint8_t bit = 1; bit; bit <<= 1) {
      if (!(bit & STICKY_MODS)) continue;
      if ((pressed & bit) && !keysHeld) tapCandidate = bit;
      if (released & bit) {
        if (tapCandidate == bit) {
          tapCandidate = 0;
          if (!(sticky & bit)) {
            if (!sticky) deadline = now + STICKY_WINDOW_MS;
            else if ((int32_t)(deadline - now) < (int32_t)STICKY_LATE_MS) deadline += STICKY_EXTEND_MS;
            sticky |= bit;
          }
        }
      }
    }
    if (keyDown) { tapCandidate = 0; if (sticky) used = true; }
    physicalMods = mods;

    out.hasReport = true;
    out.report[0] = mods | sticky;
    memcpy(out.report + 2, k, 6);
    if (keyUp && used && !keysHeld) {  // the shortcut is done: its key-up first, then release
      sticky = 0;
      used = false;
      out.hasRelease = true;
      out.release[0] = mods;
      memcpy(out.release + 2, k, 6);
    }
  }

  // Watch: newly pressed keys become text.
  void typeText(uint8_t mods, const uint8_t keys[6], Output& out) {
    bool shift = mods & (M_LSHIFT | M_RSHIFT);
    for (int i = 0; i < 6 && out.textLen < sizeof(out.text); i++) {
      uint8_t k = keys[i];
      if (!k || has(prevKept, k) || (mods & M_LALT)) continue;
      char c = toChar(k, shift);
      if (c) out.text[out.textLen++] = c;
    }
  }

 public:
  static char toChar(uint8_t k, bool shift) {
    if (k >= 0x04 && k <= 0x1D) return (char)((shift ? 'A' : 'a') + (k - 0x04));
    static const char digits[] = "1234567890", shifted[] = "!@#$%^&*()";
    if (k >= 0x1E && k <= 0x27) return shift ? shifted[k - 0x1E] : digits[k - 0x1E];
    switch (k) {
      case K_ENTER: return '\n';
      case K_BACKSPACE: return '\b';
      case K_TAB: return '\t';
      case K_SPACE: return ' ';
      case 0x2D: return shift ? '_' : '-';
      case 0x2E: return shift ? '+' : '=';
      case 0x2F: return shift ? '{' : '[';
      case 0x30: return shift ? '}' : ']';
      case 0x31: return shift ? '|' : '\\';
      case 0x33: return shift ? ':' : ';';
      case 0x34: return shift ? '"' : '\'';
      case 0x35: return shift ? '~' : '`';
      case 0x36: return shift ? '<' : ',';
      case 0x37: return shift ? '>' : '.';
      case 0x38: return shift ? '?' : '/';
    }
    return 0;
  }
};

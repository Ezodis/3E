// Hardware-independent key logic of the Clicks watch bridge (tested in test/test_bridge.cpp).
// Reports are boot-keyboard reports: [modifiers, reserved, key1..key6].
#pragma once
#include <stdint.h>
#include <string.h>

static const int NAME_LEN = 32;
static const int WATCH_BUFFER = 480;
static const uint32_t CONFIG_MAGIC = 0x33455732;  // "3EW2"
static const char* const BRIDGE_NAME = "Clicks Watch Bridge";
static const char* const WATCH_SERVICE_UUID = "3e0b0001-c11c-4b5e-9a3e-000000000000";
static const char* const WATCH_TEXT_UUID = "3e0b0002-c11c-4b5e-9a3e-000000000000";
static const char* const WATCH_CLEAR_UUID = "3e0b0003-c11c-4b5e-9a3e-000000000000";

static const uint8_t M_LSHIFT = 0x02, M_LALT = 0x04, M_RSHIFT = 0x20;
static const uint8_t K_K = 0x0E, K_0 = 0x27, K_SPACE = 0x2C, K_ENTER = 0x28, K_BACKSPACE = 0x2A, K_TAB = 0x2B;
static const uint32_t DOUBLE_TAP_MS = 400, COMMAND_MS = 3000;

inline bool isClicksName(const char* name) { return strncmp(name, "Power Keyboard", 14) == 0; }

struct Config {
  uint32_t magic = CONFIG_MAGIC;
  char watch[NAME_LEN] = {};  // the paired watch; empty = the next watch that pairs
};

struct Output {
  bool forgetWatch = false;   // double-tap six-dot, then 0
  char text[16] = {};
  uint8_t textLen = 0;
};

class Bridge {
 public:
  void process(const uint8_t raw[8], uint32_t now, Output& out) {
    out = Output();
    uint8_t mods = raw[0];
    const uint8_t* keys = raw + 2;
    bool six = (mods & M_LALT) && has(keys, K_K);  // the six-dot key sends Alt+K
    if (six && !prevSix) {
      if (lastSix && now - lastSix <= DOUBLE_TAP_MS) { commandUntil = now + COMMAND_MS; lastSix = 0; }
      else lastSix = now;
    }
    prevSix = six;
    if (commandUntil && (int32_t)(commandUntil - now) < 0) commandUntil = 0;
    bool shift = mods & (M_LSHIFT | M_RSHIFT);
    for (int i = 0; i < 6; i++) {
      uint8_t k = keys[i];
      if (!k || has(prev + 2, k) || k == K_K && (mods & M_LALT)) continue;
      if (commandUntil) {
        commandUntil = 0;
        if (k == K_0) { out.forgetWatch = true; continue; }
      }
      char c = toChar(k, shift);
      if (c && out.textLen < sizeof(out.text)) out.text[out.textLen++] = c;
    }
    memcpy(prev, raw, 8);
  }

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

 private:
  uint8_t prev[8] = {};
  bool prevSix = false;
  uint32_t lastSix = 0, commandUntil = 0;
  static bool has(const uint8_t* keys, uint8_t k) {
    for (int i = 0; i < 6; i++) if (keys[i] == k) return true;
    return false;
  }
};

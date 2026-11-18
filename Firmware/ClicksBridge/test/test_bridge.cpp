// Host test for bridge.h:  zig c++ -std=c++17 -I src test/test_bridge.cpp -o test_bridge.exe
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include "../src/bridge.h"

static int passed = 0;
static void check(bool ok, const char* what) {
  if (!ok) { std::printf("FAIL %s\n", what); std::exit(1); }
  std::printf("PASS %s\n", what);
  passed++;
}

struct Rig {
  Bridge b;
  Output o;
  uint32_t t = 1000;
  Output& send(uint8_t mods, uint8_t k1 = 0, uint8_t k2 = 0, uint32_t dt = 50) {
    t += dt;
    uint8_t raw[8] = {mods, 0, k1, k2, 0, 0, 0, 0};
    b.process(raw, t, o);
    return o;
  }
  void sixTap() { send(M_LALT, K_K); send(0); }
};

int main() {
  {
    Rig r;
    check(r.send(0, 0x0B).textLen == 1 && r.o.text[0] == 'h', "key becomes text");
    check(r.send(0, 0x0B).textLen == 0, "held key is not repeated");
    r.send(0);
    check(r.send(M_LSHIFT, 0x0C).text[0] == 'I', "shift gives uppercase");
    r.send(0);
    check(r.send(M_LSHIFT, 0x26).text[0] == '(', "sym + T arrives as Shift+9 and types (");
    r.send(0);
    check(r.send(0, K_BACKSPACE).text[0] == '\b', "backspace is \\b");
    r.send(0);
    check(r.send(0, K_ENTER).text[0] == '\n', "enter is a new line");
    r.send(0);
    check(r.send(0, 0x0B, 0x08).textLen == 2, "two keys pressed together");
  }
  {
    Rig r;
    r.send(M_LALT, K_K);
    check(r.o.textLen == 0, "six-dot types nothing");
    r.send(0);
    r.sixTap();
    check(r.send(0, K_0).forgetWatch && r.o.textLen == 0, "double six-dot then 0 pairs a new watch");
    r.send(0);
    check(r.send(0, K_0).text[0] == '0', "0 types normally afterwards");
  }
  {
    Rig r;
    r.sixTap();
    check(!r.send(0, K_0, 0, 600).forgetWatch, "a single six-dot tap is not a command");
  }
  {
    Rig r;
    r.sixTap(); r.sixTap();
    check(!r.send(0, K_0, 0, 3500).forgetWatch && r.o.text[0] == '0', "command mode expires after 3 s");
  }
  check(isClicksName("Power Keyboard-7009-9") && !isClicksName(BRIDGE_NAME), "connects only to the Clicks keyboard");
  std::printf("%d passed\n", passed);
  return 0;
}

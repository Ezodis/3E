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
  Config c;
  Output o;
  uint32_t t = 1000;
  Output& send(uint8_t mods, uint8_t k1 = 0, uint8_t k2 = 0, uint32_t dt = 50) {
    t += dt;
    uint8_t raw[8] = {mods, 0, k1, k2, 0, 0, 0, 0};
    b.process(raw, t, c, o);
    return o;
  }
  Output& tick(uint32_t dt) { t += dt; b.tick(t, c, o); return o; }
  void sixTap() { send(M_LALT, K_K); send(0); }
};

static bool report(const Output& o, uint8_t mods, uint8_t k1 = 0) {
  return o.hasReport && o.report[0] == mods && o.report[2] == k1 && o.report[3] == 0;
}

int main() {
  {  // Windows: everything passes through untouched.
    Rig r;
    check(report(r.send(M_LGUI, 0x06), M_LGUI, 0x06), "windows passes Win+C unchanged");
    check(report(r.send(M_LALT, K_K), M_LALT, K_K), "windows passes the six-dot key (Alt+K) for 3E");
    check(report(r.send(0), 0), "windows release");
    check(!r.o.hasRelease, "windows never adds a sticky release");
  }
  {  // Double-tap six-dot, then a number: switch host, number swallowed.
    Rig r;
    r.sixTap();
    r.sixTap();
    Output& o = r.send(0, 0x1F);  // '2'
    check(o.command.kind == Command::Slot && o.command.value == 1, "double six-dot then 2 selects host 2");
    check(o.hasReport && o.report[2] == 0, "command key is not typed");
    check(r.send(0).report[2] == 0, "command key release is not typed");
    check(r.send(0, 0x1F).report[2] == 0x1F, "2 types normally afterwards");
  }
  {  // A single six-dot tap followed by a number types the number.
    Rig r;
    r.sixTap();
    check(r.send(0, 0x1F, 0, 600).command.kind == Command::None, "single six-dot tap is not a command");
  }
  {  // Slow double tap is not a command.
    Rig r;
    r.send(M_LALT, K_K); r.send(0, 0, 0, 500); r.send(M_LALT, K_K); r.send(0);
    check(r.send(0, K_0).command.kind == Command::None, "taps 550 ms apart are not a double tap");
  }
  {  // Command mode expires after 3 s.
    Rig r;
    r.sixTap(); r.sixTap();
    check(r.send(0, K_9, 0, 3500).command.kind == Command::None, "command mode expires");
  }
  {
    Rig r;
    r.sixTap(); r.sixTap();
    check(r.send(0, K_9).command.kind == Command::Slot && r.o.command.value == WATCH_SLOT, "9 selects the watch");
    r.sixTap(); r.sixTap();
    check(r.send(0, K_0).command.kind == Command::Pair, "0 pairs");
    r.send(0);
    r.sixTap(); r.sixTap();
    check(r.send(0, K_M).command.kind == Command::Os && r.o.command.value == OS_APPLE, "M marks Apple");
    r.send(0);
    r.sixTap(); r.sixTap();
    check(r.send(0, K_W).command.kind == Command::Os && r.o.command.value == OS_WINDOWS, "W marks Windows");
  }
  {  // Apple: six-dot is Cmd+Space.
    Rig r;
    r.c.os[0] = OS_APPLE;
    check(report(r.send(M_LALT, K_K), M_LGUI, K_SPACE), "apple six-dot sends Cmd+Space");
    check(report(r.send(0), 0), "apple six-dot release");
  }
  {  // Apple sticky Command: tap, then C -> Cmd+C, released after C.
    Rig r;
    r.c.os[0] = OS_APPLE;
    r.send(M_LGUI);
    check(report(r.send(0), M_LGUI), "tapped Command stays held");
    check(report(r.send(0, 0x06), M_LGUI, 0x06), "next key gets Command");
    Output& o = r.send(0);
    check(report(o, M_LGUI) && o.hasRelease && o.release[0] == 0, "key-up first, then Command releases");
    check(r.b.stickyMods() == 0, "sticky cleared");
  }
  {  // Apple: Cmd, Alt-less chord Cmd+Shift+4 by taps.
    Rig r;
    r.c.os[0] = OS_APPLE;
    r.send(M_LGUI); r.send(0);
    r.send(M_LSHIFT); r.send(0);
    check(report(r.send(0, 0x21), M_LGUI | M_LSHIFT, 0x21), "Cmd then Shift taps then 4 = Cmd+Shift+4");
  }
  {  // Apple: window ends after 7 s, no extension unless late.
    Rig r;
    r.c.os[0] = OS_APPLE;
    r.send(M_LGUI); r.send(0);                 // t=1100, deadline 8100
    r.send(M_LSHIFT, 0, 0, 1000); r.send(0);   // early: no extension
    check(!r.tick(5800).hasReport, "still held before 7 s");
    Output& o = r.tick(200);
    check(o.hasReport && o.report[0] == 0 && r.b.stickyMods() == 0, "all stickies release at 7 s");
  }
  {
    Rig r;
    r.c.os[0] = OS_APPLE;
    r.send(M_LGUI); r.send(0);                 // t=1100, deadline 8100
    r.tick(5500);                              // t=6600
    r.send(M_LSHIFT); r.send(0);               // t=6700, 1.4 s left: deadline 11100
    check(!r.tick(2000).hasReport, "late tap added 3 s");           // t=8700
    check(!r.tick(2300).hasReport, "still held just before 11.1 s");  // t=11000
    check(r.tick(100).hasReport && r.b.stickyMods() == 0, "extended window ends");
  }
  {  // Apple: held Command works normally.
    Rig r;
    r.c.os[0] = OS_APPLE;
    r.send(M_LGUI);
    r.send(M_LGUI, 0x06);
    r.send(M_LGUI);
    check(report(r.send(0), 0) && r.b.stickyMods() == 0, "held Command is not sticky");
  }
  {  // Watch: keys become text.
    Rig r;
    r.c.active = WATCH_SLOT;
    Output& o = r.send(0, 0x0B);  // h
    check(o.textLen == 1 && o.text[0] == 'h' && !o.hasReport, "watch gets text, not keys");
    r.send(0);
    check(r.send(M_LSHIFT, 0x0C).text[0] == 'I', "watch shift");
    r.send(0);
    check(r.send(0, K_BACKSPACE).text[0] == '\b', "watch backspace");
    r.send(0);
    check(r.send(0, K_ENTER).text[0] == '\n', "watch enter");
  }
  check(isClicksName("Power Keyboard-7009-9") && !isClicksName(BRIDGE_NAME) && !isClicksName("Magic Keyboard"),
        "connects only to the Clicks keyboard, never another bridge");
  std::printf("%d passed\n", passed);
  return 0;
}

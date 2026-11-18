# Clicks → Apple Watch bridge (nice!nano)

Firmware for a nice!nano (nRF52840) that lets the Clicks Power Keyboard type into your own
Apple Watch app. watchOS does not accept Bluetooth keyboards, so the nano connects to the
keyboard, turns its keys into text, and keeps that text for the watch app, which reads it
over a private Bluetooth service.

Windows and Mac use the Clicks keyboard directly through the 3£ app. Point the keyboard at the
nano with the keyboard's own Power + number when you want to type on the watch.

- Shift gives uppercase; sym + key arrives as the keyboard sends it (sym + T types "(").
- Enter is `\n`, Backspace is `\b`, Tab is `\t`.
- The first watch that pairs is kept. To pair a different watch: double-tap the six-dot key,
  then press 0 within 3 s.
- The nano keeps up to 480 characters until the watch app clears them, so text typed while
  the app is closed or the watch is locked is waiting when the app reads it.

## Watch app service

- Service `3e0b0001-c11c-4b5e-9a3e-000000000000`
- `3e0b0002-…` text: read = everything not cleared yet; notify = each new piece of text.
- `3e0b0003-…` clear: write one byte after storing the text.

Both require an encrypted (paired) connection.

## Build and flash

```powershell
pio run                                   # PlatformIO, Adafruit nRF52 core
python uf2conv.py -f 0xADA52840 -c -o ClicksBridge.uf2 .pio/build/nicenano/firmware.hex
```

Double-tap the nano's reset to open the `NICENANO` drive, then copy `ClicksBridge.uf2` to it.

Key logic tests (no hardware): `zig c++ -std=c++17 -Isrc test/test_bridge.cpp -o test_bridge.exe`

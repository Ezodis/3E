# Clicks keyboard bridge (nice!nano)

Firmware for a nice!nano (nRF52840) that sits between the Clicks Power Keyboard and your
devices. The keyboard pairs with the nano; the nano pairs with up to five devices plus an
Apple Watch app and forwards every key.

| Device slot | What the nano sends |
|---|---|
| Windows (default) | Every key unchanged. The nano reports the Clicks keyboard's Bluetooth ID and a `Power Keyboard Bridge` name, so 3£ handles it like the Clicks keyboard (Command/Ctrl, sticky keys, accent picker, Mac layout). Run the 3£ installer with `-RepairKeyboard` once after pairing. |
| Apple (Mac, iPhone, iPad) | Command, Ctrl and Shift taps are sticky for one shared 7 s window (+3 s for a tap in its last 2 s); every sticky releases when the window ends. The six-dot key sends Cmd+Space (Spotlight). |
| Watch (slot 9) | Keys become text kept in a buffer (480 characters) that the watch app reads and clears. |

sym and the mic key are handled inside the keyboard and never sent over Bluetooth, so
they work exactly as before (sym + key types the symbol).

## Bridge commands

Double-tap the six-dot key, then within 3 s press:

- `1`–`5`: send keys to that device
- `9`: send keys to the watch app
- `0`: pair a new device on the current slot (60 s)
- `W` / `M`: the current slot is Windows / Apple

An empty slot takes the first device that pairs with it.

## Watch app service

- Service `3e0b0001-c11c-4b5e-9a3e-000000000000`
- `3e0b0002-…` text: read = everything not cleared yet; notify = each new piece of text.
  Enter is `\n`, Backspace is `\b`.
- `3e0b0003-…` clear: write one byte after storing the text.

Both need an encrypted (paired) connection.

## Build and flash

```powershell
pio run                                   # PlatformIO, Adafruit nRF52 core
python uf2conv.py -f 0xADA52840 -c -o ClicksBridge.uf2 .pio/build/nicenano/firmware.hex
```

Double-tap the nano's reset to open the `NICENANO` drive, then copy `ClicksBridge.uf2` to it.

Key logic tests (no hardware): `zig c++ -std=c++17 -Isrc test/test_bridge.cpp -o test_bridge.exe`

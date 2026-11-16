# Thunderbird PC205 – USB HID configuration protocol

Reverse-engineered by **static analysis only** of the vendor's Windows configurator
(`Setup.exe`, kept out of this repo). Nothing was installed or run on Windows and no USB traffic was captured.

Implementations in 3£:

- **Windows:** tray menu → **Mouse…**. The device module is `Windows/Mouse/Devices/PC205/`, on top of the generic model and window in `Windows/Mouse/`. Tests are in `Windows/MouseTests/`.
- **Mac:** menu-bar menu → **Mouse…** opens the bundled `3£ Mouse.app` helper. The device module is in `TouchBar/threee/Mouse/Sources/Mouse{Core,HID}/Devices/PC205/`; run `swift test` in `TouchBar/threee/Mouse`.

To add another mouse, add one `Devices/<Name>` module on each platform (capabilities, encoding, driver) and one line in the registry (`MouseDevices`). The window builds itself from the device's capabilities.
Each item below is tagged:

- **[code]**: read directly from the decompiled code paths that the PC205 configuration takes.
- **[cfg]**: read from the vendor `Cfg.ini` that ships with the PC205 installer.
- **[inferred]**: a reasoned guess that still needs checking on real hardware.

## 1. Where it comes from

| Item | Value |
|---|---|
| Installer | Inno Setup 5.3.3, extracted with `innoextract` in a throwaway GitHub Actions job |
| Config app | `app/OemDrv.exe` (MFC, 32-bit, "BY-COMBO Gaming Driver", version 1.0.3) |
| HID helper | `app/Lowerdev.dll` (internally `HidParse.dll` v1.8): `OpenHidDevice`, `SetFeature`, `GetFeature` |
| Device config | `app/Cfg.ini`: `[MS] VID=0x258A PID=0x1007 Sensor=0x3212`, `[OPT] MsFw=7 MacProtocol=2` |
| Same binaries as | the vendor's "T16 Wired Gaming Mouse" package (identical SHA-1 for `OemDrv.exe`, `Lowerdev.dll` and `Cfg.ini`) |

`OemDrv.exe` only ever calls `HidD_SetFeature` / `HidD_GetFeature` (through `Lowerdev.dll`).
It never uses output reports, `WriteFile`, a filter driver or a firmware updater. **[code]**

The firmware family is Sinowealth "8832" (`CDrv8832`). `MsFw=7` selects the apply routine
`Apply_M_AJ_8832_3` (switch at `0x0040d6d0`: case 5 and case 7 → `FUN_0040eb20`). **[code]**

## 2. HID interfaces

`CDrv8832::FindDev` (`0x0040bc50`) opens four handles. All four are **Usage Page 0xFF00,
Usage 0x01**. It tells them apart by report length. **[code]**

| Handle | How it is matched | Report used | Payload length (without report ID) |
|---|---|---|---|
| `m_hGeneral` | FeatureReportByteLength == 59 (`0x3b`) | Feature **ID 4** | 58 |
| `m_hMatrix` | FeatureReportByteLength == 1145 (`0x479`) | Feature **ID 6** | 1144 (`0x478`) |
| `m_hMode` | FeatureReportByteLength == 9 | Feature **ID 8** | 8 |
| `m_hNotify` | InputReportByteLength == 5 | Input (read thread; status notifications) | 4 |

(For MsFw 2/3/8 the matrix length would be `0x428` and for MsFw 10 the general length would be 80.
The PC205 uses neither.)

Both send and receive retry 3 times with 200 ms between tries. The app waits 20 ms between
reports. **[code]**

Windows 3£ matches collections by feature length, exactly like the vendor. On macOS every top-level
collection or USB interface shows up as an `IOHIDDevice`. The Mac helper picks the device by
feature-report size and then checks the signature in the general report.

## 3. General report: Feature ID 4, 58-byte payload

The app reads it first (`GetFeature`), changes it, then writes it back. Offsets below count from the
first byte after the report ID.

| Offset | Meaning | Source |
|---|---|---|
| 0 | Sensor code (8 = PMW3212 `0x3212`; 1=`0x5050`, 2=`0x3050`, 3=`0x9800`, 4=`0x3320`, 5=`0x3330`, 6=`0x3360`, 7=`0x3610`, 9=`0x3310`, 11=`0x3325`, 12=`0x7350`, 14=`0x3327`) | [code] `FUN_00458270` mapping; which byte holds it is [inferred] |
| 1 | low nibble = number of **enabled** DPI stages, high nibble = **current** DPI stage (0-based) | [code] `FUN_0040ea30`, FindDev |
| 2 | low nibble = 1 when X/Y DPI is independent | [code] |
| 3 | not touched by the app (keep as read) | – |
| 4–19 | DPI stages: 8 stages × 1 byte (or × 2 bytes X,Y when bit 0 of byte 2 is set). `bit7 = 1` → stage disabled; `bits0-6` = DPI code. Unused bytes = `0x80` | [code] |
| 20 | Lighting: high nibble = effect+1 (0 = off/"None"), low nibble = speed / brightness level | [code] |
| 21 | Lighting flags: bit7 = random/colourful variant; low bits = number of colours used | [code] (exact meaning per effect [inferred]) |
| 22–42 | Up to 7 lighting colours, 3 bytes each, **R,G,B** order (no `RGB order` key in Cfg.ini → default `0x020100`) | [code]/[cfg] |
| 43–50 | Colour of DPI stage 1…8 as a palette index: 1 red, 2 green, 3 blue, 4 cyan, 5 yellow, 6 magenta, 7 white, 0 none | [code] (default `PickColor` table) |
| 51 | `0x20`, bit0 = an extra option flag (kept as read) | [code] |
| 52–57 | Device signature, compared against `PSD=0x46,0x52,0x32,0x37,0x36,0x33` (**"FR2763"**) | [code]+[cfg]; offset [inferred] |

### DPI codes

With no `DPIHW` key in Cfg.ini, the hardware code is the 1-based index in `DPISET`. **[code]+[cfg]**

| Code | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 16 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| DPI | 500 | 800 | 1000 | 1200 | 1600 | 2000 | 2400 | 3000 | 3200 | 3500 | 4000 | 4500 | 5000 | 5500 | 6000 | 7200 |

Vendor defaults: 5 stages (`DM=5`) of 1200 / 2400 / 3500 / 5500 / 7200, coloured red, blue, green,
magenta, yellow. `DEFLEVEL=1` (the second stage).

### Lighting effects

Effect index (hardware value = index+1):

| Index | Name | Shown by vendor UI? |
|---|---|---|
| 0 | Colorful Streaming | yes |
| 1 | Steady (low nibble = brightness level, 1–8) | yes |
| 2 | Breathing | yes |
| 3 | Tail | yes |
| 4 | Neon | yes |
| 5 | Colorful Steady | hidden (`LedMask` bit 5) |
| 6 | Flicker | hidden (bit 6) |
| 7 | Response | yes |
| 8 | Streaming | hidden (bit 8) |
| 9 | Wave | yes |
| 10 | Trailing | hidden (bit 10) |
| 11 | None → hardware 0 | yes |

`LedMask=0x560`: a set bit hides the effect in the vendor UI (lighting page builder at about `0x0042d6c0`). **[code]**

## 4. Mode report: Feature ID 8, 8-byte payload

The app reads it first. Before writing, it changes bytes 0–3. **[code]** (`FUN_0040c4d0`, `CDrv8832` vtable +0x1c)

| Offset | Meaning |
|---|---|
| 0 | Active key mode + 1 (1…3; `MDNUM=3`) |
| 1, 2, 3 | USB polling rate for modes 1, 2, 3: `1`=125 Hz, `2`=250 Hz, `3`=500 Hz, `4`=1000 Hz |
| 4–7 | Only written by "restore defaults": `[4]` = default DPI stage + 1, `[5]=3`, `[6]=1`, `[7]=0`. Otherwise left as read |

Vendor default rate: `DR=0x500` → 500 Hz for every mode. **[cfg]**

## 5. Matrix report: Feature ID 6, 1144-byte payload (buttons and macros)

The app writes this report as a whole and never reads it back. **[code]** (`Apply_M_AJ_8832_3`, `FUN_0040d950`)

| Offset | Size | Content |
|---|---|---|
| `0x000` | 8 × 128 | Macro buffers 1…8 (`DAT_00617fc4 = 0x80`, max 8 macros) |
| `0x400` | 30 × 4 | Key entries, `uint32` **little-endian**: mode 1 slots 1–10, then mode 2, then mode 3 |

### Key entry (`uint32`)

`KeyCodeHasIndex=1` (default) → the low nibble of every entry is the **slot number (1…10)**.
Bits 4–7 give the action class. **[code]** (`FUN_0040ca60`, `FUN_0040d3c0`)

| Action | Encoding (before the slot nibble is ORed in) |
|---|---|
| Left / Right / Middle / Back / Forward | `0xF010` / `0xF110` / `0xF210` / `0xF310` / `0xF410` (byte1 = `0xF0` \| button bit) |
| Double click | `0x0232F020`: fire class, key `0xF0`, interval 0x32 (50 ms), count 2 |
| Three click | `0x0130` |
| Fire key (repeat a key) | `0x20 \| key<<8 \| interval<<16 \| count<<24`. `key` = HID keyboard usage, or `0xF0…0xF6` for mouse buttons |
| Key / key combination | `0x60 \| modifiers<<8 \| key1<<16 \| key2<<24`. Modifiers use HID bit order (bit0 LCtrl, bit1 LShift, bit2 LAlt, bit3 LGUI, bit4 RCtrl, bit5 RShift, bit6 RAlt, bit7 RGUI) |
| Multimedia | `0x70 \| b1<<8 \| b2<<16 \| b3<<24` (bitmaps below) |
| DPI loop / DPI+ / DPI- | `0x0040` / `0x2040` / `0x4040` |
| DPI lock (stage code `n`) | `0x8040 \| (n & 0xF)<<8` |
| Disable | `0x0150` |
| Switch polling rate | `0x0250` |
| Switch lighting effect (menu "Switch Effect", `0x080000AE`) | `0x0750` |
| Function `0x080000AC` (not in the PC205 menu; probably lighting-related) | `0x0450` [inferred name] |
| Function `0x080000AB` (not in the PC205 menu; special-cased in the UI, probably "Switch Mode") | `0x0650` [inferred name] |
| Macro | `0x?90 \| buffer<<12`: low nibble of byte1 = repeat mode (1 = repeat N times, 2 = while held, 4 = until another key is pressed); bits 12–15 = macro buffer 1…8 |

Multimedia bitmaps (consumer usage → bit): **[code]** `FUN_0040c880`

- b1: Next `0xB5`=0x01, Prev `0xB6`=0x02, Stop `0xB7`=0x04, Play/Pause `0xCD`=0x08, Mute `0xE2`=0x10, Vol+ `0xE9`=0x40, Vol- `0xEA`=0x80
- b2: Media player `0x183`=0x01, My Computer `0x194`=0x02, Mail `0x18A`=0x10, Calculator `0x192`=0x20
- b3: WWW search `0x221`=0x01, Home `0x223`=0x02, Back `0x224`=0x04, Forward `0x225`=0x08, Stop `0x226`=0x10, Refresh `0x227`=0x20, Favourites `0x22A`=0x40

### Vendor default mapping (`[SENSOR_1] K1…K10`, same for all 3 modes) [cfg]

| Slot | Default | Entry |
|---|---|---|
| 1 | Left | `0xF011` |
| 2 | Right | `0xF112` |
| 3 | Middle | `0xF213` |
| 4 | Back | `0xF314` |
| 5 | Forward | `0xF415` |
| 6 | DPI+ | `0x2046` |
| 7 | DPI- | `0x4047` |
| 8 | Three click (`0x01,0x17`) | `0x0138` |
| 9 | Switch lighting effect (`0x08,0xAE`) | `0x0759` |
| 10 | Switch lighting effect (`0x08,0xAE`) | `0x075A` |

**Extra side button.** The vendor's per-button menu is built by the function at about `0x00428200`. The firmware takes
*any* entry in *any* slot. The "macro only" limit is in the vendor UI, not the firmware.
Mapping the button to a plain key is therefore the "key / key combination" entry with no modifiers:

- **F13** (HID `0x68`): `0x00680060 | slot`
- **Pause** (HID `0x48`): `0x00480060 | slot`

Which slot is the physical extra button has not been confirmed (slot 8 is the likely one). Use
"Identify buttons" in 3£ Mouse (Windows or Mac) to find out. The vendor's own key table (`0x005c6b10`) covers HID
`0x04…0x65` and `0x85`/`0x87`, so the firmware's keyboard range reaches past `0x68`. However, the
vendor never sends F13 itself. **If F13 doesn't arrive on the Mac, use Pause**, which the vendor
table does contain. **[inferred]**

### Macro buffer (128 bytes, `MacProtocol=2`) [code] `FUN_0040d050`

| Offset | Content |
|---|---|
| 0–1 | Repeat count, big-endian (`0x0001` when unset) |
| 2… | Events, then `00 00` |

Short event (delay ≤ 127 ms): `[flags | delay, key]`. A delay of 0 is written as 1.
Long event (delay > 127 ms): `[flags | (delay % 100), key, delay / 100, 0x03]`.
`flags` = `0x80` for **key press**, `0x00` for release **[inferred]**. The source sets `0x80` when
the event's "up" field is 0.
`key` = HID keyboard usage (modifiers as `0xE0…0xE7`). Mouse buttons are `0xF0` left, `0xF1`
right, `0xF2` middle. Maximum delay 25627 ms. Events stop 3 or 5 bytes short of 128.

## 6. Notify input report (5 bytes)

The vendor app reads it to see on-mouse DPI or mode changes. The configuration doesn't need it.
3£ ignores it.

## 7. Not supported / not sent

- No firmware update path exists in `OemDrv.exe`, and 3£ sends **only** reports 4, 6 and 8,
  the same as the vendor app.
- Profiles: the vendor keeps profiles **on the PC** (`pro.dct`). The mouse itself has 3 "key
  modes" (matrix rows) with their own polling rate. 3£ saves its profile as JSON in
  `%LOCALAPPDATA%\3EWindows\Mouse\profile.json` (Windows) or
  `~/Library/Application Support/3E Mouse/profile.json` (Mac).

## 8. Vendor window layout (used by the 3£ Mouse window)

The 3£ Mouse window on Windows and on Mac copies the vendor window's layout, so later changes can start from
the same design. Positions come from `OemDrv.exe` (skinned-button calls `FUN_0045a190`, panel classes) and
`Cfg.ini`. **[code]**/**[cfg]**

| Element | Position (window px) | Vendor images |
|---|---|---|
| Window | 1030×662, borderless | `main_nr.png` |
| Minimise / close | (940,21) / (965,21) | `min_*.png`, `exit_*.png` |
| Key list (8 keys) | panel (30,40)–(270,300); key *i* at (75, 50+31·*i*), 179×25 | `button2_nr/ov.png` |
| Mouse picture | (340,80), 280×440; numbered buttons at the digit centres measured on the picture (1 (91,78), 2 (183,78), 3 (138,108), 4 (50,176), 5 (55,230), 6 (163,169), 7 (163,203), **8 (46,132)**, i.e. the extra side button) | `mouse/mouse_nr.png` |
| Accordion: DPI, Lighting, Mouse Parameter, Polling Rate | headers at (743, 41+30·*i*), 245×25; the open panel sits below its header | `header_nr/ov/ov2.png` |
| Mode buttons | `ProfileGpY`=500 | `btn_nr/ov.png` |
| Driver buttons (Macro, Restore, Apply, …) | `DrvGpY`=570, 92×27 | `button3_nr/ov.png` |
| Function picker popup | 540×340 | `pickfundlg.png` |
| Macro editor | 767×418 (record button 128×30) | `macro_nr.png`, `recbtn_*.png` |

Text colours (Cfg.ini): normal 180,180,180; hover white; pressed 230,0,18; list background 39,39,39,
list selection 0,218,233; selected text 255,232,6; popup background 6,6,7 with frame 100,100,100.

3E is a public repo, so it doesn't contain the vendor's images. 3£ copies them from the user's own copy of the
vendor app, either found automatically (for example the vendor zip in `~/source/eduu`) or picked once with
Info → Import skin. Without them the window draws the same layout itself.

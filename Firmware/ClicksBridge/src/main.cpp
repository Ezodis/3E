// Clicks Power Keyboard bridge for the nice!nano (nRF52840).
//
// The Clicks keyboard pairs with this board (central role); the board pairs with up to
// five hosts plus an Apple Watch app (peripheral role) and forwards every key.
// The key logic (bridge.h) is hardware independent and covered by test/test_bridge.cpp.
//
//  - Windows host: keys pass through unchanged. The board reports the Clicks keyboard's
//    own Bluetooth PnP ID and a "Power Keyboard ..." name, so 3£ on Windows treats it as
//    the Clicks keyboard (Command/Ctrl mapping, sticky keys, accent picker, Mac layout).
//  - Apple host (Mac, iPhone, iPad): Command, Ctrl and Shift taps are sticky for one shared
//    7 s window (+3 s for a tap in its last 2 s); the six-dot key sends Cmd+Space (Spotlight).
//  - Watch: keys become text kept in a buffer the watch app reads and clears.
//
// Bridge commands: double-tap the six-dot key, then within 3 s press
//    1-5  use that host      9  use the watch      0  pair a new device on the current slot
//    W    current slot is Windows                   M  current slot is Apple
// sym and the mic key never leave the keyboard, so they behave exactly as before.

#include <bluefruit.h>
#include <InternalFileSystem.h>
#include "bridge.h"

using namespace Adafruit_LittleFS_Namespace;

static const char* CONFIG_PATH = "/bridge.cfg";
static const uint32_t PAIR_WINDOW_MS = 60000;
static const uint8_t CLICKS_PNP_ID[7] = {0x01, 0xD7, 0x07, 0x00, 0x00, 0x10, 0x01};  // as read from the keyboard

static BLEDis bledis;
static BLEHidAdafruit blehid;
static BLEClientHidAdafruit clicks;
static BLEService watchService{BLEUuid(WATCH_SERVICE_UUID)};
static BLECharacteristic watchText{BLEUuid(WATCH_TEXT_UUID)};
static BLECharacteristic watchClear{BLEUuid(WATCH_CLEAR_UUID)};

static QueueHandle_t reports;
static Config config;
static Bridge bridge;
static char watchBuffer[WATCH_BUFFER + 1];
static int8_t slotOfConn[BLE_MAX_CONNECTION];
static uint16_t clicksConn = BLE_CONN_HANDLE_INVALID;
static uint32_t pairUntil = 0;
static uint8_t lastSent[8];
static uint16_t lastSentConn = BLE_CONN_HANDLE_INVALID;

// ---------- persistence ----------
static void saveConfig() {
  InternalFS.remove(CONFIG_PATH);
  File f(InternalFS);
  if (f.open(CONFIG_PATH, FILE_O_WRITE)) { f.write((const uint8_t*)&config, sizeof(config)); f.close(); }
}
static void loadConfig() {
  File f(InternalFS);
  if (f.open(CONFIG_PATH, FILE_O_READ)) { f.read(&config, sizeof(config)); f.close(); }
  if (config.magic != CONFIG_MAGIC) { config = Config(); saveConfig(); }
}

// ---------- host side ----------
static uint16_t activeConn() {
  for (uint16_t h = 0; h < BLE_MAX_CONNECTION; h++)
    if (slotOfConn[h] == config.active && Bluefruit.connected(h)) return h;
  return BLE_CONN_HANDLE_INVALID;
}

static void sendToHost(const uint8_t report[8]) {
  uint16_t h = activeConn();
  if (h != lastSentConn) {
    if (lastSentConn != BLE_CONN_HANDLE_INVALID && Bluefruit.connected(lastSentConn)) {
      uint8_t none[6] = {0};
      blehid.keyboardReport(lastSentConn, 0, none);  // never leave keys held on the old host
    }
    memset(lastSent, 0, sizeof(lastSent));
    lastSentConn = h;
  }
  if (h == BLE_CONN_HANDLE_INVALID || memcmp(report, lastSent, 8) == 0) return;
  memcpy(lastSent, report, 8);
  uint8_t keys[6];
  memcpy(keys, report + 2, 6);
  blehid.keyboardReport(h, report[0], keys);
}

static void sendToWatch(const char* text, size_t len) {
  if (!len) return;
  // The value holds everything the watch app has not cleared yet (it reads it on connect);
  // each notification carries just the new text.
  size_t used = strnlen(watchBuffer, WATCH_BUFFER);
  if (used + len > WATCH_BUFFER) used = 0;  // full: start over with the newest text
  memcpy(watchBuffer + used, text, len);
  watchBuffer[used + len] = 0;
  watchText.write(watchBuffer, used + len);
  for (uint16_t h = 0; h < BLE_MAX_CONNECTION; h++)
    if (slotOfConn[h] == WATCH_SLOT && Bluefruit.connected(h)) watchText.notify(h, text, len);
}

static void onWatchClear(uint16_t, BLECharacteristic*, uint8_t*, uint16_t) {
  watchBuffer[0] = 0;
  watchText.write("", 0);
}

static void runCommand(const Command& c) {
  switch (c.kind) {
    case Command::Slot:
      config.active = c.value;
      saveConfig();
      break;
    case Command::Pair:
      config.names[config.active][0] = 0;  // the next new device takes this slot
      saveConfig();
      pairUntil = millis() + PAIR_WINDOW_MS;
      break;
    case Command::Os:
      if (config.active != WATCH_SLOT) { config.os[config.active] = c.value; saveConfig(); }
      break;
    default:
      break;
  }
}

static void periphSecured(uint16_t h) {
  BLEConnection* conn = Bluefruit.Connection(h);
  char name[NAME_LEN] = {0};
  conn->getPeerName(name, sizeof(name) - 1);
  int slot = -1;
  for (int s = 0; s < SLOTS; s++)
    if (config.names[s][0] && strncmp(config.names[s], name, NAME_LEN) == 0) slot = s;
  // A new device takes the current slot while pairing, or when that slot is still empty.
  bool canTake = !config.names[config.active][0] || (int32_t)(pairUntil - millis()) > 0;
  if (slot < 0 && canTake) {
    slot = config.active;
    strncpy(config.names[slot], name[0] ? name : "host", NAME_LEN - 1);
    pairUntil = 0;
    saveConfig();
  }
  if (slot < 0) {  // not one of ours and not pairing: refuse and forget it
    conn->removeBondKey();
    conn->disconnect();
    return;
  }
  slotOfConn[h] = slot;
}

static void periphDisconnected(uint16_t h, uint8_t) {
  slotOfConn[h] = -1;
  if (h == lastSentConn) lastSentConn = BLE_CONN_HANDLE_INVALID;
}

// ---------- keyboard side ----------
static void scanned(ble_gap_evt_adv_report_t* report) {
  uint8_t name[32] = {0};
  bool named = Bluefruit.Scanner.parseReportByType(report, BLE_GAP_AD_TYPE_COMPLETE_LOCAL_NAME, name, sizeof(name) - 1) ||
               Bluefruit.Scanner.parseReportByType(report, BLE_GAP_AD_TYPE_SHORT_LOCAL_NAME, name, sizeof(name) - 1);
  if (named && isClicksName((const char*)name)) Bluefruit.Central.connect(report);
  else Bluefruit.Scanner.resume();
}

static void centralConnected(uint16_t h) {
  BLEConnection* conn = Bluefruit.Connection(h);
  if (!clicks.discover(h)) { conn->disconnect(); return; }
  clicksConn = h;
  conn->requestPairing();
}

static void centralDisconnected(uint16_t h, uint8_t) {
  if (h == clicksConn) clicksConn = BLE_CONN_HANDLE_INVALID;
  hid_keyboard_report_t none = {};
  xQueueSend(reports, &none, 0);  // release anything still held on the host
}

static void secured(uint16_t h) {
  BLEConnection* conn = Bluefruit.Connection(h);
  if (conn->getRole() == BLE_GAP_ROLE_CENTRAL) {
    if (!conn->secured()) { conn->requestPairing(); return; }
    clicks.setBootMode(true);
    if (clicks.keyboardPresent()) clicks.enableKeyboard();
  } else {
    periphSecured(h);
  }
}

static void clicksReport(hid_keyboard_report_t* r) { xQueueSend(reports, r, 0); }

// ---------- setup/loop ----------
void setup() {
  for (auto& s : slotOfConn) s = -1;
  reports = xQueueCreate(32, sizeof(hid_keyboard_report_t));
  InternalFS.begin();
  loadConfig();

  Bluefruit.begin(4, 1);
  Bluefruit.autoConnLed(false);
  Bluefruit.setTxPower(4);
  Bluefruit.setName(BRIDGE_NAME);
  Bluefruit.Security.setSecuredCallback(secured);

  bledis.setManufacturer("Clicks Technology");
  bledis.setModel("CP-1000 bridge");
  bledis.setPNPID((const char*)CLICKS_PNP_ID, sizeof(CLICKS_PNP_ID));
  bledis.begin();
  blehid.begin();

  watchService.begin();
  watchText.setProperties(CHR_PROPS_READ | CHR_PROPS_NOTIFY);
  watchText.setPermission(SECMODE_ENC_NO_MITM, SECMODE_NO_ACCESS);
  watchText.setMaxLen(WATCH_BUFFER);
  watchText.begin();
  watchClear.setProperties(CHR_PROPS_WRITE);
  watchClear.setPermission(SECMODE_NO_ACCESS, SECMODE_ENC_NO_MITM);
  watchClear.setFixedLen(1);
  watchClear.setWriteCallback(onWatchClear);
  watchClear.begin();

  Bluefruit.Periph.setDisconnectCallback(periphDisconnected);
  Bluefruit.Advertising.addFlags(BLE_GAP_ADV_FLAGS_LE_ONLY_GENERAL_DISC_MODE);
  Bluefruit.Advertising.addTxPower();
  Bluefruit.Advertising.addAppearance(BLE_APPEARANCE_HID_KEYBOARD);
  Bluefruit.Advertising.addService(blehid);
  Bluefruit.ScanResponse.addName();
  Bluefruit.Advertising.restartOnDisconnect(true);
  Bluefruit.Advertising.setInterval(32, 244);
  Bluefruit.Advertising.setFastTimeout(30);
  Bluefruit.Advertising.start(0);

  clicks.begin();
  clicks.setKeyboardReportCallback(clicksReport);
  Bluefruit.Central.setConnectCallback(centralConnected);
  Bluefruit.Central.setDisconnectCallback(centralDisconnected);
  Bluefruit.Scanner.setRxCallback(scanned);
  Bluefruit.Scanner.restartOnDisconnect(true);
  Bluefruit.Scanner.setInterval(160, 80);
  Bluefruit.Scanner.filterService(clicks);
  Bluefruit.Scanner.useActiveScan(true);
  Bluefruit.Scanner.start(0);
}

void loop() {
  hid_keyboard_report_t r;
  while (xQueueReceive(reports, &r, 0) == pdTRUE) {
    uint8_t raw[8] = {r.modifier, 0, r.keycode[0], r.keycode[1], r.keycode[2], r.keycode[3], r.keycode[4], r.keycode[5]};
    Output out;
    bridge.process(raw, millis(), config, out);
    if (out.command.kind != Command::None) runCommand(out.command);
    if (out.hasReport) sendToHost(out.report);
    if (out.hasRelease) sendToHost(out.release);
    if (out.textLen) sendToWatch(out.text, out.textLen);
  }
  Output out;
  bridge.tick(millis(), config, out);
  if (out.hasReport) sendToHost(out.report);
  delay(2);
}

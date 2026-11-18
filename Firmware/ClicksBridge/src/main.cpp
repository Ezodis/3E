// Clicks Power Keyboard -> Apple Watch bridge for the nice!nano (nRF52840).
//
// The Clicks keyboard pairs with this board (central role). The board turns its keys into
// text and keeps it for one paired Apple Watch app (peripheral role, encrypted), which reads
// and clears it. Windows and Mac use the Clicks keyboard directly through the 3£ app; switch
// the keyboard to this board with its own Power + number.
// The key logic (bridge.h) is hardware independent and covered by test/test_bridge.cpp.
//
// Double-tap the six-dot key, then 0: forget the paired watch so a new one can pair.

#include <bluefruit.h>
#include <InternalFileSystem.h>
#include "bridge.h"

using namespace Adafruit_LittleFS_Namespace;

static const char* CONFIG_PATH = "/watch.cfg";

static BLEClientHidAdafruit clicks;
static BLEService watchService{BLEUuid(WATCH_SERVICE_UUID)};
static BLECharacteristic watchText{BLEUuid(WATCH_TEXT_UUID)};
static BLECharacteristic watchClear{BLEUuid(WATCH_CLEAR_UUID)};

static QueueHandle_t reports;
static Config config;
static Bridge bridge;
static char buffer[WATCH_BUFFER + 1];
static uint16_t watchConn = BLE_CONN_HANDLE_INVALID;

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

// ---------- watch side ----------
static void addText(const char* text, size_t len) {
  // The value holds everything the watch app has not cleared yet (it reads it on connect);
  // each notification carries just the new text.
  size_t used = strnlen(buffer, WATCH_BUFFER);
  if (used + len > WATCH_BUFFER) used = 0;  // full: start over with the newest text
  memcpy(buffer + used, text, len);
  buffer[used + len] = 0;
  watchText.write(buffer, used + len);
  if (watchConn != BLE_CONN_HANDLE_INVALID) watchText.notify(watchConn, text, len);
}

static void onClear(uint16_t, BLECharacteristic*, uint8_t*, uint16_t) {
  buffer[0] = 0;
  watchText.write("", 0);
}

static void watchSecured(uint16_t h) {
  BLEConnection* conn = Bluefruit.Connection(h);
  char name[NAME_LEN] = {0};
  conn->getPeerName(name, sizeof(name) - 1);
  if (!config.watch[0]) {  // first watch to pair is ours
    strncpy(config.watch, name[0] ? name : "watch", NAME_LEN - 1);
    saveConfig();
  }
  if (strncmp(config.watch, name[0] ? name : "watch", NAME_LEN) != 0) {
    conn->removeBondKey();
    conn->disconnect();
    return;
  }
  watchConn = h;
}

static void watchDisconnected(uint16_t h, uint8_t) {
  if (h == watchConn) watchConn = BLE_CONN_HANDLE_INVALID;
}

// ---------- keyboard side ----------
static void scanned(ble_gap_evt_adv_report_t* report) {
  uint8_t name[32] = {0};
  bool named = Bluefruit.Scanner.parseReportByType(report, BLE_GAP_AD_TYPE_COMPLETE_LOCAL_NAME, name, sizeof(name) - 1) ||
               Bluefruit.Scanner.parseReportByType(report, BLE_GAP_AD_TYPE_SHORT_LOCAL_NAME, name, sizeof(name) - 1);
  if (named && isClicksName((const char*)name)) Bluefruit.Central.connect(report);
  else Bluefruit.Scanner.resume();
}

static void keyboardConnected(uint16_t h) {
  BLEConnection* conn = Bluefruit.Connection(h);
  if (!clicks.discover(h)) { conn->disconnect(); return; }
  conn->requestPairing();
}

static void secured(uint16_t h) {
  BLEConnection* conn = Bluefruit.Connection(h);
  if (conn->getRole() == BLE_GAP_ROLE_CENTRAL) {
    if (!conn->secured()) { conn->requestPairing(); return; }
    clicks.setBootMode(true);
    if (clicks.keyboardPresent()) clicks.enableKeyboard();
  } else {
    watchSecured(h);
  }
}

static void clicksReport(hid_keyboard_report_t* r) { xQueueSend(reports, r, 0); }

void setup() {
  reports = xQueueCreate(32, sizeof(hid_keyboard_report_t));
  InternalFS.begin();
  loadConfig();

  Bluefruit.begin(1, 1);
  Bluefruit.autoConnLed(false);
  Bluefruit.setName(BRIDGE_NAME);
  Bluefruit.Security.setSecuredCallback(secured);

  watchService.begin();
  watchText.setProperties(CHR_PROPS_READ | CHR_PROPS_NOTIFY);
  watchText.setPermission(SECMODE_ENC_NO_MITM, SECMODE_NO_ACCESS);
  watchText.setMaxLen(WATCH_BUFFER);
  watchText.begin();
  watchClear.setProperties(CHR_PROPS_WRITE);
  watchClear.setPermission(SECMODE_NO_ACCESS, SECMODE_ENC_NO_MITM);
  watchClear.setFixedLen(1);
  watchClear.setWriteCallback(onClear);
  watchClear.begin();

  Bluefruit.Periph.setDisconnectCallback(watchDisconnected);
  Bluefruit.Advertising.addFlags(BLE_GAP_ADV_FLAGS_LE_ONLY_GENERAL_DISC_MODE);
  Bluefruit.Advertising.addService(watchService);
  Bluefruit.ScanResponse.addName();
  Bluefruit.Advertising.restartOnDisconnect(true);
  Bluefruit.Advertising.setInterval(32, 244);
  Bluefruit.Advertising.setFastTimeout(30);
  Bluefruit.Advertising.start(0);

  clicks.begin();
  clicks.setKeyboardReportCallback(clicksReport);
  Bluefruit.Central.setConnectCallback(keyboardConnected);
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
    bridge.process(raw, millis(), out);
    if (out.forgetWatch) {
      config.watch[0] = 0;
      saveConfig();
      if (watchConn != BLE_CONN_HANDLE_INVALID) Bluefruit.Connection(watchConn)->disconnect();
    }
    if (out.textLen) addText(out.text, out.textLen);
  }
  delay(2);
}

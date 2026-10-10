#include <BLEDevice.h>
#include <BLEAdvertising.h>
#include <esp_bt.h>

// ===================== CONFIGURE PER BEACON =====================

// 1, 2 or 3 (any value 1..65535). Must be unique per board.
#define BEACON_ID 1

// Shared by ALL beacons. Use the exact same string in the iOS app.
static const char *BEACON_UUID = "DFB76639-2B31-46CB-AAD1-63470563632E";

// Same for all beacons in one setup (e.g. room / venue number).
static const uint16_t BEACON_MAJOR = 1;

// RSSI (dBm) measured by an iPhone 1 m away from THIS beacon.
// iOS uses it to compute CLBeacon.accuracy. -59 is a typical starting
// value at +9 dBm; calibrate it (see bottom of file) for better distances.
static const int8_t MEASURED_POWER_1M = -59;

// Advertising interval in milliseconds (20..10240). Lower = more RSSI
// samples per second for the phone (smoother readings), more power draw.
static const uint16_t ADV_INTERVAL_MS = 100;

// =================================================================

static const uint16_t APPLE_COMPANY_ID = 0x004C;

// Parses "XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX" into 16 big-endian bytes.
static bool parseUuid(const char *str, uint8_t out[16]) {
  int n = 0;
  int hi = -1;
  for (const char *p = str; *p; ++p) {
    char c = *p;
    if (c == '-') continue;
    int v;
    if (c >= '0' && c <= '9') v = c - '0';
    else if (c >= 'a' && c <= 'f') v = c - 'a' + 10;
    else if (c >= 'A' && c <= 'F') v = c - 'A' + 10;
    else return false;
    if (hi < 0) {
      hi = v;
    } else {
      if (n >= 16) return false;
      out[n++] = (uint8_t)((hi << 4) | v);
      hi = -1;
    }
  }
  return n == 16 && hi < 0;
}

// Builds the 25-byte iBeacon manufacturer-specific payload
// (the BLE library adds the AD length + 0xFF type header).
static String buildIBeaconPayload(const uint8_t uuid[16], uint16_t major, uint16_t minor, int8_t measuredPower) {
  uint8_t p[25];
  p[0] = APPLE_COMPANY_ID & 0xFF;  // company id, little-endian
  p[1] = APPLE_COMPANY_ID >> 8;
  p[2] = 0x02;                     // iBeacon type
  p[3] = 0x15;                     // remaining length (21)
  memcpy(&p[4], uuid, 16);         // proximity UUID, big-endian
  p[20] = major >> 8;              // major, big-endian
  p[21] = major & 0xFF;
  p[22] = minor >> 8;              // minor, big-endian
  p[23] = minor & 0xFF;
  p[24] = (uint8_t)measuredPower;  // signed dBm @ 1 m
  return String(p, sizeof(p));
}

static void setMaxTxPower() {
  // +9 dBm is the highest level available on every ESP32 variant.
  // (ESP32-C3/S3/C6 support up to +20 dBm, but +9 dBm already saturates
  // phones at close range; more power mostly adds multipath reflections.)
  BLEDevice::setPower(ESP_PWR_LVL_P9, ESP_BLE_PWR_TYPE_ADV);
  BLEDevice::setPower(ESP_PWR_LVL_P9, ESP_BLE_PWR_TYPE_SCAN);
  BLEDevice::setPower(ESP_PWR_LVL_P9, ESP_BLE_PWR_TYPE_DEFAULT);
}

void setup() {
  Serial.begin(115200);
  delay(200);

  uint8_t uuid[16];
  if (!parseUuid(BEACON_UUID, uuid)) {
    Serial.println("ERROR: BEACON_UUID is not a valid UUID string. Halting.");
    while (true) delay(1000);
  }

  char name[16];
  snprintf(name, sizeof(name), "Beacon-%u", (unsigned)BEACON_ID);
  BLEDevice::init(name);
  setMaxTxPower();

  BLEAdvertisementData advData;
  advData.setFlags(0x06);  // LE General Discoverable | BR/EDR not supported
  advData.setManufacturerData(buildIBeaconPayload(uuid, BEACON_MAJOR, BEACON_ID, MEASURED_POWER_1M));

  BLEAdvertising *adv = BLEDevice::getAdvertising();
  adv->setAdvertisementData(advData);
  adv->setScanResponse(false);
#if defined(CONFIG_BLUEDROID_ENABLED)
  adv->setAdvertisementType(ADV_TYPE_NONCONN_IND);
#elif defined(CONFIG_NIMBLE_ENABLED)
  adv->setAdvertisementType(BLE_GAP_CONN_MODE_NON);
#endif

  // BLE intervals are in units of 0.625 ms.
  uint16_t units = (uint16_t)((ADV_INTERVAL_MS * 1000UL) / 625UL);
  adv->setMinInterval(units);
  adv->setMaxInterval(units);

  BLEDevice::startAdvertising();

  Serial.println();
  Serial.println("=== ESP32 iBeacon started ===");
  Serial.printf("UUID:           %s\n", BEACON_UUID);
  Serial.printf("Major / Minor:  %u / %u\n", (unsigned)BEACON_MAJOR, (unsigned)BEACON_ID);
  Serial.printf("Measured power: %d dBm @ 1 m\n", MEASURED_POWER_1M);
  Serial.printf("Interval:       %u ms\n", (unsigned)ADV_INTERVAL_MS);
  Serial.printf("TX power level: %d (enum)\n", BLEDevice::getPower(ESP_BLE_PWR_TYPE_ADV));
  Serial.printf("MAC address:    %s\n", BLEDevice::getAddress().toString().c_str());
}

void loop() {
  // Advertising runs entirely in the BLE controller; nothing to do here.
  // Heartbeat so you can confirm the board is alive on the serial monitor.
  static uint32_t last = 0;
  if (millis() - last >= 10000) {
    last = millis();
    Serial.printf("[beacon %u] advertising, uptime %lus\n", (unsigned)BEACON_ID, (unsigned long)(millis() / 1000));
  }
  delay(100);
}

/*
 * CALIBRATING MEASURED_POWER_1M (do this once per beacon, worth it):
 *   1. Put the iPhone exactly 1 m from the beacon, line of sight,
 *      beacon at the height it will be mounted.
 *   2. Log CLBeacon.rssi for ~30 s in your app (or use an app like "Beacon Scope").
 *   3. Average the values, round, and put the result here. Reflash.
 *
 * PLACEMENT TIPS FOR BETTER TRILATERATION:
 *   - Mount beacons high (~2 m), away from metal and walls' corners,
 *     spread out as a large triangle around the area (not in a line).
 *   - Keep the PCB antenna unobstructed; all beacons in the same orientation.
 *   - Power from USB / a stable 5 V supply (brownouts cause dropouts).
 *   - RSSI is noisy: in the app, smooth it (moving average or Kalman filter),
 *     convert with d = 10^((MEASURED_POWER_1M - rssi) / (10 * n)), n ~ 2.0-3.0
 *     indoors, then solve with least squares rather than exact circle intersection.
 */

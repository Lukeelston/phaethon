// Phaethon lever controller: Raspberry Pi Pico (RP2040), Arduino-Pico core, USB HID joystick.
//
// Axes:    X = left throttle (AS5600 on I2C0, GP4/GP5)   Y  = right throttle (AS5600 on I2C1, GP6/GP7)
//          Z = left brake (SS49E on GP26 / ADC0)          Rz = right brake (SS49E on GP27 / ADC1)
// Buttons: GP10..GP17, active low, internal pull-ups:
//          1 reignite (left thumb)  2 ramjet arm  3 repair  4 respawn
//          5 binder  6 left ignition  7 right ignition  8 shunt (right thumb)
// A sensor that is not fitted reports idle, so one lever (M3) and the full cockpit (M4) run the same build.
//
// Calibrate: levers at idle, brakes released, hold BOTH thumb buttons 3 s (LED blinks fast).
//            Sweep both levers to full and squeeze both brakes, then tap both thumbs again to save.
// Serial (115200): 'd' dumps raw values, 'j' measures throttle jitter at rest over 2 s.

#include <Wire.h>
#include <EEPROM.h>
#include <Joystick.h>

constexpr uint8_t AS5600_ADDR = 0x36;   // fixed address, hence one sensor per I2C bus
constexpr uint8_t REG_STATUS = 0x0B;    // bit5 MD magnet detected, bit4 ML too weak, bit3 MH too strong
constexpr uint8_t REG_RAW_ANGLE = 0x0C; // 12-bit, high nibble first
constexpr int BTN_PIN0 = 10, BTN_COUNT = 8;
constexpr int THUMB_L = 0, THUMB_R = 7;
constexpr int BRAKE_PIN[2] = {26, 27};
constexpr uint32_t CAL_MAGIC = 0x50484131;   // "PHA1"
constexpr int16_t DEFAULT_SPAN = 683;        // 60 degrees in AS5600 counts
constexpr int AXIS_MAX = 1023;

struct Cal {
  uint32_t magic;
  int16_t idle[2];   // raw angle at idle
  int16_t span[2];   // signed counts from idle to full
  int16_t brest[2];  // brake ADC at rest
  int16_t bfull[2];  // brake ADC fully squeezed
};

Cal cal;
TwoWire* bus[2] = {&Wire, &Wire1};
bool present[2] = {false, false};
int rawNow[2] = {0, 0};
int brakeNow[2] = {0, 0};
enum Mode { RUN, CAL_SWEEP } mode = RUN;
uint32_t thumbsSince = 0;

// Wrap a 12-bit angle difference into [-2048, 2047].
int wrap12(int v) {
  v %= 4096;
  if (v > 2047) v -= 4096;
  if (v < -2048) v += 4096;
  return v;
}

bool readReg(int i, uint8_t reg, uint8_t* buf, uint8_t n) {
  bus[i]->beginTransmission(AS5600_ADDR);
  bus[i]->write(reg);
  if (bus[i]->endTransmission(false) != 0) return false;
  if (bus[i]->requestFrom(AS5600_ADDR, n) != n) return false;
  for (uint8_t k = 0; k < n; k++) buf[k] = bus[i]->read();   // one read per statement: order is defined
  return true;
}

bool magnetOk(int i) {
  uint8_t st;
  return readReg(i, REG_STATUS, &st, 1) && (st & 0x20);
}

// Four samples, averaged after unwrapping against the first so a reading near 0/4095 can't smear.
bool readAngle(int i, int& out) {
  long acc = 0;
  int first = -1;
  for (int s = 0; s < 4; s++) {
    uint8_t b[2];
    if (!readReg(i, REG_RAW_ANGLE, b, 2)) return false;
    int v = ((b[0] & 0x0F) << 8) | b[1];
    if (first < 0) first = v;
    acc += first + wrap12(v - first);
  }
  out = (int)((acc / 4) & 0x0FFF);
  return true;
}

float throttleFrac(int i) {
  if (!present[i] || cal.span[i] == 0) return 0.0f;
  float f = (float)wrap12(rawNow[i] - cal.idle[i]) / (float)cal.span[i];
  return f < 0 ? 0 : (f > 1 ? 1 : f);
}

float brakeFrac(int i) {
  int d = cal.bfull[i] - cal.brest[i];
  if (abs(d) < 50) return 0.0f;   // uncalibrated or no sensor fitted
  float f = (float)(brakeNow[i] - cal.brest[i]) / (float)d;
  return f < 0 ? 0 : (f > 1 ? 1 : f);
}

bool pressed(int b) { return digitalRead(BTN_PIN0 + b) == LOW; }

void loadCal() {
  EEPROM.get(0, cal);
  if (cal.magic != CAL_MAGIC) {   // first boot: assume the levers are at idle right now
    cal.magic = CAL_MAGIC;
    for (int i = 0; i < 2; i++) {
      cal.idle[i] = rawNow[i];
      cal.span[i] = DEFAULT_SPAN;
      cal.brest[i] = cal.bfull[i] = brakeNow[i];
    }
  }
}

void saveCal() {
  EEPROM.put(0, cal);
  EEPROM.commit();
}

void sample() {
  for (int i = 0; i < 2; i++) {
    int v;
    present[i] = readAngle(i, v);
    if (present[i]) rawNow[i] = v;
    brakeNow[i] = analogRead(BRAKE_PIN[i]);
  }
}

void calibration() {
  bool both = pressed(THUMB_L) && pressed(THUMB_R);
  if (mode == RUN) {
    if (!both) { thumbsSince = 0; return; }
    if (thumbsSince == 0) thumbsSince = millis();
    if (millis() - thumbsSince < 3000) return;
    for (int i = 0; i < 2; i++) {   // capture idle and brake rest, then start tracking the sweep
      cal.idle[i] = rawNow[i];
      cal.span[i] = 0;
      cal.brest[i] = cal.bfull[i] = brakeNow[i];
    }
    mode = CAL_SWEEP;
    while (pressed(THUMB_L) || pressed(THUMB_R)) delay(10);   // wait for release
    return;
  }
  for (int i = 0; i < 2; i++) {     // CAL_SWEEP: keep the furthest excursion of each input
    int d = wrap12(rawNow[i] - cal.idle[i]);
    if (abs(d) > abs(cal.span[i])) cal.span[i] = d;
    if (abs(brakeNow[i] - cal.brest[i]) > abs(cal.bfull[i] - cal.brest[i])) cal.bfull[i] = brakeNow[i];
  }
  if (both) {
    for (int i = 0; i < 2; i++) if (abs(cal.span[i]) < 100) cal.span[i] = DEFAULT_SPAN;   // lever not swept
    saveCal();
    mode = RUN;
    thumbsSince = 0;
    while (pressed(THUMB_L) || pressed(THUMB_R)) delay(10);
  }
}

void serialCommands() {
  if (!Serial.available()) return;
  char c = Serial.read();
  if (c == 'd') {
    for (int i = 0; i < 2; i++) {
      Serial.printf("lever %d: present=%d magnet=%d raw=%d idle=%d span=%d frac=%.3f | brake raw=%d rest=%d full=%d frac=%.3f\n",
                    i, present[i], present[i] && magnetOk(i), rawNow[i], cal.idle[i], cal.span[i], throttleFrac(i),
                    brakeNow[i], cal.brest[i], cal.bfull[i], brakeFrac(i));
    }
  } else if (c == 'j') {   // M3 gate: jitter at rest must be <= +-2 counts
    int lo[2] = {9999, 9999}, hi[2] = {-9999, -9999};
    uint32_t t0 = millis();
    while (millis() - t0 < 2000) {
      sample();
      for (int i = 0; i < 2; i++) if (present[i]) {
        int d = wrap12(rawNow[i] - cal.idle[i]);
        lo[i] = min(lo[i], d); hi[i] = max(hi[i], d);
      }
      delay(1);
    }
    for (int i = 0; i < 2; i++) {
      if (!present[i]) { Serial.printf("lever %d: not fitted\n", i); continue; }
      int half = (hi[i] - lo[i] + 1) / 2;
      Serial.printf("lever %d: jitter %d..%d counts (+-%d) -> %s\n", i, lo[i], hi[i], half, half <= 2 ? "PASS" : "FAIL");
    }
  }
}

void setup() {
  Serial.begin(115200);
  pinMode(LED_BUILTIN, OUTPUT);
  for (int b = 0; b < BTN_COUNT; b++) pinMode(BTN_PIN0 + b, INPUT_PULLUP);
  analogReadResolution(12);
  Wire.setSDA(4);  Wire.setSCL(5);  Wire.begin();  Wire.setClock(400000);
  Wire1.setSDA(6); Wire1.setSCL(7); Wire1.begin(); Wire1.setClock(400000);
  EEPROM.begin(256);
  sample();
  loadCal();
  Joystick.begin();
  Joystick.useManualSend(true);
}

void loop() {
  sample();
  calibration();
  serialCommands();

  auto axis = [](float f) { return (int)(f * AXIS_MAX + 0.5f); };
  Joystick.X(axis(throttleFrac(0)));
  Joystick.Y(axis(throttleFrac(1)));
  Joystick.Z(axis(brakeFrac(0)));
  Joystick.Zrotate(axis(brakeFrac(1)));
  for (int b = 0; b < BTN_COUNT; b++) Joystick.button(b + 1, pressed(b));
  Joystick.send_now();

  // LED: fast blink while calibrating, slow blink if a fitted lever lost its magnet, solid when happy.
  uint32_t t = millis();
  bool magnetLost = (present[0] && !magnetOk(0)) || (present[1] && !magnetOk(1));
  digitalWrite(LED_BUILTIN, mode == CAL_SWEEP ? (t / 100) % 2 : magnetLost ? (t / 500) % 2 : 1);
  delay(1);
}

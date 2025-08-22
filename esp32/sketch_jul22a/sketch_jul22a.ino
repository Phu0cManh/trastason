#include <Wire.h>
#include <Adafruit_INA3221.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <cstring>

// ======================== OLED CONFIG ========================
#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
#define OLED_RESET    -1
Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);


// ======================== INA3221 CONFIG =====================
// INA3221 #1: ch1 = C1 (R003), ch2 = C2 (R005), ch3 = C3 (R005)
// INA3221 #2: ch1 = C4 (R010), ch2 = USB-A (R010), ch3 bỏ trống
Adafruit_INA3221 ina1; // C1, C2, C3
Adafruit_INA3221 ina2; // C4, USB-A

#define RSHUNT_C1     0.003f
#define RSHUNT_C2     0.005f
#define RSHUNT_C3     0.005f
#define RSHUNT_C4     0.010f
#define RSHUNT_USBA   0.010f

// Hệ số hiệu chỉnh theo từng cổng: C1, C2, C3, C4, USB-A
// Ví dụ: C2 đang đọc 1.5A nhưng thực 2.6A -> factor = 2.6/1.5 = 1.733f
float currentFactors[5] = {
  1.0f,    // C1
  1.0f,  // C2  <-- chỉnh theo case bạn nêu
  1.0f,    // C3
  1.0f,    // C4
  1.0f     // USB-A
};

// ======================== BLE CONFIG =========================
BLECharacteristic *pCharacteristic;
bool deviceConnected = false;
#define SERVICE_UUID        "12345678-1234-1234-1234-1234567890ab"
#define CHARACTERISTIC_UUID "abcd1234-abcd-1234-abcd-1234567890ab"

// ======================== HIỂN THỊ / LOGIC ====================
int displayMode = 0;
unsigned long lastSwitchTime = 0;
const unsigned long switchInterval = 3000; // 3 giây

float voltageArr[5], currentArr[5], powerArr[5];
const char* portLabels[5] = {"C1", "C2", "C3", "C4", "USB-A"};

//#define ENABLE_DEBUG  // bật để in debug shunt

// ======================== BLE CALLBACKS =======================
class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) override {
    deviceConnected = true;
  }
  void onDisconnect(BLEServer* pServer) override {
    deviceConnected = false;
    // Tự động quảng bá lại để thiết bị khác có thể kết nối
    pServer->getAdvertising()->start(); // <-- thêm dòng này
  }
};


// ======================== HÀM PHỤ TRỢ =========================
void setupINA3221()
{

  // INA3221 #1
  if (!ina1.begin(0x40)) {
    Serial.println("INA3221 #1 lỗi!");
    while (1) delay(10);
  }
  // INA3221 #2
  if (!ina2.begin(0x41)) {
    Serial.println("INA3221 #2 lỗi!");
    while (1) delay(10);
  }

  // INA3221 #1: ch1 = C1 (R003), ch2 = C2 (R005), ch3 = C3 (R005)
  ina1.setShuntResistance(1, RSHUNT_C1); // C1
  ina1.setShuntResistance(2, RSHUNT_C2); // C2
  ina1.setShuntResistance(3, RSHUNT_C3); // C3

  // INA3221 #2: ch1 = C4 (R010), ch2 = USB-A (R010), ch3 bỏ trống
  ina2.setShuntResistance(1, RSHUNT_C4);    // C4
  ina2.setShuntResistance(2, RSHUNT_USBA);  // USB-A
  // ch3 không dùng

  // Tuỳ chọn: averaging & conversion time để ổn định
  // (Bật nếu cần lọc nhiễu; cân đối tốc độ cập nhật)
  // ina1.setAveragingMode(INA3221_AVG_16_SAMPLES);
  // ina2.setAveragingMode(INA3221_AVG_16_SAMPLES);
  // ina1.setBusVoltageConversionTime(INA3221_VBUS_CONV_TIME_140US);
  // ina2.setBusVoltageConversionTime(INA3221_VBUS_CONV_TIME_140US);
  // ina1.setShuntVoltageConversionTime(INA3221_VSHUNT_CONV_TIME_140US);
  // ina2.setShuntVoltageConversionTime(INA3221_VSHUNT_CONV_TIME_140US);
}

void readAllPorts()
{

  // Mapping mới: INA1 ch1=C3, ch2=C2, ch3=C1; INA2 ch1=USB-A, ch2=C4
  // Hoán đổi dữ liệu: dữ liệu của C2 thành C1, dữ liệu của C3 thành C2
  voltageArr[0] = ina1.getBusVoltage(2); // C1 lấy từ ch2 INA1 (trước là C2)
  currentArr[0] = ina1.getCurrentAmps(2) * currentFactors[0];
  powerArr[0]   = voltageArr[0] * currentArr[0];

  voltageArr[1] = ina1.getBusVoltage(1); // C1 lấy từ ch1 INA1 (trước là C3, giờ thành C1 thứ 2)
  currentArr[1] = ina1.getCurrentAmps(1) * currentFactors[1];
  powerArr[1]   = voltageArr[1] * currentArr[1];

  voltageArr[2] = ina1.getBusVoltage(3); // C2 lấy từ ch3 INA1 (trước là C1, giờ thành C2)
  currentArr[2] = ina1.getCurrentAmps(3) * currentFactors[2];
  powerArr[2]   = voltageArr[2] * currentArr[2];

  voltageArr[3] = ina2.getBusVoltage(2); // C4 (ch2 INA2)
  currentArr[3] = ina2.getCurrentAmps(2) * currentFactors[3];
  powerArr[3]   = voltageArr[3] * currentArr[3];

  voltageArr[4] = ina2.getBusVoltage(3); // USB-A (ch3 INA2)
  currentArr[4] = ina2.getCurrentAmps(3) * currentFactors[4];
  powerArr[4]   = voltageArr[4] * currentArr[4];

  // Lọc NaN / giá trị nhỏ
  for (int i = 0; i < 5; i++) {
    if (isnan(voltageArr[i]) || voltageArr[i] < 0.1f) voltageArr[i] = 0.0f;
    if (isnan(currentArr[i])) currentArr[i] = 0.0f;
    if (isnan(powerArr[i]) || voltageArr[i] < 0.1f) powerArr[i] = 0.0f;
  }

#ifdef ENABLE_DEBUG
  // Ví dụ debug C2 (kênh 2 của INA1): soi shunt voltage và tính tay
  float vshunt_mV = ina1.getShuntVoltage(2) * 1000.0f;
  float icalc = (vshunt_mV / 1000.0f) / RSHUNT_OHMS;
  Serial.printf("[DBG] C2 Vshunt=%.2f mV, Icalc=%.3f A, Ifinal=%.3f A\n",
                vshunt_mV, icalc, currentArr[1]);
#endif
}

void sendAllPortsBLE()
{
  String bleData;
  bleData.reserve(128);
  for (int i = 0; i < 5; i++) {
    bleData += String(portLabels[i]) + ": ";
    bleData += String(voltageArr[i], 1) + "V, ";
    bleData += String(currentArr[i], 2) + "A, ";
    bleData += String(powerArr[i], 1) + "W\n";
  }
  if (deviceConnected) {
    pCharacteristic->setValue(bleData.c_str());
    pCharacteristic->notify();
  }
}

void drawPage_3cols() // C1, C2, C3
{
  display.setTextSize(2);
  for (int i = 0; i < 3; i++) {
    int colWidth = SCREEN_WIDTH / 3;
    int xBase = i * colWidth;
    int xLabel = xBase + (colWidth - (int)strlen(portLabels[i]) * 12) / 2;
    bool hasLoad = currentArr[i] > 0.05f;

    if (hasLoad) {
      display.fillRect(xLabel - 2, 0, strlen(portLabels[i]) * 12 + 4, 16, SSD1306_WHITE);
      display.setTextColor(SSD1306_BLACK);
    } else {
      display.setTextColor(SSD1306_WHITE);
    }
    display.setCursor(xLabel, 0);
    display.print(portLabels[i]);
  }

  display.setTextColor(SSD1306_WHITE);
  display.setTextSize(1);
  for (int i = 0; i < 3; i++) {
    int colWidth = SCREEN_WIDTH / 3;
    int xBase = i * colWidth;
    char vStr[10], aStr[10], wStr[10];
    snprintf(vStr, sizeof(vStr), "%.1fV", voltageArr[i]);
    snprintf(aStr, sizeof(aStr), "%.2fA", currentArr[i]);
    snprintf(wStr, sizeof(wStr), "%.1fW", powerArr[i]);
    display.setCursor(xBase + (colWidth - (int)strlen(vStr) * 6) / 2, 20);
    display.print(vStr);
    display.setCursor(xBase + (colWidth - (int)strlen(aStr) * 6) / 2, 32);
    display.print(aStr);
    display.setCursor(xBase + (colWidth - (int)strlen(wStr) * 6) / 2, 44);
    display.print(wStr);
  }
}

void drawPage_2cols() // C4, USB-A
{
  display.setTextSize(2);
  // Hiển thị đúng: cột trái là C4 (index 3), cột phải là USB-A (index 4)
  for (int idx = 0; idx < 2; idx++) {
    int colWidth = SCREEN_WIDTH / 2;
    int xBase = idx * colWidth;
    int arrIdx = idx + 3; // idx=0->3(C4), idx=1->4(USB-A)
    int xLabel = xBase + (colWidth - (int)strlen(portLabels[arrIdx]) * 12) / 2;
    bool hasLoad = currentArr[arrIdx] > 0.05f;

    if (hasLoad) {
      display.fillRect(xLabel - 2, 0, strlen(portLabels[arrIdx]) * 12 + 4, 16, SSD1306_WHITE);
      display.setTextColor(SSD1306_BLACK);
    } else {
      display.setTextColor(SSD1306_WHITE);
    }
    display.setCursor(xLabel, 0);
    display.print(portLabels[arrIdx]);
  }

  display.setTextColor(SSD1306_WHITE);
  display.setTextSize(1);
  for (int idx = 0; idx < 2; idx++) {
    int colWidth = SCREEN_WIDTH / 2;
    int xBase = idx * colWidth;
    int arrIdx = idx + 3;
    char vStr[10], aStr[10], wStr[10];
    snprintf(vStr, sizeof(vStr), "%.1fV", voltageArr[arrIdx]);
    snprintf(aStr, sizeof(aStr), "%.2fA", currentArr[arrIdx]);
    snprintf(wStr, sizeof(wStr), "%.1fW", powerArr[arrIdx]);
    display.setCursor(xBase + (colWidth - (int)strlen(vStr) * 6) / 2, 20);
    display.print(vStr);
    display.setCursor(xBase + (colWidth - (int)strlen(aStr) * 6) / 2, 32);
    display.print(aStr);
    display.setCursor(xBase + (colWidth - (int)strlen(wStr) * 6) / 2, 44);
    display.print(wStr);
  }
}

// ======================== SETUP / LOOP ========================
void setup() {
  Serial.begin(115200);
  Wire.begin();

  // OLED
  if (!display.begin(SSD1306_SWITCHCAPVCC, 0x3C)) {
    Serial.println("OLED lỗi!");
    while (1) delay(10);
  }
  display.clearDisplay();
  display.setTextColor(SSD1306_WHITE);

  // INA3221
  setupINA3221();

  // BLE
  BLEDevice::init("ESP32-PowerMonitor");
  BLEServer *pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService *pService = pServer->createService(SERVICE_UUID);
  pCharacteristic = pService->createCharacteristic(
                      CHARACTERISTIC_UUID,
                      BLECharacteristic::PROPERTY_READ |
                      BLECharacteristic::PROPERTY_NOTIFY
                    );
  pCharacteristic->addDescriptor(new BLE2902());
  pService->start();
  pServer->getAdvertising()->start();

  Serial.println("ESP32 sẵn sàng.");
}

void loop() {
  readAllPorts();
  sendAllPortsBLE();

  unsigned long currentMillis = millis();
  if (currentMillis - lastSwitchTime >= switchInterval) {
    displayMode = !displayMode;
    lastSwitchTime = currentMillis;
  }

  display.clearDisplay();
  if (displayMode == 0) {
    drawPage_3cols(); // C1, C2, C3
  } else {
    drawPage_2cols(); // C4, USB-A
  }
  display.display();

  delay(500);
}

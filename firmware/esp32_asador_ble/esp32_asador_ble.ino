/*
 * ============================================================================
 *  ASADOR · Firmware ESP32 — Bluetooth Clásico (SPP) + BLE en paralelo
 * ============================================================================
 *
 *  Objetivo: que el MISMO asador funcione con
 *    • la app Kodular original y la nueva app Android en modo "Clásico" (SPP), y
 *    • la nueva app en iPhone y Android en modo "BLE".
 *
 *  El protocolo es EXACTAMENTE el del APK original (1 carácter ASCII, sin '\n'):
 *     '4'..'8'  → nivel de velocidad (y arranque)
 *     '0'       → cambio de sentido
 *     '1'       → parada
 *
 *  ⚠ IMPORTANTE — este archivo NO conoce tu hardware.
 *  La parte de radio (SPP/BLE) está completa. La parte de motor
 *  (motorApply…) es un EJEMPLO para un driver PWM + pin de dirección
 *  (L298N, BTS7960, TB6612…). Sustitúyela por la lógica de tu sketch actual:
 *  basta con copiar lo que hoy hace tu `switch (c)` dentro de handleCommand().
 *
 *  Placa: ESP32 "clásico" (ESP32-WROOM/WROVER). Los ESP32-S3/C3/C6 NO tienen
 *  Bluetooth Clásico: en esos, pon ENABLE_SPP en 0 (solo BLE).
 *  Arduino IDE → Herramientas → Partition Scheme → "Huge APP (3MB No OTA)"
 *  (SPP + BLE juntos ocupan ~1,6 MB).
 *  Probado conceptualmente con arduino-esp32 2.x y 3.x (librería BLE incluida).
 * ============================================================================
 */

#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

#define ENABLE_SPP 1            // 1 = también Bluetooth Clásico (compatibilidad total)
#define STOP_ON_DISCONNECT 0    // 1 = parar el motor si se pierde la conexión (ver README)

#if ENABLE_SPP
#include "BluetoothSerial.h"
BluetoothSerial SerialBT;
#endif

// ---------------------------------------------------------------- Identidad
// La app busca nombres que contengan "ASADOR" (también "ESP32"/"KANKA").
static const char *DEVICE_NAME = "ASADOR-ESP32";

// Nordic UART Service (NUS) — debe coincidir con lib/core/constants/app_constants.dart
#define NUS_SERVICE_UUID "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define NUS_RX_UUID      "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"  // app → ESP32 (write)
#define NUS_TX_UUID      "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"  // ESP32 → app (notify)

// ---------------------------------------------------------------- Motor (EJEMPLO)
// ▼▼▼ AJUSTA A TU HARDWARE ▼▼▼
static const int PIN_PWM = 25;
static const int PIN_DIR = 26;
static const int PWM_FREQ = 20000;   // 20 kHz: silencioso
static const int PWM_BITS = 8;       // 0..255
// Duty por nivel 4..8 (índice 0..4). Ajusta según tu motor/reductora.
static const uint8_t DUTY_BY_LEVEL[5] = {90, 120, 150, 190, 230};
// ▲▲▲ AJUSTA A TU HARDWARE ▲▲▲

volatile bool motorRunning = false;
volatile bool motorClockwise = true;
volatile int  motorLevel = 6;

BLECharacteristic *txChar = nullptr;
volatile bool bleConnected = false;

// BLE llega desde la tarea de Bluedroid y SPP desde loop(): se serializa.
SemaphoreHandle_t cmdMutex = nullptr;

void motorInit() {
  pinMode(PIN_DIR, OUTPUT);
  digitalWrite(PIN_DIR, HIGH);
#if defined(ESP_ARDUINO_VERSION_MAJOR) && ESP_ARDUINO_VERSION_MAJOR >= 3
  ledcAttach(PIN_PWM, PWM_FREQ, PWM_BITS);
#else
  ledcSetup(0, PWM_FREQ, PWM_BITS);
  ledcAttachPin(PIN_PWM, 0);
#endif
}

void pwmWrite(uint8_t duty) {
#if defined(ESP_ARDUINO_VERSION_MAJOR) && ESP_ARDUINO_VERSION_MAJOR >= 3
  ledcWrite(PIN_PWM, duty);
#else
  ledcWrite(0, duty);
#endif
}

void motorApply() {
  digitalWrite(PIN_DIR, motorClockwise ? HIGH : LOW);
  pwmWrite(motorRunning ? DUTY_BY_LEVEL[motorLevel - 4] : 0);
}

// ---------------------------------------------------------------- Estado → app
// Opcional: la app actual lo ignora, pero queda listo para mostrar estado real.
// Formato: "S,<run 0/1>,<nivel>,<dir C/A>\n"
void notifyStatus() {
  char msg[24];
  snprintf(msg, sizeof(msg), "S,%d,%d,%c\n", motorRunning ? 1 : 0, motorLevel, motorClockwise ? 'C' : 'A');
  if (bleConnected && txChar) {
    txChar->setValue((uint8_t *)msg, strlen(msg));
    txChar->notify();
  }
}

// ---------------------------------------------------------------- Protocolo
// ÚNICO punto de entrada para ambos transportes.
void handleCommandLocked(char c);
void handleCommand(char c) {
  if (cmdMutex) xSemaphoreTake(cmdMutex, portMAX_DELAY);
  handleCommandLocked(c);
  if (cmdMutex) xSemaphoreGive(cmdMutex);
}

void handleCommandLocked(char c) {
  switch (c) {
    case '4': case '5': case '6': case '7': case '8':
      // Slider original: fija nivel y arranca.
      motorLevel = c - '0';
      motorRunning = true;
      break;
    case '0':
      // Flecha original: alterna el sentido.
      // (Si tu firmware actual hace otra cosa con '0', respétalo aquí.)
      motorClockwise = !motorClockwise;
      break;
    case '1':
      // Botón power original: parada.
      // (Si en tu firmware '1' era un toggle on/off, cámbialo aquí.)
      motorRunning = false;
      break;
    default:
      return;  // ignora '\r', '\n' y cualquier otro byte
  }
  motorApply();
  notifyStatus();
}

void onLinkLost() {
#if STOP_ON_DISCONNECT
  handleCommand('1');
#endif
}

// ---------------------------------------------------------------- BLE
class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *server) override {
    bleConnected = true;
  }
  void onDisconnect(BLEServer *server) override {
    bleConnected = false;
    onLinkLost();
    // Volver a anunciarse para permitir reconexión inmediata.
    BLEDevice::startAdvertising();
  }
};

class RxCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *ch) override {
    // String (core 3.x) o std::string (core 2.x): ambas tienen length() y [].
    auto value = ch->getValue();
    for (size_t i = 0; i < value.length(); i++) handleCommand((char)value[i]);
  }
};

void bleInit() {
  BLEDevice::init(DEVICE_NAME);
  BLEServer *server = BLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());

  BLEService *service = server->createService(NUS_SERVICE_UUID);

  BLECharacteristic *rx = service->createCharacteristic(
      NUS_RX_UUID, BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR);
  rx->setCallbacks(new RxCallbacks());

  txChar = service->createCharacteristic(NUS_TX_UUID, BLECharacteristic::PROPERTY_NOTIFY);
  txChar->addDescriptor(new BLE2902());

  service->start();

  BLEAdvertising *adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(NUS_SERVICE_UUID);
  adv->setScanResponse(true);  // el nombre va en la respuesta de escaneo
  BLEDevice::startAdvertising();
}

// ---------------------------------------------------------------- SPP
#if ENABLE_SPP
void sppCallback(esp_spp_cb_event_t event, esp_spp_cb_param_t *param) {
  if (event == ESP_SPP_CLOSE_EVT) onLinkLost();
}
#endif

void setup() {
  Serial.begin(115200);
  cmdMutex = xSemaphoreCreateMutex();
  motorInit();
  motorApply();

#if ENABLE_SPP
  SerialBT.register_callback(sppCallback);
  SerialBT.begin(DEVICE_NAME);  // mismo nombre para SPP
#endif
  bleInit();

  Serial.printf("[ASADOR] listo como \"%s\" (SPP=%d, BLE=1)\n", DEVICE_NAME, ENABLE_SPP);
}

void loop() {
#if ENABLE_SPP
  while (SerialBT.available()) handleCommand((char)SerialBT.read());
#endif
  // Depuración por USB: escribe 4..8 / 0 / 1 en el monitor serie.
  while (Serial.available()) handleCommand((char)Serial.read());
  delay(5);
}

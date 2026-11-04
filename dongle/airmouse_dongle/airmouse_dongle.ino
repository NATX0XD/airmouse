#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <USB.h>
#include <USBHIDMouse.h>
#include <USBHIDKeyboard.h>
#include "uuids.h"

USBHIDMouse mouse;
USBHIDKeyboard keyboard;
uint8_t buttons = 0;

static void releaseButtons() {
  if (buttons & 1) mouse.release(MOUSE_LEFT);
  if (buttons & 2) mouse.release(MOUSE_RIGHT);
  buttons = 0;
}

static void applyReport(const uint8_t *r) {
  const uint8_t next = r[0] & 3;
  if ((buttons ^ next) & 1) (next & 1) ? mouse.press(MOUSE_LEFT) : mouse.release(MOUSE_LEFT);
  if ((buttons ^ next) & 2) (next & 2) ? mouse.press(MOUSE_RIGHT) : mouse.release(MOUSE_RIGHT);
  buttons = next;
  mouse.move((int8_t)r[1], (int8_t)r[2], (int8_t)r[3]);
  if (r[4] == 1) keyboard.write(KEY_LEFT_ARROW);
  if (r[4] == 2) keyboard.write(KEY_RIGHT_ARROW);
}

class ServerCallbacks final : public BLEServerCallbacks {
  void onConnect(BLEServer *) override {}
  void onDisconnect(BLEServer *server) override {
    releaseButtons();
    server->startAdvertising();
  }
};

class ReportCallbacks final : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *characteristic) override {
    const String value = characteristic->getValue();
    if (value.length() == 0 || value.length() % 5 != 0) return;
    for (size_t i = 0; i < value.length(); i += 5) applyReport((const uint8_t *)value.c_str() + i);
  }
};

void setup() {
  Serial.begin(115200);
  mouse.begin();
  keyboard.begin();
  USB.begin();
  BLEDevice::init("AirMouse-Dongle");
  BLEServer *server = BLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());
  BLEService *service = server->createService(AIRMOUSE_SERVICE_UUID);
  BLECharacteristic *report = service->createCharacteristic(
    AIRMOUSE_REPORT_UUID, BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR);
  report->setCallbacks(new ReportCallbacks());
  service->start();
  server->getAdvertising()->addServiceUUID(AIRMOUSE_SERVICE_UUID);
  server->getAdvertising()->start();
}

void loop() { delay(20); }

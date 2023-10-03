#include <zip8.h>

#include <I2S.h>
#include <pio_i2s.pio.h>

#include <PicoDVI.h>

DVIGFX8 display(DVI_RES_400x240p60, true, adafruit_feather_dvi_cfg);

auto &outport = Serial;

extern "C" void zip8Log(const char *buf, size_t len) {
  outport.write(buf, len);
  outport.write('\n');
}

void *cpu = nullptr;

void panic(int rate) {
  pinMode(LED_BUILTIN, OUTPUT);
  while (true) {
    digitalWrite(LED_BUILTIN, HIGH);
    delay(rate);
    digitalWrite(LED_BUILTIN, LOW);
    delay(rate);
  }
}

bool led = true;

void setup() {
  outport.begin(115200);
  outport.println("init");
  pinMode(LED_BUILTIN, OUTPUT);
  pinMode(PIN_BUTTON, INPUT);
  if (!display.begin()) {
    outport.println("display alloc failed");
    panic(250);
  }

  const uint16_t palette[] = { 0x0000, 0xffff };
  memcpy(display.getPalette(), palette, sizeof(palette));
  display.swap(false, true);

  cpu = malloc(zip8CpuGetSize());
  if (!cpu) {
    outport.println("cpu alloc failed");
    panic(1000);
  }

unsigned char program[] = {
  0x62, 0x10, 0x63, 0x00, 0x61, 0x00, 0xa2, 0x42, 0xf1, 0x1e, 0xf0, 0x65,
  0xa2, 0x3a, 0xe0, 0xa1, 0xd2, 0x38, 0xf0, 0x29, 0x72, 0x02, 0x73, 0x01,
  0xd2, 0x35, 0x72, 0x06, 0x73, 0xff, 0x71, 0x01, 0x32, 0x30, 0x12, 0x28,
  0x62, 0x10, 0x73, 0x08, 0x31, 0x10, 0x12, 0x06, 0x6f, 0x01, 0xff, 0x15,
  0xff, 0x07, 0x3f, 0x00, 0x12, 0x30, 0x00, 0xe0, 0x12, 0x00, 0xff, 0xff,
  0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01, 0x02, 0x03, 0x0c, 0x04, 0x05,
  0x06, 0x0d, 0x07, 0x08, 0x09, 0x0e, 0x0a, 0x00, 0x0b, 0x0f
};
unsigned int program_len = 82;

  uint16_t err = 0;
  if (zip8CpuInit(&err, cpu, program, program_len, 0, 0)) {
    outport.print("cpu init error: ");
    outport.println(zip8GetErrorName(err));
    panic(2000);
  }

  Wire.begin();
}

void loop() {
  digitalWrite(LED_BUILTIN, led ? HIGH : LOW);
  led = !led;
  display.fillScreen(0);
  uint16_t err;

  uint8_t key_bytes[2];
  if (Wire.requestFrom(0x48, 2) != 2) {
    outport.print("got wrong number of bytes from i2c target");
    panic(1000);
  }

  key_bytes[0] = Wire.read();
  key_bytes[1] = Wire.read();

  uint16_t keys = key_bytes[0] | (((uint16_t) key_bytes[1]) << 8);

  zip8CpuSetKeys(cpu, keys);

  for (int i = 0; i < 300; i++) {
    if (zip8CpuCycle(&err, cpu)) {
      outport.print("cpu cycle error: ");
      outport.println(zip8GetErrorName(err));
      panic(100);
    }
  }
  zip8CpuTimerTick(cpu);
  for (int y = 0; y < 32; y++) {
    for (int x = 0; x < 64; x++) {
      uint8_t pixel = zip8CpuGetPixel(cpu, x, y);
      int screenX = 5 * x + 40;
      int screenY = 5 * y + 40;
      display.fillRect(screenX, screenY, 5, 5, pixel);
    }
  }
  display.swap();
}

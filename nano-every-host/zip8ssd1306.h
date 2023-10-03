#include <Adafruit_SSD1306.h>

class Zip8SSD1306 : Adafruit_SSD1306 {
public:
  Zip8SSD1306(SPIClass &spi, int8_t dc_pin, int8_t rst_pin, int8_t cs_pin, uint32_t bitrate = 8000000UL)
    : Adafruit_SSD1306(128, 64, &spi, dc_pin, rst_pin, cs_pin, bitrate) {}

  bool begin(uint8_t vcs = SSD1306_SWITCHCAPVCC, uint8_t addr = 0, bool reset = true,
             bool periphBegin = true);

  void display(void *cpu);
};
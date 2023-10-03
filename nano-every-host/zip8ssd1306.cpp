/*!
 * @file Adafruit_SSD1306.cpp
 *
 * @mainpage Arduino library for monochrome OLEDs based on SSD1306 drivers.
 *
 * @section intro_sec Introduction
 *
 * This is documentation for Adafruit's SSD1306 library for monochrome
 * OLED displays: http://www.adafruit.com/category/63_98
 *
 * These displays use I2C or SPI to communicate. I2C requires 2 pins
 * (SCL+SDA) and optionally a RESET pin. SPI requires 4 pins (MOSI, SCK,
 * select, data/command) and optionally a reset pin. Hardware SPI or
 * 'bitbang' software SPI are both supported.
 *
 * Adafruit invests time and resources providing this open source code,
 * please support Adafruit and open-source hardware by purchasing
 * products from Adafruit!
 *
 * @section dependencies Dependencies
 *
 * This library depends on <a
 * href="https://github.com/adafruit/Adafruit-GFX-Library"> Adafruit_GFX</a>
 * being present on your system. Please make sure you have installed the latest
 * version before using this library.
 *
 * @section author Author
 *
 * Written by Limor Fried/Ladyada for Adafruit Industries, with
 * contributions from the open source community.
 *
 * @section license License
 *
 * BSD license, all text above, and the splash screen included below,
 * must be included in any redistribution.
 *
 */

#include "zip8ssd1306.h"
#include <zip8.h>

#ifdef HAVE_PORTREG
#define SSD1306_SELECT *csPort &= ~csPinMask;        ///< Device select
#define SSD1306_DESELECT *csPort |= csPinMask;       ///< Device deselect
#define SSD1306_MODE_COMMAND *dcPort &= ~dcPinMask;  ///< Command mode
#define SSD1306_MODE_DATA *dcPort |= dcPinMask;      ///< Data mode
#else
#define SSD1306_SELECT digitalWrite(csPin, LOW);        ///< Device select
#define SSD1306_DESELECT digitalWrite(csPin, HIGH);     ///< Device deselect
#define SSD1306_MODE_COMMAND digitalWrite(dcPin, LOW);  ///< Command mode
#define SSD1306_MODE_DATA digitalWrite(dcPin, HIGH);    ///< Data mode
#endif

#if (ARDUINO >= 157) && !defined(ARDUINO_STM32_FEATHER)
#define SETWIRECLOCK wire->setClock(wireClk)     ///< Set before I2C transfer
#define RESWIRECLOCK wire->setClock(restoreClk)  ///< Restore after I2C xfer
#else                                            // setClock() is not present in older Arduino Wire lib (or WICED)
#define SETWIRECLOCK                             ///< Dummy stand-in define
#define RESWIRECLOCK                             ///< keeps compiler happy
#endif

#if defined(SPI_HAS_TRANSACTION)
#define SPI_TRANSACTION_START spi->beginTransaction(spiSettings)  ///< Pre-SPI
#define SPI_TRANSACTION_END spi->endTransaction()                 ///< Post-SPI
#else                                                             // SPI transactions likewise not present in older Arduino SPI lib
#define SPI_TRANSACTION_START                                     ///< Dummy stand-in define
#define SPI_TRANSACTION_END                                       ///< keeps compiler happy
#endif

// The definition of 'transaction' is broadened a bit in the context of
// this library -- referring not just to SPI transactions (if supported
// in the version of the SPI library being used), but also chip select
// (if SPI is being used, whether hardware or soft), and also to the
// beginning and end of I2C transfers (the Wire clock may be sped up before
// issuing data to the display, then restored to the default rate afterward
// so other I2C device types still work).  All of these are encapsulated
// in the TRANSACTION_* macros.

// Check first if Wire, then hardware SPI, then soft SPI:
#define TRANSACTION_START \
  SPI_TRANSACTION_START; \
  SSD1306_SELECT;
#define TRANSACTION_END \
  SSD1306_DESELECT; \
  SPI_TRANSACTION_END;

bool Zip8SSD1306::begin(uint8_t vcs, uint8_t addr, bool reset, bool periphBegin) {
  vccstate = vcs;
  pinMode(dcPin, OUTPUT);  // Set data/command pin as output
  pinMode(csPin, OUTPUT);  // Same for chip select
#ifdef HAVE_PORTREG
  dcPort = (PortReg *)portOutputRegister(digitalPinToPort(dcPin));
  dcPinMask = digitalPinToBitMask(dcPin);
  csPort = (PortReg *)portOutputRegister(digitalPinToPort(csPin));
  csPinMask = digitalPinToBitMask(csPin);
#endif
  SSD1306_DESELECT
  // SPI peripheral begin same as wire check above.
  if (periphBegin) {
    spi->begin();
  }

  // Reset SSD1306 if requested and reset pin specified in constructor
  if (reset && (rstPin >= 0)) {
    pinMode(rstPin, OUTPUT);
    digitalWrite(rstPin, HIGH);
    delay(1);                    // VDD goes high at start, pause for 1 ms
    digitalWrite(rstPin, LOW);   // Bring reset low
    delay(10);                   // Wait 10 ms
    digitalWrite(rstPin, HIGH);  // Bring out of reset
  }


  TRANSACTION_START

  // Init sequence
  static const uint8_t PROGMEM init1[] = { SSD1306_DISPLAYOFF,          // 0xAE
                                           SSD1306_SETDISPLAYCLOCKDIV,  // 0xD5
                                           0x80,                        // the suggested ratio 0x80
                                           SSD1306_SETMULTIPLEX };      // 0xA8
  ssd1306_commandList(init1, sizeof(init1));
  ssd1306_command1(HEIGHT - 1);

  static const uint8_t PROGMEM init2[] = { SSD1306_SETDISPLAYOFFSET,    // 0xD3
                                           0x0,                         // no offset
                                           SSD1306_SETSTARTLINE | 0x0,  // line #0
                                           SSD1306_CHARGEPUMP };        // 0x8D
  ssd1306_commandList(init2, sizeof(init2));

  ssd1306_command1((vccstate == SSD1306_EXTERNALVCC) ? 0x10 : 0x14);

  static const uint8_t PROGMEM init3[] = { SSD1306_MEMORYMODE,  // 0x20
                                           0x00,                // 0x0 act like ks0108
                                           SSD1306_SEGREMAP | 0x1,
                                           SSD1306_COMSCANDEC };
  ssd1306_commandList(init3, sizeof(init3));

  uint8_t comPins = 0x02;
  contrast = 0x8F;

  if ((WIDTH == 128) && (HEIGHT == 32)) {
    comPins = 0x02;
    contrast = 0x8F;
  } else if ((WIDTH == 128) && (HEIGHT == 64)) {
    comPins = 0x12;
    contrast = (vccstate == SSD1306_EXTERNALVCC) ? 0x9F : 0xCF;
  } else if ((WIDTH == 96) && (HEIGHT == 16)) {
    comPins = 0x2;  // ada x12
    contrast = (vccstate == SSD1306_EXTERNALVCC) ? 0x10 : 0xAF;
  } else {
    // Other screen varieties -- TBD
  }

  ssd1306_command1(SSD1306_SETCOMPINS);
  ssd1306_command1(comPins);
  ssd1306_command1(SSD1306_SETCONTRAST);
  ssd1306_command1(contrast);

  ssd1306_command1(SSD1306_SETPRECHARGE);  // 0xd9
  ssd1306_command1((vccstate == SSD1306_EXTERNALVCC) ? 0x22 : 0xF1);
  static const uint8_t PROGMEM init5[] = {
    SSD1306_SETVCOMDETECT,  // 0xDB
    0x40,
    SSD1306_DISPLAYALLON_RESUME,  // 0xA4
    SSD1306_NORMALDISPLAY,        // 0xA6
    SSD1306_DEACTIVATE_SCROLL,
    SSD1306_DISPLAYON
  };  // Main screen turn on
  ssd1306_commandList(init5, sizeof(init5));

  TRANSACTION_END

  return true;  // Success
}

void Zip8SSD1306::display(void *cpu) {
  TRANSACTION_START
  static const uint8_t PROGMEM dlist1[] = {
    SSD1306_PAGEADDR,
    0,     // Page start address
    0xFF,  // Page end (not really, but works here)
    SSD1306_COLUMNADDR, 0
  };  // Column start address
  ssd1306_commandList(dlist1, sizeof(dlist1));
  ssd1306_command1(WIDTH - 1);  // Column end address

#if defined(ESP8266)
  // ESP8266 needs a periodic yield() call to avoid watchdog reset.
  // With the limited size of SSD1306 displays, and the fast bitrate
  // being used (1 MHz or more), I think one yield() immediately before
  // a screen write and one immediately after should cover it.  But if
  // not, if this becomes a problem, yields() might be added in the
  // 32-byte transfer condition below.
  yield();
#endif
  uint16_t count = WIDTH * ((HEIGHT + 7) / 8);
  const uint8_t *ptr = zip8CpuGetDisplay(cpu);

  SSD1306_MODE_DATA

  for (uint8_t y = 0; y < 64 / 8; y++) {
    for (uint8_t x = 0; x < 128; x++) {
      uint8_t real_x = x / 2;
      uint8_t real_y = y * 8 / 2;
      uint16_t pixel_index = 32 * (uint16_t)real_x + real_y;
      uint8_t byte = ptr[pixel_index / 8];
      uint8_t nibble = (y % 2 == 0) ? byte : (byte >> 4);
      nibble = nibble & 0x0f;

      static uint8_t lookup[16] = {
        0b00000000,
        0b00000011,
        0b00001100,
        0b00001111,
        0b00110000,
        0b00110011,
        0b00111100,
        0b00111111,
        0b11000000,
        0b11000011,
        0b11001100,
        0b11001111,
        0b11110000,
        0b11110011,
        0b11111100,
        0b11111111,
      };

      spi->transfer(lookup[nibble]);
    }
  }

  TRANSACTION_END
#if defined(ESP8266)
  yield();
#endif
}
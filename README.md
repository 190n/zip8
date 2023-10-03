# ZIP-8

This is a [CHIP-8](https://en.wikipedia.org/wiki/CHIP-8) emulator written in Zig. It's designed to be portable through a minimal interface so that you can embed it on a variety of different platforms. Currently, there's a web wrapper which uses the code compiled to WebAssembly, and it also gets compiled to an Arduino library suitable for the RP2040 (or other Cortex-M0+ microcontrollers).

## Credits

The pony artwork in `pony.ch8` and `ponyhop.ch8` was done by Fayabella.

## Limitations

- Sound is not exposed via the C API.

## Demos

### WASM

A WebAssembly demo is [hosted on GitHub Pages](https://190n.github.io/zip8/), running a Flappy Bird game that I wrote for CHIP-8. This supports display, timer, and input, but no sound yet. You can try some of the other ROMs too or upload your own

Both demo ROMs were developed using [Octo](https://github.com/JohnEarnest/Octo), an excellent CHIP-8 implementation with a built-in high-level assembler, and you can view the assembly source code in the `.8o` files inside `web-host/public`.

### RP2040

I've also gotten this running on the Raspberry Pi RP2040 microcontroller, using an [Adafruit Feather RP2040 DVI](https://www.adafruit.com/product/5710), [Earle F Philhower III's Arduino core](https://github.com/earlephilhower/arduino-pico), and [Adafruit's fork of PicoDVI](https://github.com/adafruit/PicoDVI). This version scales the CHIP-8's display up to 640x320, with black bars surrounding to fill 800x480, at 60Hz with an RP2040 overclocked to 295MHz. Here is a video of that running:



### Nano Every

Finally, I've run this code on an Arduino Nano Every. This board uses the ATmega4809 microcontroller, which is a 20MHz 8-bit AVR chip with 6KiB RAM and 48KiB flash. I chose this because I thought the small memory would make running CHIP-8 possible but difficult (CHIP-8 itself has 4,096 bytes of memory, and the display, registers, and other state increases that to 4,472 bytes currently). Unfortunately I have not yet reduced the memory enough to run full CHIP-8 (I changed the memory size to 1,024 bytes), but I have improved performance significantly (the time for one frame went from roughly 230ms to 13ms) since the early iterations so that it now runs the same Flappy Bird demo as on the web version at full speed.

In addition to the Arduino, this version uses an SSD1306 128x64 monochrome OLED display connected over SPI (I²C is too slow). I modified [Adafruit's driver library](https://github.com/adafruit/Adafruit_SSD1306/) to avoid storing a separate 1,024-byte bitmap for the display contents; instead, I upscale the 64x32 representation stored by ZIP-8 on the fly. Below is a video of this setup in operation:

## Usage

### Compiling

The default `zig build` target builds a static library using the target and optimize mode from the command line (i.e. native and debug mode by default) in `zig-out/lib`. As in other Zig projects you can override them with `-Dtarget=<target>` and `-Doptimize=(Debug|ReleaseSafe|ReleaseFast|ReleaseSmall)`. You can also run the test suite with `zig build test`. The other things you can build all have preset targets, but the optimization option still applies:

- `zig build wasm`: generates a WebAssembly library, `zig-out/lib/zip8.wasm`. If ReleaseSmall mode is used (which I recommend) it uses wasm-opt from [binaryen](https://github.com/WebAssembly/binaryen), which you'll need to have installed.
- `zig build arduino`: generates a .ZIP library file at `zig-out/lib/zip8.zip` which you can use in the Arduino IDE. This is built for the Cortex-M0+ (RP2040 and other microcontrollers) and ATmega4809 architectures. This and the `atmega4809` targets support the option `-Duse_avr_gcc=(true|false)`, which if enabled uses Zig's C backend plus your installation of AVR GCC to compile the ATmega version instead of LLVM. This is necessary in Debug and ReleaseSafe modes to avoid a compiler crash, and may improve performance in other modes.
- `zig build atmega4809` and `zig build m0plus` build static libraries for the respective architectures in `zig-out/lib/<arch>/libzip8.a`.

All targets support `-Dmemory_size=<int>` to reduce the size of CHIP-8 memory (which is supposed to be 4,096 bytes) and `-Dcolumn_major_display=<bool>` to store the pixels of the display in a flat array in column-major order, instead of the default row-major. Currently, if `-Dcolumn_major_display=true` is used then the C API function `zip8CpuGetPixel` returns incorrect results (it assumes row-major).

In short, here are the build configurations I use regularly:

```sh
# For the web host
zig build wasm -Doptimize=ReleaseSmall

# For the RP2040 host
zig build arduino -Doptimize=ReleaseFast

# For the Nano Every host
# notes:
# 1. I am hoping to eliminate the need to reduce memory size
# 2. I have not benchmarked AVR GCC vs. LLVM
zig build arduino -Doptimize=ReleaseFast -Dmemory_size=1024 -Dcolumn_major_display=true -Duse_avr_gcc=true
```

### Calling from C code

The WASM and Arduino libraries expose the interface in `src/zip8.h`. WASM also includes these two functions, helpful for when you need to pass pointers in the WASM address space:

```c
// Allocate enough memory for the ZIP-8 CPU structure
void *zip8CpuAlloc(void);
// Allocate an arbitrary amount of memory
void *wasmAlloc(size_t size);
```

You should also provide the function (which must be `extern "C"` if you use C++):

```c
void zip8Log(const char *text, size_t length);
```

to send log output to a suitable place. `text` points to a null-terminated string, but the length is provided as well.

## Running the web host

- Compile the WebAssembly module:

```
zig build wasm -Doptimize=ReleaseSmall
```

- Switch to the web host's directory:

```
cd web-host
```

- Install Node.js dependencies:

```
npm install
```

- Launch the development server:

```
npm run dev
```

The last command prints a `localhost` URL where you can access the server. The page will hot reload if you edit the TypeScript source. If you edit the Zig code, you need to have Zig compile the module again.

## Structure

- `src`
	- `main.zig`: entrypoint; as the root file this is able to override Zig's `std.log` to go through the `zip8Log` callback.
	- `bindings.zig`: C ABI-compatible wrappers around most CPU functions.
	- `cpu.zig`: defines the structure representing a CPU, including registers, memory, and display.
	- `instruction.zig`: contains logic to decode an instruction and apply its effects to a CPU.
	- `zip8.h`: C API function declarations.
- `build.zig`: tells Zig how to compile everything and put together the Arduino library
- `library.properties`: configuration file telling the Arduino IDE how to use this library (this file gets bundled in the ZIP file)
- `web-host` contains a web application embedding the library:
	- `index.html` is the main page
	- `src/cpu.ts` is a JavaScript class wrapping a WebAssembly module running the ZIP-8 code
	- `src/main.ts` creates a CPU with a given ROM and handles input and drawing
	- `public` contains various ROMs (`.ch8` files) and in some cases their assembly source code (`.8o` files)

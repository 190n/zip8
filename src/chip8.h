#ifndef __CHIP8_H__
#define __CHIP8_H__

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

const char *chip8GetErrorName(uint16_t err);
size_t chip8GetCpuSize(void);
int chip8CpuInit(uint16_t *err, void *cpu, const uint8_t *program, size_t program_len, uint64_t seed);
int chip8CpuCycle(uint16_t *err, void *cpu);
void chip8CpuSetKeys(void *cpu, uint16_t keys);
bool chip8CpuIsWaitingForKey(const void *cpu);
void chip8CpuTimerTick(void *cpu);
bool chip8CpuDisplayIsDirty(const void *cpu);
void chip8CpuSetDisplayNotDirty(void *cpu);
const uint8_t *chip8CpuGetDisplay(const void *cpu);

static inline uint8_t chip8CpuGetPixel(const void *cpu, uint8_t x, uint8_t y) {
	return chip8CpuGetDisplay(cpu)[64 * (uint16_t)y + x];
}

#endif

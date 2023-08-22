#ifndef __CHIP8_H__
#define __CHIP8_H__

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

const char *zip8GetErrorName(uint16_t err);
size_t zip8CpuGetSize(void);
int zip8CpuInit(uint16_t *err, void *cpu, const uint8_t *program, size_t program_len, uint64_t seed);
int zip8CpuCycle(uint16_t *err, void *cpu);
void zip8CpuSetKeys(void *cpu, uint16_t keys);
bool zip8CpuIsWaitingForKey(const void *cpu);
void zip8CpuTimerTick(void *cpu);
bool zip8CpuDisplayIsDirty(const void *cpu);
void zip8CpuSetDisplayNotDirty(void *cpu);
const uint8_t *zip8CpuGetDisplay(const void *cpu);

static inline uint8_t zip8CpuGetPixel(const void *cpu, uint8_t x, uint8_t y) {
	return zip8CpuGetDisplay(cpu)[64 * (uint16_t)y + x];
}

#ifdef __cplusplus
}
#endif

#endif

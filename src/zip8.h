#ifndef __CHIP8_H__
#define __CHIP8_H__

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Error returned when an instruction is invalid
*/
extern const uint16_t ZIP8_ERR_ILLEGAL_OPCODE;

/**
 * Error returned when a call instruction overflows the stack (16 entries)
*/
extern const uint16_t ZIP8_ERR_STACK_OVERFLOW;

/**
 * Error returned when a return instruction is executed but the stack is empty
*/
extern const uint16_t ZIP8_ERR_BAD_RETURN;

/**
 * Error returned when the program supplied to zip8CpuInit does not fit in RAM
*/
extern const uint16_t ZIP8_ERR_PROGRAM_TOO_LONG;

/**
 * Error returned when the program tries to save or load more than 8 flag registers
*/
extern const uint16_t ZIP8_ERR_FLAG_OVERFLOW;

/**
 * Converts an error code into a null-terminated string
 *
 * err: an error code obtained via a ZIP-8 function's `err` parameter
*/
const char *zip8GetErrorName(uint16_t err);

/**
 * Returns the number of bytes that should be allocated for a ZIP-8 CPU
 */
size_t zip8CpuGetSize(void);

/**
 * Initializes a ZIP-8 CPU
 *
 * err:         location where an error code will be stored, if an error occurs
 * cpu:         opaque pointer to the CPU's data (should be allocated with the size from
 *              zip8CpuGetSize)
 * program:     code for the CPU to execute, copied into memory at address 0x200
 * program_len: how many bytes of the ROM should be copied into memory
 * seed:        seed for random number generation
 * flags:       initial value for the eight 8-bit flags used to store data between executions, in
 *              little-endian order
 *
 * Returns zero for success, nonzero (and stores a code in *err) for error
*/
int zip8CpuInit(uint16_t *err, void *cpu, const uint8_t *program, size_t program_len, uint64_t seed, uint64_t flags);

/**
 * Executes one instruction on a ZIP-8 CPU
 *
 * err: location for an error code
 * cpu: opaque pointer for CPU data
 *
 * Returns zero for success, nonzero (and stores a code in *err) for error
*/
int zip8CpuCycle(uint16_t *err, void *cpu);

/**
 * Sets which keys are pressed on a ZIP-8 CPU
 *
 * cpu:  opaque pointer for CPU data
 * keys: bitfield: least significant bit is key 0, most significant is key F, zero means released,
 *       one means pressed
*/
void zip8CpuSetKeys(void *cpu, uint16_t keys);

/**
 * Check whether a ZIP-8 CPU is blocked waiting for a key to be pressed
 *
 * cpu: opaque pointer for CPU data
*/
bool zip8CpuIsWaitingForKey(const void *cpu);

/**
 * Trigger a tick on a ZIP-8 CPU's 60Hz sound and delay timers
 *
 * cpu: opaque pointer for CPU data
*/
void zip8CpuTimerTick(void *cpu);

/**
 * Check whether a ZIP-8 CPU's display has changed since the last time the dirty flag was cleared
 *
 * cpu: opaque pointer for CPU data
*/
bool zip8CpuDisplayIsDirty(const void *cpu);

/**
 * Clear the dirty flag on a ZIP-8 CPU (to indicate that your application is displaying the most
 * recent contents)
 *
 * cpu: opaque pointer for CPU data
*/
void zip8CpuSetDisplayNotDirty(void *cpu);

/**
 * Access the display of a ZIP-8 CPU
 *
 * cpu: opaque pointer for CPU data
 *
 * Returns a flat array of bytes, one for each pixel. CHIP-8 has a 64x32 display so this array is
 * 256 bytes long (bit-packed). The order is from left to right then top to bottom. Pixels are
 * packed into each byte starting from the least significant bit.
*/
const uint8_t *zip8CpuGetDisplay(const void *cpu);

/**
 * Convenience function to access one pixel from a ZIP-8 CPU's display
 *
 * cpu: opaque pointer for CPU data
 * x:   X coordinate
 * y:   Y coordinate
 *
 * Returns zero or one.
*/
static inline uint8_t zip8CpuGetPixel(const void *cpu, uint8_t x, uint8_t y) {
	uint16_t index = 64 * (uint16_t) y + x;
	uint16_t byte_index = index / 8;
	uint16_t bit_index = index % 8;
	return (zip8CpuGetDisplay(cpu)[byte_index] >> bit_index) & 0x01;
}

/**
 * Get the instruction about to be executed by a ZIP-8 CPU
*/
uint16_t zip8CpuGetInstruction(const void *cpu);

/**
 * Get the program counter of a ZIP-8 CPU
*/
uint16_t zip8CpuGetProgramCounter(const void *cpu);

/**
 * Read the flag registers of a ZIP-8 CPU (eight 8-bit flags in big-endian order)
*/
uint64_t zip8CpuGetFlags(const void *cpu);

/**
 * Check whether a ZIP-8 CPU's flags have changed since the last time the dirty flag was cleared
 *
 * cpu: opaque pointer for CPU data
*/
bool zip8CpuFlagsAreDirty(const void *cpu);

/**
 * Clear the dirty flag on a ZIP-8 CPU (to indicate that your application has stored the most recent
 * flags)
 *
 * cpu: opaque pointer for CPU data
*/
void zip8CpuSetFlagsNotDirty(void *cpu);

#ifdef __cplusplus
}
#endif

#endif

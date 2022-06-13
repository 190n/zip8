const CPU = @This();

const std = @import("std");

const ops = @import("./opcodes.zig");

pub const memory_size = 4096;
pub const initial_pc = 0x200;
pub const stack_size = 16;

/// normal 8-bit registers V0-VF
V: [16]u8 = .{0} ** 16,
/// 12-bit register I for indexing memory
I: u12 = 0,
/// 4 KiB of memory
mem: [memory_size]u8 = .{0} ** memory_size,
/// program counter
pc: u12 = initial_pc,
/// call stack
stack: [stack_size]u12 = .{0} ** stack_size,
/// which index of the call stack will be used next
sp: std.math.IntFittingRange(0, stack_size - 1) = 0,

/// display is 64x32 stored row-major
display: [32][64]bool = .{.{false} ** 64} ** 32,
/// whether each key 0-F is pressed
keys: [16]bool = .{false} ** 16,

/// initialize a CPU and copy the program into memory
pub fn init(program: []const u8) error{ProgramTooLong}!CPU {
    var cpu = CPU{};
    if (program.len > (memory_size - initial_pc)) {
        return error.ProgramTooLong;
    }
    std.mem.copy(u8, cpu.mem[initial_pc..], program);
    return cpu;
}

pub fn cycle(self: *CPU) ops.ExecutionError!void {
    const opcode: u16 = (@as(u16, self.mem[self.pc]) << 8) | self.mem[self.pc + 1];
    const func = ops.msd_opcodes[(opcode & 0xf000) >> 12];
    if (try func(self, opcode)) |new_pc| {
        self.pc = new_pc;
    } else {
        self.pc += 2;
    }
}

test "CPU.init" {
    const cpu = try CPU.init("abc");
    try std.testing.expectEqualSlices(u8, &(.{0} ** 16), &cpu.V);
    try std.testing.expectEqual(@as(u12, 0), cpu.I);
    // should be the program then a bunch of zeros
    try std.testing.expectEqualSlices(u8, "abc" ++ ([_]u8{0} ** (memory_size - initial_pc - 3)), cpu.mem[initial_pc..]);
    try std.testing.expectEqual(@as(u12, initial_pc), cpu.pc);
    try std.testing.expectEqualSlices(u12, &(.{0} ** stack_size), &cpu.stack);
    try std.testing.expectEqual(@as(@TypeOf(cpu.sp), 0), cpu.sp);

    try std.testing.expectError(error.ProgramTooLong, CPU.init(&(.{0} ** (memory_size - initial_pc + 1))));
}

test "CPU.cycle with a basic proram" {
    const program = [_]u8{
        0x60, 0xC0, // V0 = 0xC0
        0x61, 0x53, // V1 = 0x53
        0x80, 0x14, // V0 += V1 (0x13 with carry)
        0x12, 0x06, // jump to 0x206 (infinite loop)
    };
    var cpu = try CPU.init(&program);
    try cpu.cycle();
    try std.testing.expectEqual(@as(u8, 0xC0), cpu.V[0]);
    try cpu.cycle();
    try std.testing.expectEqual(@as(u8, 0x53), cpu.V[1]);
}

const Cpu = @This();

const std = @import("std");

const Instruction = @import("./instruction.zig");

pub const memory_size = 4096;
pub const initial_pc = 0x200;
pub const stack_size = 16;
pub const display_width = 64;
pub const display_height = 32;
pub const font_base_address = 0x000;
pub const font_character_size = 5;

/// normal 8-bit registers V0-VF
V: [16]u8 = .{0} ** 16,
/// 12-bit register I for indexing memory
I: u12 = 0,
/// 4 KiB of memory
mem: [memory_size]u8 = .{0} ** memory_size,
/// program counter
pc: u12 = initial_pc,
/// call stack
stack: std.BoundedArray(u12, 16),
/// random number generator to use
rand: std.rand.Random,

/// display is 64x32 stored row-major
display: [display_height][display_width]bool = std.mem.zeroes([display_height][display_width]bool),
/// whether the contents of the screen have changed since the last time this flag was set to false
display_dirty: bool = false,

/// whether each key 0-F is pressed
keys: [16]bool = .{false} ** 16,

/// which register the next keypress should be stored in (only if a FX0A "wait for key" instruction
/// is waiting
next_key_register: ?u4 = null,

/// delay timer, counts down at 60Hz if nonzero
dt: u8 = 0,
/// sound timer, counts down to zero at 60Hz and sound is played if nonzero
st: u8 = 0,

/// initialize a CPU and copy the program into memory
pub fn init(program: []const u8, rand: std.rand.Random) error{ProgramTooLong}!Cpu {
    var cpu = Cpu{ .rand = rand, .stack = std.BoundedArray(u12, stack_size).init(0) catch unreachable };
    if (program.len > (memory_size - initial_pc)) {
        return error.ProgramTooLong;
    }
    std.mem.copy(u8, cpu.mem[initial_pc..], program);
    return cpu;
}

pub fn cycle(self: *Cpu) !void {
    const opcode: u16 = (@as(u16, self.mem[self.pc]) << 8) | self.mem[self.pc + 1];
    const inst = Instruction.decode(opcode);
    if (try inst.exec(self)) |new_pc| {
        self.pc = new_pc;
    } else {
        self.pc += 2;
    }
}

/// execute for N cycles, setting completed.* (if not null) to the number of cycles that actually
/// ran
pub fn cycleN(self: *Cpu, n: usize, completed: ?*usize) !void {
    var i: usize = 0;
    if (completed) |ptr| ptr.* = 0;
    while (i < n) : (i += 1) {
        try self.cycle();
        if (completed) |ptr| ptr.* += 1;
    }
}

/// decrement the delay and sound timers, if either is above zero. should be called 60 times per
/// second.
pub fn timerTick(self: *Cpu) void {
    if (self.dt > 0) self.dt -= 1;
    if (self.st > 0) self.st -= 1;
}

pub fn setKeys(self: *Cpu, new_keys: *const [16]bool) void {
    if (self.next_key_register) |reg| {
        for (new_keys, self.keys, 0..) |now_pressed, was_pressed, key| {
            if (now_pressed and !was_pressed) {
                self.V[reg] = @intCast(key);
            }
        }
        self.pc += 2;
    } else {
        @memcpy(&self.keys, new_keys);
    }
}

test "Cpu.init" {
    const cpu = try Cpu.init("abc", undefined);
    try std.testing.expectEqualSlices(u8, &(.{0} ** 16), &cpu.V);
    try std.testing.expectEqual(@as(u12, 0), cpu.I);
    // should be the program then a bunch of zeros
    try std.testing.expectEqualSlices(u8, "abc" ++ ([_]u8{0} ** (memory_size - initial_pc - 3)), cpu.mem[initial_pc..]);
    try std.testing.expectEqual(@as(u12, initial_pc), cpu.pc);
    try std.testing.expectEqual(@as(usize, 0), cpu.stack.len);

    for (cpu.display) |row| {
        for (row) |pixel| {
            try std.testing.expectEqual(false, pixel);
        }
    }

    try std.testing.expectEqualSlices(bool, &(.{false} ** 16), &cpu.keys);

    try std.testing.expectError(error.ProgramTooLong, Cpu.init(&(.{0} ** (memory_size - initial_pc + 1)), undefined));
}

test "Cpu.cycle with a basic program" {
    const program = [_]u8{
        0x60, 0xC0, // V0 = 0xC0
        0x61, 0x53, // V1 = 0x53
        0x80, 0x14, // V0 += V1 (0x13 with carry)
        0x12, 0x06, // jump to 0x206 (infinite loop)
    };
    var cpu = try Cpu.init(&program, undefined);
    try cpu.cycle();
    try std.testing.expectEqual(@as(u8, 0xC0), cpu.V[0x0]);
    try cpu.cycle();
    try std.testing.expectEqual(@as(u8, 0x53), cpu.V[0x1]);
    try cpu.cycle();
    // check that V0 has the right value and VF indicates overflow
    try std.testing.expectEqual(@as(u8, 0x13), cpu.V[0x0]);
    try std.testing.expectEqual(@as(u8, 0x01), cpu.V[0xF]);
    // check that we are now in a loop
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        try cpu.cycle();
        try std.testing.expectEqual(@as(u12, cpu.pc), 0x206);
    }
}

test "Cpu.cycleN" {
    var cpu = try Cpu.init(&[_]u8{
        // NOPs
        0x70, 0x00,
        0x70, 0x00,
        0x70, 0x00,
        0x70, 0x00,
        0x70, 0x00,
        // illegal
        0x00, 0x00,
    }, undefined);

    var completed: usize = 0;
    try cpu.cycleN(2, &completed);
    try std.testing.expectEqual(@as(usize, 2), completed);
    try cpu.cycleN(2, null);
    try std.testing.expectError(error.IllegalOpcode, cpu.cycleN(2, &completed));
    try std.testing.expectEqual(@as(usize, 1), completed);
}

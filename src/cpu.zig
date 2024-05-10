const Cpu = @This();

const std = @import("std");

const Instruction = @import("./instruction.zig");
const font_data = @import("./font.zig").font_data;

const build_options = @import("build_options");

pub const memory_size = build_options.memory_size orelse 4096;
pub const column_major_display = build_options.column_major_display;

comptime {
    if (memory_size > 4096) {
        @compileError("CHIP-8 memory may not be larger than 4096 bytes");
    }
}

pub const initial_pc = 0x200;
pub const stack_size = 16;
pub const display_width = 64;
pub const display_height = 32;
pub const font_base_address = 0x000;
pub const font_character_size = 5;

// downgrade errors in tests
const log = if (@import("builtin").is_test) struct {
    const base = std.log.scoped(.cpu);
    const err = info;
    const warn = info;
    const info = base.info;
    const debug = base.debug;
} else std.log.scoped(.cpu);

/// normal 8-bit registers V0-VF
V: [16]u8 = .{0} ** 16,
/// 12-bit register I for indexing memory
I: u12 = 0,
/// program counter
pc: u12 = initial_pc,
/// call stack
stack: std.BoundedArray(u12, 16),
/// random number generator to use
rand: std.rand.DefaultPrng,

/// 4 KiB of memory
mem: [memory_size]u8 = .{0x00} ** memory_size,
/// track which memory has not been synchronized to clients
mem_dirty: [memory_size / 8]u8 = .{0xff} ** (memory_size / 8),

draw_bytes_this_frame: usize = 0,

/// display is 64x32 stored row-major
display: [display_width * display_height / 8]u8 = .{0} ** (display_width * display_height / 8),
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

/// flags to store data between program runs
flags: [8]u8,
/// whether flags have changed since the host saved them
flags_dirty: bool = false,

pub fn initInPlace(cpu: *Cpu, program: []const u8, seed: u64, flags: [8]u8) error{ProgramTooLong}!void {
    cpu.* = Cpu{
        .rand = std.rand.DefaultPrng.init(seed),
        .stack = std.BoundedArray(u12, stack_size).init(0) catch unreachable,
        .flags = flags,
    };
    if (program.len > (memory_size - initial_pc)) {
        return error.ProgramTooLong;
    }
    @memcpy(cpu.mem[font_base_address..].ptr, font_data);
    @memcpy(cpu.mem[initial_pc..].ptr, program);
    log.info("cpu init", .{});
}

/// initialize a CPU and copy the program into memory
pub fn init(program: []const u8, seed: u64, flags: [8]u8) error{ProgramTooLong}!Cpu {
    var cpu: Cpu = undefined;
    try initInPlace(&cpu, program, seed, flags);
    return cpu;
}

pub fn cycle(self: *Cpu) !void {
    const hi: u8 = @as([*]u8, @ptrCast(&self.mem))[self.pc];
    const lo: u8 = @as([*]u8, @ptrCast(&self.mem))[self.pc + 1];
    const opcode: u16 = (@as(u16, hi) << 8) + lo;
    const inst = Instruction.decode(opcode);
    log.debug("{any}", .{inst});
    if (inst.exec(self) catch |e| {
        log.err("instruction 0x{x:0>4} at 0x{x:0>3}: {s}", .{ opcode, self.pc, @errorName(e) });
        return e;
    }) |new_pc| {
        self.pc = new_pc;
    } else {
        self.pc +%= 2;
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
    if (self.next_key_register) |reg| store_newly_pressed: {
        for (new_keys, self.keys, 0..) |now_pressed, was_pressed, key| {
            if (now_pressed and !was_pressed) {
                // store the key in the desired register
                self.V[reg] = @intCast(key);
                // advance to the next instruction (not waiting anymore)
                self.pc +%= 2;
                // indicate that we are not waiting anymore
                self.next_key_register = null;
                // exit the loop so we don't advance 2 instructions if 2 keys are pressed at once
                break :store_newly_pressed;
            }
        }
    }
    @memcpy(&self.keys, new_keys);
}

pub fn invertPixel(self: *Cpu, x: u8, y: u8) void {
    const pixel_index = if (column_major_display)
        display_height * @as(u16, x) + @as(u16, y)
    else
        display_width * @as(u16, y) + @as(u16, x);
    const byte_index = pixel_index / 8;
    const bit_index: u3 = @truncate(pixel_index);

    self.display[byte_index] ^= (@as(u8, 1) << bit_index);
}

pub fn getPixel(self: *const Cpu, x: u8, y: u8) u1 {
    const pixel_index = if (column_major_display)
        display_height * @as(u16, x) + @as(u16, y)
    else
        display_width * @as(u16, y) + @as(u16, x);
    const byte_index = pixel_index / 8;
    const bit_index: u3 = @truncate(pixel_index);

    return @truncate(@as([*]const u8, @ptrCast(&self.display))[byte_index] >> bit_index);
}

test "Cpu.init" {
    const cpu = try Cpu.init("abc", 0, .{0} ** 8);
    try std.testing.expectEqualSlices(u8, &(.{0} ** 16), &cpu.V);
    try std.testing.expectEqual(@as(u12, 0), cpu.I);
    // should be the program then a bunch of zeros
    try std.testing.expectEqualSlices(u8, "abc" ++ ([_]u8{0} ** (memory_size - initial_pc - 3)), cpu.mem[initial_pc..]);
    try std.testing.expectEqual(@as(u12, initial_pc), cpu.pc);
    try std.testing.expectEqual(@as(usize, 0), cpu.stack.len);

    for (0..cpu.display.len) |i| {
        try std.testing.expectEqual(@as(u8, 0), cpu.display[i]);
    }

    try std.testing.expectEqualSlices(bool, &(.{false} ** 16), &cpu.keys);

    try std.testing.expectError(
        error.ProgramTooLong,
        Cpu.init(&(.{0} ** (memory_size - initial_pc + 1)), 0, .{0} ** 8),
    );
}

test "Cpu.cycle with a basic program" {
    const program = [_]u8{
        0x60, 0xC0, // V0 = 0xC0
        0x61, 0x53, // V1 = 0x53
        0x80, 0x14, // V0 += V1 (0x13 with carry)
        0x12, 0x06, // jump to 0x206 (infinite loop)
    };
    var cpu = try Cpu.init(&program, 0, .{0} ** 8);
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
    }, 0, .{0} ** 8);

    var completed: usize = 0;
    try cpu.cycleN(2, &completed);
    try std.testing.expectEqual(@as(usize, 2), completed);
    try cpu.cycleN(2, null);
    try std.testing.expectError(error.IllegalOpcode, cpu.cycleN(2, &completed));
    try std.testing.expectEqual(@as(usize, 1), completed);
}

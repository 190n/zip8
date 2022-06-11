const CPU = @This();

const std = @import("std");

pub const memory_size = 4096;
pub const initial_pc = 0x200;

/// normal 8-bit registers V0-VF
V: [16]u8 = .{0} ** 16,
/// 12-bit register I for indexing memory
I: u12 = 0,
/// 4 KiB of memory
mem: [memory_size]u8 = .{0} ** memory_size,
/// program counter
pc: u12 = initial_pc,
/// call stack
stack: [16]u12 = .{0} ** 16,
/// which index of the call stack will be used next
sp: u4 = 0,

/// display is 64x32 stored row-major
display: [32][64]bool = .{.{false} ** 64} ** 32,
/// whether each key 0-F is pressed
keys: [16]bool = .{false} ** 16,

pub const ExecutionError = error{ IllegalOpcode };

/// a function that executes an instruction and optionally returns the new program counter
const OpcodeFn = fn (self: *CPU, opcode: u16) ExecutionError!?u12;

/// functions that delegate opcodes by the most significant hex digit
const msd_opcodes = [_]OpcodeFn{
    op00EX, // 0
    opJump, // 1
    opCall, // 2
    opSkipEq, // 3
    opSkipNe, // 4
    opSkipEqReg, // 5
    opSetReg, // 6
    opAddNoCarry, // 7
    opArithmetic, // 8
    opSkipNeReg, // 9
    opSetI, // A
    opJumpV0, // B
    opRandom, // C
    opDraw, // D
    opInput, // E
    opFXYZ, // F
};

/// initialize a CPU and copy the program into memory
pub fn init(program: []const u8) error{ProgramTooLong}!CPU {
    var cpu = CPU{};
    if (program.len > (memory_size - initial_pc)) {
        return error.ProgramTooLong;
    }
    std.mem.copy(u8, cpu.mem[initial_pc..], program);
    return cpu;
}

pub fn cycle(self: *CPU) ExecutionError!void {
    const opcode: u16 = (self.mem[self.pc] << 8) | self.mem[self.pc + 1];
    const func = msd_opcodes[(opcode & 0xf000) >> 12];
    if (try func(self, opcode)) |new_pc| {
        self.pc = new_pc;
    } else {
        self.pc += 2;
    }
}

/// 00E0: clear the screen
/// 00EE: return
fn op00EX(self: *CPU, opcode: u16) !?u12 {
    _ = self;
    _ = opcode;
    return null;
}

/// 1NNN: jump to NNN
fn opJump(self: *CPU, opcode: u16) !?u12 {
    _ = self;
    _ = opcode;
    return null;
}

/// 2NNN: call address NNN
fn opCall(self: *CPU, opcode: u16) !?u12 {
    _ = self;
    _ = opcode;
    return null;
}

/// 3XNN: skip next instruction if VX == NN
fn opSkipEq(self: *CPU, opcode: u16) !?u12 {
    _ = self;
    _ = opcode;
    return null;
}

/// 4XNN: skip next instruction if VX != NN
fn opSkipNe(self: *CPU, opcode: u16) !?u12 {
    _ = self;
    _ = opcode;
    return null;
}

/// 5XY0: skip next instruction if VX == VY
fn opSkipEqReg(self: *CPU, opcode: u16) !?u12 {
    _ = self;
    _ = opcode;
    return null;
}

/// 6XNN: set VX to NN
fn opSetReg(self: *CPU, opcode: u16) !?u12 {
    _ = self;
    _ = opcode;
    return null;
}

/// 7XNN: add NN to VX without carry
fn opAddNoCarry(self: *CPU, opcode: u16) !?u12 {
    _ = self;
    _ = opcode;
    return null;
}

/// dispatch an arithmetic instruction beginning with 8
fn opArithmetic(self: *CPU, opcode: u16) !?u12 {
    _ = self;
    _ = opcode;
    return null;
}

/// 9XY0: skip next instruction if VX != VY
fn opSkipNeReg(self: *CPU, opcode: u16) !?u12 {
    _ = self;
    _ = opcode;
    return null;
}

/// ANNN: set I to NNN
fn opSetI(self: *CPU, opcode: u16) !?u12 {
    _ = self;
    _ = opcode;
    return null;
}

/// BNNN: jump to NNN + V0
fn opJumpV0(self: *CPU, opcode: u16) !?u12 {
    _ = self;
    _ = opcode;
    return null;
}

/// CXNN: set VX to rand() & NN
fn opRandom(self: *CPU, opcode: u16) !?u12 {
    _ = self;
    _ = opcode;
    return null;
}

/// DXYN: draw an 8xN sprite from memory starting at I at (VX, VY)
fn opDraw(self: *CPU, opcode: u16) !?u12 {
    _ = self;
    _ = opcode;
    return null;
}

/// EX9E: skip next instruction if the key in VX is pressed
/// EXA1: skip next instruction if the key in VX is not pressed
fn opInput(self: *CPU, opcode: u16) !?u12 {
    _ = self;
    _ = opcode;
    return null;
}

/// dispatch an instruction beginning with F
fn opFXYZ(self: *CPU, opcode: u16) !?u12 {
    _ = self;
    _ = opcode;
    return null;
}

test "CPU.init" {
    const cpu = try CPU.init("abc");
    try std.testing.expectEqualSlices(u8, &(.{0} ** 16), &cpu.V);
    try std.testing.expectEqual(@as(u12, 0), cpu.I);
    try std.testing.expectEqualSlices(u8, "abc" ++ ([_]u8{0} ** (memory_size - initial_pc - 3)), cpu.mem[initial_pc..]);
    try std.testing.expectEqual(@as(u12, initial_pc), cpu.pc);
    try std.testing.expectEqualSlices(u12, &(.{0} ** 16), &cpu.stack);
    try std.testing.expectEqual(@as(u12, 0), cpu.sp);

    try std.testing.expectError(error.ProgramTooLong, CPU.init(&(.{0} ** (memory_size - initial_pc + 1))));
}

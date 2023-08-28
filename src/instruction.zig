const Instruction = @This();

const std = @import("std");

const Cpu = @import("./cpu.zig");

/// 4-bit elements of opcode, most significant first
nibbles: [4]u4,
/// lowest 8 bits
low8: u8,
/// lowest 12 bits, often a jump target or memory address
low12: u12,
/// highest 4 bits, indicates which class of opcode is used
high4: u4,
/// first register specified
regX: u4,
/// second register specified
regY: u4,
/// lowest 4 bits, used as disambiguation in some cases
low4: u4,
/// full opcode, if needed for any reason
opcode: u16,

const testing_seed = 1337;

/// split up an opcode into useful parts
pub fn decode(opcode: u16) Instruction {
    const nibbles = [4]u4{
        @as(u4, @truncate(opcode >> 12)),
        @as(u4, @truncate(opcode >> 8)),
        @as(u4, @truncate(opcode >> 4)),
        @as(u4, @truncate(opcode >> 0)),
    };
    return .{
        .nibbles = nibbles,
        .low8 = @as(u8, @truncate(opcode)),
        .low12 = @as(u12, @truncate(opcode)),
        .high4 = nibbles[0],
        .regX = nibbles[1],
        .regY = nibbles[2],
        .low4 = nibbles[3],
        .opcode = opcode,
    };
}

test "Instruction.decode" {
    const ins = Instruction.decode(0x1234);
    try std.testing.expectEqual([_]u4{ 0x1, 0x2, 0x3, 0x4 }, ins.nibbles);
    try std.testing.expectEqual(@as(u8, 0x34), ins.low8);
    try std.testing.expectEqual(@as(u12, 0x234), ins.low12);
    try std.testing.expectEqual(@as(u4, 0x1), ins.high4);
    try std.testing.expectEqual(@as(u4, 0x2), ins.regX);
    try std.testing.expectEqual(@as(u4, 0x3), ins.regY);
    try std.testing.expectEqual(@as(u4, 0x4), ins.low4);
    try std.testing.expectEqual(@as(u16, 0x1234), ins.opcode);
}

/// execute an instruction, returning the new program counter if execution should go somewhere other
/// than the next instruction
pub fn exec(self: Instruction, cpu: *Cpu) ExecutionError!?u12 {
    return msd_opcodes[self.high4](self, cpu);
}

pub const ExecutionError = error{
    IllegalOpcode,
    NotImplemented,
    StackOverflow,
    BadReturn,
    FlagOverflow,
};

/// a function that executes an instruction and optionally returns the new program counter
const OpcodeFn = *const fn (self: Instruction, cpu: *Cpu) ExecutionError!?u12;

/// functions that delegate opcodes by the most significant hex digit
const msd_opcodes = [16]OpcodeFn{
    op00EX, // 0
    opJump, // 1
    opCall, // 2
    opSkipEqImm, // 3
    opSkipNeImm, // 4
    opSkipEqReg, // 5
    opSetRegImm, // 6
    opAddImm, // 7
    opArithmetic, // 8
    opSkipNeReg, // 9
    opSetIImm, // A
    opJumpV0, // B
    opRandom, // C
    opDraw, // D
    opInput, // E
    opFXYZ, // F
};

/// does nothing and returns IllegalOpcode, for use in arrays of function pointers
fn opIllegal(self: Instruction, cpu: *const Cpu) !?u12 {
    _ = cpu;
    _ = self;
    return error.IllegalOpcode;
}

/// same as opIllegal, but conforms to function signature of arithmetic instructions
fn opIllegalArithmetic(vx: u8, vy: u8, vf: *const u8) !u8 {
    _ = vx;
    _ = vy;
    _ = vf;
    return error.IllegalOpcode;
}

/// 00E0: clear the screen
/// 00EE: return
fn op00EX(self: Instruction, cpu: *Cpu) !?u12 {
    switch (self.opcode) {
        0x00E0 => {
            @memset(&cpu.display, false);
            cpu.display_dirty = true;
            return null;
        },
        0x00EE => {
            if (cpu.stack.popOrNull()) |return_address| {
                return return_address;
            } else {
                return error.BadReturn;
            }
        },
        else => return error.IllegalOpcode,
    }
}

test "00E0 clear screen" {
    var cpu = try Cpu.init(&[_]u8{
        0x00, 0xE0,
    }, testing_seed, .{0} ** 8);
    // fill screen
    @memset(&cpu.display, true);
    try cpu.cycle();
    for (cpu.display) |pixel| {
        try std.testing.expectEqual(false, pixel);
    }
    try std.testing.expect(cpu.display_dirty);
}

test "00EE return" {
    var cpu = try Cpu.init(&[_]u8{
        0x00, 0xEE, // return to 0x206
        0x00, 0x00,
        0x00, 0x00,
        0x00, 0xEE, // return again but now the stack is empty
    }, testing_seed, .{0} ** 8);
    // set up somewhere to return to
    try cpu.stack.append(0x206);
    try cpu.cycle();
    // make sure it sent us to the right address and decremented the stack pointer
    try std.testing.expectEqual(@as(u12, 0x206), cpu.pc);
    try std.testing.expectEqual(@as(usize, 0), cpu.stack.len);
    // this should error as there's nothing on the stack anymore
    try std.testing.expectError(error.BadReturn, cpu.cycle());
}

/// 1NNN: jump to NNN
fn opJump(self: Instruction, cpu: *const Cpu) !?u12 {
    _ = cpu;
    return self.low12;
}

test "1NNN jump" {
    var cpu = try Cpu.init(&[_]u8{
        0x15, 0x62, // jump to 0x562
    }, testing_seed, .{0} ** 8);
    try cpu.cycle();
    try std.testing.expectEqual(@as(u12, 0x562), cpu.pc);
}

/// 2NNN: call address NNN
fn opCall(self: Instruction, cpu: *Cpu) !?u12 {
    const return_address = cpu.pc + 2;
    cpu.stack.append(return_address) catch return error.StackOverflow;
    return self.low12;
}

test "2NNN call" {
    // calls an instruction, then jumps back to the start (without returning)
    var cpu = try Cpu.init(&[_]u8{
        0x22, 0x08, // 0x200: call 0x208
        0x00, 0x00,
        0x00, 0x00,
        0x00, 0x00,
        0x12, 0x00, // 0x208: jump back to 0x200
    }, testing_seed, .{0} ** 8);

    // fill up the stack
    for (0..Cpu.stack_size) |i| {
        // execute call
        try cpu.cycle();
        try std.testing.expectEqual(@as(u12, 0x208), cpu.pc);
        try std.testing.expectEqual(i + 1, cpu.stack.len);
        try std.testing.expectEqual(@as(u12, 0x202), cpu.stack.get(i));
        // execute jump
        try cpu.cycle();
    }
    // now this one should fail
    try std.testing.expectError(error.StackOverflow, cpu.cycle());
}

/// calculate the new PC, using condition as whether the next instruction should be skipped
fn skipNextInstructionIf(cpu: *const Cpu, condition: bool) u12 {
    return cpu.pc +% @as(u12, if (condition) 4 else 2);
}

/// 3XNN: skip next instruction if VX == NN
fn opSkipEqImm(self: Instruction, cpu: *const Cpu) !?u12 {
    return skipNextInstructionIf(cpu, cpu.V[self.regX] == self.low8);
}

test "3XNN skip if VX == NN" {
    var cpu = try Cpu.init(&[_]u8{
        0x63, 0x58, // V3 = 0x58
        0x33, 0x58, // skip
        0x00, 0x00, // skipped
        0x33, 0x20, // won't skip
        0x32, 0x58, // won't skip
    }, testing_seed, .{0} ** 8);

    try cpu.cycle();
    try cpu.cycle();
    try std.testing.expectEqual(@as(u12, 0x206), cpu.pc);
    try cpu.cycle();
    try std.testing.expectEqual(@as(u12, 0x208), cpu.pc);
    try cpu.cycle();
    try std.testing.expectEqual(@as(u12, 0x20A), cpu.pc);
}

/// 4XNN: skip next instruction if VX != NN
fn opSkipNeImm(self: Instruction, cpu: *const Cpu) !?u12 {
    return skipNextInstructionIf(cpu, cpu.V[self.regX] != self.low8);
}

test "4XNN skip if VX != NN" {
    var cpu = try Cpu.init(&[_]u8{
        0x63, 0x58, // V3 = 0x58
        0x43, 0x20, // skip
        0x00, 0x00, // skipped
        0x43, 0x58, // won't skip
        0x42, 0x58, // skip
    }, testing_seed, .{0} ** 8);

    try cpu.cycle();
    try cpu.cycle();
    try std.testing.expectEqual(@as(u12, 0x206), cpu.pc);
    try cpu.cycle();
    try std.testing.expectEqual(@as(u12, 0x208), cpu.pc);
    try cpu.cycle();
    try std.testing.expectEqual(@as(u12, 0x20C), cpu.pc);
}

/// 5XY0: skip next instruction if VX == VY
fn opSkipEqReg(self: Instruction, cpu: *const Cpu) !?u12 {
    if (self.low4 != 0x0) {
        return error.IllegalOpcode;
    }
    return skipNextInstructionIf(cpu, cpu.V[self.regX] == cpu.V[self.regY]);
}

test "5XY0 skip if VX == VY" {
    var cpu = try Cpu.init(&[_]u8{
        0x60, 0x23, // V0 = 0x23
        0x61, 0x23, // V1 = 0x23
        0x50, 0x10, // skip
        0x00, 0x00, // skipped
        0x51, 0x00, // skip
        0x00, 0x00, // skipped
        0x50, 0x20, // won't skip
        0x50, 0x11, // error
    }, testing_seed, .{0} ** 8);
    // initialize registers
    try cpu.cycle();
    try cpu.cycle();
    // testing skips
    try cpu.cycle();
    try std.testing.expectEqual(@as(u12, 0x208), cpu.pc);
    try cpu.cycle();
    try std.testing.expectEqual(@as(u12, 0x20C), cpu.pc);
    try cpu.cycle();
    try std.testing.expectEqual(@as(u12, 0x20E), cpu.pc);
    try std.testing.expectError(error.IllegalOpcode, cpu.cycle());
}

/// 6XNN: set VX to NN
fn opSetRegImm(self: Instruction, cpu: *Cpu) !?u12 {
    cpu.V[self.regX] = self.low8;
    return null;
}

test "6XNN set VX to NN" {
    var cpu = try Cpu.init(&[_]u8{
        0x60, 0x2F,
        0x61, 0x68,
    }, testing_seed, .{0} ** 8);
    try cpu.cycle();
    try std.testing.expectEqual(@as(u8, 0x2F), cpu.V[0x0]);
    try cpu.cycle();
    try std.testing.expectEqual(@as(u8, 0x68), cpu.V[0x1]);
}

/// 7XNN: add NN to VX without carry
fn opAddImm(self: Instruction, cpu: *Cpu) !?u12 {
    cpu.V[self.regX] +%= self.low8;
    return null;
}

test "7XNN add NN to VX" {
    var cpu = try Cpu.init(&[_]u8{
        0x70, 0x53,
        0x70, 0xFF,
        0x71, 0x28,
    }, testing_seed, .{0} ** 8);
    // V0 = 0x53
    try cpu.cycle();
    try std.testing.expectEqual(@as(u8, 0x53), cpu.V[0x0]);
    // always make sure carry flag not set
    try std.testing.expectEqual(@as(u8, 0), cpu.V[0xF]);
    // add 0xFF = subtract 1
    try cpu.cycle();
    try std.testing.expectEqual(@as(u8, 0x52), cpu.V[0x0]);
    try std.testing.expectEqual(@as(u8, 0), cpu.V[0xF]);
    // V1 = 0x28
    try cpu.cycle();
    try std.testing.expectEqual(@as(u8, 0x28), cpu.V[0x1]);
    try std.testing.expectEqual(@as(u8, 0), cpu.V[0xF]);
}

/// dispatch an arithmetic instruction beginning with 8
fn opArithmetic(self: Instruction, cpu: *Cpu) !?u12 {
    // vx is set to the return value of this function
    const ArithmeticOpcodeFn = *const fn (vx: u8, vy: u8, vf: *u8) ExecutionError!u8;
    const arithmetic_opcodes = [_]ArithmeticOpcodeFn{
        opSetRegReg, // 8XY0
        opOr, // 8XY1
        opAnd, // 8XY2
        opXor, // 8XY3
        opAdd, // 8XY4
        opSub, // 8XY5
        opShiftRight, // 8XY6
        opSubRev, // 8XY7
        opIllegalArithmetic, // 8XY8 through 8XYD do not exist
        opIllegalArithmetic,
        opIllegalArithmetic,
        opIllegalArithmetic,
        opIllegalArithmetic,
        opIllegalArithmetic,
        opShiftLeft, // 8XYE
        opIllegalArithmetic, // 8XYF does not exist
    };

    const which_fn = arithmetic_opcodes[self.low4];
    const vx = &cpu.V[self.regX];
    const vy = &cpu.V[self.regY];
    vx.* = try which_fn(vx.*, vy.*, &cpu.V[0xF]);
    return null;
}

test "illegal arithmetic opcodes" {
    for ([_]u8{ 0x8, 0x9, 0xA, 0xB, 0xC, 0xD, 0xF }) |lsd| {
        var cpu = try Cpu.init(&[_]u8{
            0x80, 0x10 | lsd,
        }, testing_seed, .{0} ** 8);
        try std.testing.expectError(error.IllegalOpcode, cpu.cycle());
    }
}

/// 8XY0: set VX to VY
fn opSetRegReg(vx: u8, vy: u8, vf: *const u8) !u8 {
    _ = vx;
    _ = vf;
    return vy;
}

test "8XY0 set VX to VY" {
    var cpu = try Cpu.init(&[_]u8{
        0x60, 0x38,
        0x81, 0x00,
        0x80, 0x20,
    }, testing_seed, .{0} ** 8);
    try cpu.cycle();
    try cpu.cycle();
    try std.testing.expectEqual(@as(u8, 0x38), cpu.V[0x1]);
    try std.testing.expectEqual(@as(u8, 0x38), cpu.V[0x0]);
    try cpu.cycle();
    try std.testing.expectEqual(@as(u8, 0x00), cpu.V[0x0]);
}

/// 8XY1: set VX to VX | VY
fn opOr(vx: u8, vy: u8, vf: *const u8) !u8 {
    _ = vf;
    return vx | vy;
}

test "8XY1 bitwise OR" {
    var cpu = try Cpu.init(&[_]u8{
        0x60, 0x55,
        0x61, 0x33,
        0x80, 0x11,
    }, testing_seed, .{0} ** 8);
    try cpu.cycleN(3, null);
    try std.testing.expectEqual(@as(u8, 0x77), cpu.V[0x0]);
    try std.testing.expectEqual(@as(u8, 0x33), cpu.V[0x1]);
}

/// 8XY2: set VX to VX & VY
fn opAnd(vx: u8, vy: u8, vf: *const u8) !u8 {
    _ = vf;
    return vx & vy;
}

test "8XY2 bitwise AND" {
    var cpu = try Cpu.init(&[_]u8{
        0x60, 0x55,
        0x61, 0x33,
        0x80, 0x12,
    }, testing_seed, .{0} ** 8);
    try cpu.cycleN(3, null);
    try std.testing.expectEqual(@as(u8, 0x11), cpu.V[0x0]);
    try std.testing.expectEqual(@as(u8, 0x33), cpu.V[0x1]);
}

/// 8XY3: set VX to VX ^ VY
fn opXor(vx: u8, vy: u8, vf: *const u8) !u8 {
    _ = vf;
    return vx ^ vy;
}

test "8XY3 bitwise XOR" {
    var cpu = try Cpu.init(&[_]u8{
        0x60, 0x55,
        0x61, 0x33,
        0x80, 0x13,
    }, testing_seed, .{0} ** 8);
    try cpu.cycleN(3, null);
    try std.testing.expectEqual(@as(u8, 0x66), cpu.V[0x0]);
    try std.testing.expectEqual(@as(u8, 0x33), cpu.V[0x1]);
}

/// 8XY4: set VX to VX + VY; set VF to 1 if carry occurred, 0 otherwise
fn opAdd(vx: u8, vy: u8, vf: *u8) !u8 {
    const result = @addWithOverflow(vx, vy);
    vf.* = result[1];
    return result[0];
}

test "8XY4 add registers" {
    var cpu = try Cpu.init(&[_]u8{
        0x60, 66,
        0x61, 228,
        0x80, 0x14,
        0x61, 26,
        0x80, 0x14,
    }, testing_seed, .{0} ** 8);
    try cpu.cycleN(3, null);
    try std.testing.expectEqual(@as(u8, @truncate(294)), cpu.V[0x0]);
    try std.testing.expectEqual(@as(u8, 1), cpu.V[0xF]);
    try cpu.cycleN(2, null);
    try std.testing.expectEqual(@as(u8, 64), cpu.V[0x0]);
    try std.testing.expectEqual(@as(u8, 0), cpu.V[0xF]);
}

/// 8XY5: set VX to VX - VY; set VF to 0 if borrow occurred, 1 otherwise
fn opSub(vx: u8, vy: u8, vf: *u8) !u8 {
    const result = @subWithOverflow(vx, vy);
    vf.* = 1 - result[1];
    return result[0];
}

test "8XY5 subtract registers" {
    var cpu = try Cpu.init(&[_]u8{
        0x60, 107,
        0x61, 25,
        0x80, 0x15,
        0x60, 13,
        0x61, 59,
        0x80, 0x15,
    }, testing_seed, .{0} ** 8);
    try cpu.cycleN(3, null);
    try std.testing.expectEqual(@as(u8, 107 - 25), cpu.V[0x0]);
    try std.testing.expectEqual(@as(u8, 1), cpu.V[0xF]);
    try cpu.cycleN(3, null);
    try std.testing.expectEqual(@as(u8, @bitCast(@as(i8, @truncate(13 - 59)))), cpu.V[0x0]);
    try std.testing.expectEqual(@as(u8, 0), cpu.V[0xF]);
}

/// 8XY6: set VX to VY >> 1, set VF to the former least significant bit of VY
fn opShiftRight(vx: u8, vy: u8, vf: *u8) !u8 {
    _ = vx;
    vf.* = vy & 0x01;
    return vy >> 1;
}

test "8XY6 shift right" {
    var cpu = try Cpu.init(&[_]u8{
        0x61, 0b01011001,
        0x80, 0x16,
        0x80, 0x06,
    }, testing_seed, .{0} ** 8);
    try cpu.cycle();
    try cpu.cycle();
    try std.testing.expectEqual(@as(u8, 0b00101100), cpu.V[0x0]);
    try std.testing.expectEqual(@as(u8, 1), cpu.V[0xF]);
    try cpu.cycle();
    try std.testing.expectEqual(@as(u8, 0b00010110), cpu.V[0x0]);
    try std.testing.expectEqual(@as(u8, 0), cpu.V[0xF]);
}

/// 8XY7: set VX to VY - VX; set VF to 0 if borrow occurred, 1 otherwise
fn opSubRev(vx: u8, vy: u8, vf: *u8) !u8 {
    const result = @subWithOverflow(vy, vx);
    vf.* = 1 - result[1];
    return result[0];
}

test "8XY7 subtract registers in reverse" {
    var cpu = try Cpu.init(&[_]u8{
        0x60, 25,
        0x61, 107,
        0x80, 0x17,
        0x60, 59,
        0x61, 13,
        0x80, 0x17,
    }, testing_seed, .{0} ** 8);
    try cpu.cycleN(3, null);
    try std.testing.expectEqual(@as(u8, 107 - 25), cpu.V[0x0]);
    try std.testing.expectEqual(@as(u8, 1), cpu.V[0xF]);
    try cpu.cycleN(3, null);
    try std.testing.expectEqual(@as(u8, @bitCast(@as(i8, @truncate(13 - 59)))), cpu.V[0x0]);
    try std.testing.expectEqual(@as(u8, 0), cpu.V[0xF]);
}

/// 8XYE: set VX to VY << 1, set VF to the former most significant bit of VY
fn opShiftLeft(vx: u8, vy: u8, vf: *u8) !u8 {
    _ = vx;
    vf.* = vy >> 7;
    return vy << 1;
}

test "8XYE shift left" {
    var cpu = try Cpu.init(&[_]u8{
        0x61, 0b10010110,
        0x80, 0x1E,
        0x80, 0x0E,
    }, testing_seed, .{0} ** 8);
    try cpu.cycle();
    try cpu.cycle();
    try std.testing.expectEqual(@as(u8, 0b00101100), cpu.V[0x0]);
    try std.testing.expectEqual(@as(u8, 1), cpu.V[0xF]);
    try cpu.cycle();
    try std.testing.expectEqual(@as(u8, 0b01011000), cpu.V[0x0]);
    try std.testing.expectEqual(@as(u8, 0), cpu.V[0xF]);
}

/// 9XY0: skip next instruction if VX != VY
fn opSkipNeReg(self: Instruction, cpu: *const Cpu) !?u12 {
    if (self.low4 != 0x0) {
        return error.IllegalOpcode;
    }
    return skipNextInstructionIf(cpu, cpu.V[self.regX] != cpu.V[self.regY]);
}

test "9XY0 skip if VX != VY" {
    var cpu = try Cpu.init(&[_]u8{
        0x60, 0x23, // V0 = 0x23
        0x61, 0xB2, // V1 = 0xB2
        0x90, 0x10, // skip
        0x00, 0x00, // skipped
        0x91, 0x00, // skip
        0x00, 0x00, // skipped
        0x93, 0x20, // won't skip
        0x90, 0x11, // error
    }, testing_seed, .{0} ** 8);
    // initialize registers
    try cpu.cycle();
    try cpu.cycle();
    // testing skips
    try cpu.cycle();
    try std.testing.expectEqual(@as(u12, 0x208), cpu.pc);
    try cpu.cycle();
    try std.testing.expectEqual(@as(u12, 0x20C), cpu.pc);
    try cpu.cycle();
    try std.testing.expectEqual(@as(u12, 0x20E), cpu.pc);
    try std.testing.expectError(error.IllegalOpcode, cpu.cycle());
}

/// ANNN: set I to NNN
fn opSetIImm(self: Instruction, cpu: *Cpu) !?u12 {
    cpu.I = self.low12;
    return null;
}

test "ANNN set I" {
    var cpu = try Cpu.init(&[_]u8{
        0xA6, 0x83,
    }, testing_seed, .{0} ** 8);
    try cpu.cycle();
    try std.testing.expectEqual(@as(u12, 0x683), cpu.I);
}

/// BNNN: jump to NNN + V0
fn opJumpV0(self: Instruction, cpu: *const Cpu) !?u12 {
    return self.low12 +% cpu.V[0x0];
}

test "BNNN jump adding V0" {
    var cpu = try Cpu.init(&[_]u8{
        0x60, 0x58,
        0xB4, 0xC3,
    }, testing_seed, .{0} ** 8);
    try cpu.cycle();
    try cpu.cycle();
    try std.testing.expectEqual(@as(u12, 0x58 + 0x4C3), cpu.pc);
}

/// CXNN: set VX to rand() & NN
fn opRandom(self: Instruction, cpu: *Cpu) !?u12 {
    cpu.V[self.regX] = cpu.rand.random().int(u8) & self.low8;
    return null;
}

test "CXNN random" {
    var prng = std.rand.DefaultPrng.init(testing_seed);
    const rand = prng.random();
    var cpu = try Cpu.init(&[_]u8{
        0xC0, 0xFF,
        0xC0, 0x07,
        0xC0, 0x00,
    }, testing_seed, .{0} ** 8);
    try cpu.cycle();
    try std.testing.expectEqual(rand.int(u8), cpu.V[0x0]);
    try cpu.cycle();
    try std.testing.expectEqual(rand.int(u8) & 0x07, cpu.V[0x0]);
    try cpu.cycle();
    try std.testing.expectEqual(@as(u8, 0x00), cpu.V[0x0]);
}

/// DXYN: draw an 8xN sprite from memory starting at I at (VX, VY); set VF to 1 if any pixel was
/// turned off, 0 otherwise
fn opDraw(self: Instruction, cpu: *Cpu) !?u12 {
    cpu.V[0xF] = 0;
    const sprite: []const u8 = cpu.mem[(cpu.I)..(cpu.I + self.low4)];
    const x_start = cpu.V[self.regX] % Cpu.display_width;
    const y_start = cpu.V[self.regY] % Cpu.display_height;
    for (sprite, 0..) |row, y_sprite| {
        for (0..8) |x_sprite| {
            const mask = @as(u8, 0b10000000) >> @as(u3, @intCast(x_sprite));
            const pixel = (row & mask != 0);
            const x = x_start + x_sprite;
            const y = y_start + y_sprite;
            if (x >= Cpu.display_width or y >= Cpu.display_height) {
                continue;
            }

            const index = y * Cpu.display_width + x;
            if (pixel and cpu.display[index]) {
                // pixel turned off
                cpu.V[0xF] = 1;
            }
            // draw using XOR
            cpu.display[index] = (pixel != cpu.display[index]);
            cpu.display_dirty = cpu.display_dirty or pixel;
        }
    }
    return null;
}

test "DXYN draw" {
    const program = [_]u8{
        0xA3, 0x00, // I = 0x300
        0x60, 8, // V0 = 8
        0x61, 17, // V1 = 17
        0x6F, 0xFF, // VF = 0xFF (it should be cleared)
        0xD0, 0x14, // draw 8x4 at (8, 17)
        0xD0, 0x14, // turn everything back off and set VF
    };
    const sprites = [_]u8{
        0b00110000, // 0x300
        0b11000011,
        0b11000011,
        0b00001100,
    };
    // calculate padding so the sprites start at 0x300
    const rom = program ++ ([1]u8{0} ** (0x100 - program.len)) ++ sprites;
    var cpu = try Cpu.init(&rom, testing_seed, .{0} ** 8);

    try cpu.cycleN(5, null);
    // VF should be cleared
    try std.testing.expectEqual(@as(u8, 0), cpu.V[0xF]);
    try std.testing.expect(cpu.display_dirty);
    // check the screen
    for (sprites, 0..) |pixel, y| {
        for (0..8) |x| {
            const expected = (pixel & (@as(u8, 1) << @as(u3, @intCast(7 - x)))) != 0;
            try std.testing.expectEqual(expected, cpu.display[Cpu.display_width * (y + 17) + x + 8]);
        }
    }

    cpu.display_dirty = false;
    try cpu.cycle();
    // now there was a collision
    try std.testing.expectEqual(@as(u8, 1), cpu.V[0xF]);
    try std.testing.expect(cpu.display_dirty);
    // all off
    for (cpu.display) |pixel| {
        try std.testing.expectEqual(false, pixel);
    }
}

/// EX9E: skip next instruction if the key in VX is pressed
/// EXA1: skip next instruction if the key in VX is not pressed
fn opInput(self: Instruction, cpu: *Cpu) !?u12 {
    return switch (self.low8) {
        0x9E => skipNextInstructionIf(cpu, cpu.keys[cpu.V[self.regX]]),
        0xA1 => skipNextInstructionIf(cpu, !cpu.keys[cpu.V[self.regX]]),
        else => error.IllegalOpcode,
    };
}

test "illegal EXYZ opcodes" {
    for (0x00..0xFF) |low8| {
        if (low8 != 0x9E and low8 != 0xA1) {
            var cpu = try Cpu.init(&[_]u8{
                0xE0, @as(u8, @intCast(low8)),
            }, testing_seed, .{0} ** 8);
            try std.testing.expectError(error.IllegalOpcode, cpu.cycle());
        }
    }
}

test "EX9E skip if pressed" {
    var cpu = try Cpu.init(&[_]u8{
        0x60, 0x05, // check key 5
        0xE0, 0x9E, // skip if 5 pressed (yes)
        0x00, 0x00, // skipped
        0xE1, 0x9E, // skip if 0 pressed (V1 still zeroed) (no)
    }, testing_seed, .{0} ** 8);
    cpu.keys[5] = true;
    try cpu.cycle();
    try cpu.cycle();
    // should skip
    try std.testing.expectEqual(@as(u12, 0x206), cpu.pc);
    try cpu.cycle();
    // should not skip
    try std.testing.expectEqual(@as(u12, 0x208), cpu.pc);
}

test "EXA1 skip if not pressed" {
    var cpu = try Cpu.init(&[_]u8{
        0x60, 0x05, // check key 5
        0xE0, 0xA1, // skip if 5 not pressed (no)
        0xE1, 0xA1, // skip if 0 not pressed (V1 still zeroed) (yes)
    }, testing_seed, .{0} ** 8);
    cpu.keys[5] = true;
    try cpu.cycle();
    try cpu.cycle();
    // should not skip
    try std.testing.expectEqual(@as(u12, 0x204), cpu.pc);
    try cpu.cycle();
    // should skip
    try std.testing.expectEqual(@as(u12, 0x208), cpu.pc);
}

/// dispatch an instruction beginning with F
fn opFXYZ(self: Instruction, cpu: *Cpu) !?u12 {
    const misc_opcode_fns = comptime blk: {
        var fns: [256]OpcodeFn = .{opIllegal} ** 256;
        fns[0x07] = opStoreDT;
        fns[0x0A] = opWaitForKey;
        fns[0x15] = opSetDT;
        fns[0x18] = opSetST;
        fns[0x1E] = opIncIReg;
        fns[0x29] = opSetISprite;
        fns[0x33] = opStoreBCD;
        fns[0x55] = opStore;
        fns[0x65] = opLoad;
        fns[0x75] = opSaveFlags;
        fns[0x85] = opLoadFlags;
        break :blk fns;
    };

    return misc_opcode_fns[self.low8](self, cpu);
}

/// FX07: store the value of the delay timer in VX
fn opStoreDT(self: Instruction, cpu: *Cpu) !?u12 {
    cpu.V[self.regX] = cpu.dt;
    return null;
}

test "FX07 get DT" {
    var cpu = try Cpu.init(&[_]u8{ 0xF0, 0x07 }, testing_seed, .{0} ** 8);
    cpu.dt = 30;
    try cpu.cycle();
    try std.testing.expectEqual(@as(u8, 30), cpu.V[0x0]);
}

/// FX0A: wait until any key is pressed, then store the key that was pressed in VX
fn opWaitForKey(self: Instruction, cpu: *Cpu) !?u12 {
    cpu.next_key_register = self.regX;
    // stay at same instruction
    return cpu.pc;
}

test "FX0A wait for a keypress" {
    var cpu = try Cpu.init(&[_]u8{
        0xF4, 0x0A,
        0xA4, 0x20,
    }, testing_seed, .{0} ** 8);

    // it should stay at the same instruction
    for (0..5) |_| {
        try cpu.cycle();
        try std.testing.expectEqual(@as(u12, 0x200), cpu.pc);
    }

    // press key 1
    cpu.setKeys(&(.{false} ++ .{true} ++ .{false} ** 14));
    // V4 should be set to 1
    try std.testing.expectEqual(@as(u8, 1), cpu.V[0x4]);
    // and the cpu should be continuing past the blocked instruction
    try std.testing.expectEqual(@as(u12, 0x202), cpu.pc);
    // and it should not think it is waiting anymore
    try std.testing.expectEqual(@as(?u4, null), cpu.next_key_register);

    // and it should continue nominally
    try cpu.cycle();
    try std.testing.expectEqual(@as(u12, 0x420), cpu.I);
}

/// FX15: set the delay timer to the value of VX
fn opSetDT(self: Instruction, cpu: *Cpu) !?u12 {
    cpu.dt = cpu.V[self.regX];
    return null;
}

test "FX15 set DT" {
    var cpu = try Cpu.init(&[_]u8{
        0x60, 0x10,
        0xF0, 0x15,
    }, testing_seed, .{0} ** 8);
    try cpu.cycle();
    try cpu.cycle();
    try std.testing.expectEqual(@as(u8, 0x10), cpu.dt);
}

/// FX18: set the sound timer to the value of VX
fn opSetST(self: Instruction, cpu: *Cpu) !?u12 {
    cpu.st = cpu.V[self.regX];
    return null;
}

test "FX18 set ST" {
    var cpu = try Cpu.init(&[_]u8{
        0x60, 0x10,
        0xF0, 0x18,
    }, testing_seed, .{0} ** 8);
    try cpu.cycle();
    try cpu.cycle();
    try std.testing.expectEqual(@as(u8, 0x10), cpu.st);
}

/// FX1E: increment I by the value of VX
fn opIncIReg(self: Instruction, cpu: *Cpu) !?u12 {
    cpu.I +%= cpu.V[self.regX];
    return null;
}

test "FX1E increment I by register" {
    var cpu = try Cpu.init(&[_]u8{
        0xA5, 0x00, // I = 0x500
        0x63, 0x1F, // V3 = 0x1F
        0xF3, 0x1E, // I += V3
        0xAF, 0xFF, // I = 0xFFF
        0x62, 0x02, // V2 = 0x02
        0xF2, 0x1E, // I += V2 (overflows)
    }, testing_seed, .{0} ** 8);
    try cpu.cycleN(3, null);
    try std.testing.expectEqual(@as(u12, 0x51F), cpu.I);
    try cpu.cycleN(3, null);
    try std.testing.expectEqual(@as(u12, 0x001), cpu.I);
}

/// FX29: set I to the address of the sprite for the digit in VX
fn opSetISprite(self: Instruction, cpu: *Cpu) !?u12 {
    cpu.I = Cpu.font_base_address + (@as(u12, @as(u4, @truncate(cpu.V[self.regX]))) * Cpu.font_character_size);
    return null;
}

test "FX29 get address of font" {
    var cpu = try Cpu.init(&[_]u8{
        0x60, 0x3A, // V0 = 0x3A
        0xF0, 0x29, // get that character
    }, testing_seed, .{0} ** 8);
    try cpu.cycle();
    try cpu.cycle();
    try std.testing.expectEqual(@as(u12, Cpu.font_base_address + 0xA * Cpu.font_character_size), cpu.I);
    try std.testing.expectEqualSlices(u8, &.{
        0xf0, 0x90, 0xf0, 0x90, 0x90,
    }, cpu.mem[cpu.I..][0..5]);
}

/// FX33: store the binary-coded decimal version of the value of VX in I, I + 1, and I + 2
fn opStoreBCD(self: Instruction, cpu: *Cpu) !?u12 {
    const value = cpu.V[self.regX];
    cpu.mem[cpu.I] = value / 100;
    cpu.mem[cpu.I +% 1] = (value / 10) % 10;
    cpu.mem[cpu.I +% 2] = value % 10;
    return null;
}

test "FX33 store BCD" {
    var cpu = try Cpu.init(&[_]u8{
        0x60, 83, // V0 = 83
        0xA3, 0x00, // I = 0x300
        0xF0, 0x33, // store BCD of V0
    }, testing_seed, .{0} ** 8);
    try cpu.cycleN(3, null);
    try std.testing.expectEqual(@as(u8, 0), cpu.mem[0x300]);
    try std.testing.expectEqual(@as(u8, 8), cpu.mem[0x301]);
    try std.testing.expectEqual(@as(u8, 3), cpu.mem[0x302]);
}

/// FX55: store registers [V0, VX] in memory starting at I; set I to I + X + 1
fn opStore(self: Instruction, cpu: *Cpu) !?u12 {
    for (0..(@as(u8, self.regX) + 1)) |offset| {
        cpu.mem[cpu.I] = cpu.V[offset];
        cpu.I +%= 1;
    }
    return null;
}

test "FX55 store registers" {
    var cpu = try Cpu.init(&[_]u8{
        0x60, 5,
        0x61, 4,
        0x62, 3,
        0x63, 2,
        0x64, 1,
        0x65, 0xFF, // make sure this is *not* stored
        0xA4, 0x00, // I = 0x400
        0xF4, 0x55,
        0xA2, 0x00, // try storing all registers
        0xFF, 0x55,
    }, testing_seed, .{0} ** 8);
    try cpu.cycleN(8, null);
    try std.testing.expectEqual(@as(u12, 0x405), cpu.I);
    for (0..5) |i| {
        const addr = 0x400 + i;
        const val = 5 - i;
        try std.testing.expectEqual(@as(u8, @intCast(val)), cpu.mem[addr]);
    }
    try std.testing.expectEqual(@as(u8, 0), cpu.mem[0x405]);

    try cpu.cycle();
    try cpu.cycle();
    try std.testing.expectEqual(cpu.V, cpu.mem[0x200..][0..16].*);
}

/// FX65: load values from memory starting at I into registers [V0, VX]; set I to I + X + 1
fn opLoad(self: Instruction, cpu: *Cpu) !?u12 {
    for (0..(@as(u8, self.regX) + 1)) |offset| {
        cpu.V[offset] = cpu.mem[cpu.I];
        cpu.I +%= 1;
    }
    return null;
}

test "FX65 load registers" {
    var cpu = try Cpu.init(&[_]u8{
        0xA2, 0x08, // set I
        0xF4, 0x65, // load them
        0xA4, 0x00,
        0xFF, 0x65, // test loading all registers
        5, 4, 3, 2, 1, // data to load
        0xFF, // do not load
    }, testing_seed, .{0} ** 8);
    try cpu.cycle();
    try cpu.cycle();
    try std.testing.expectEqual(@as(u12, 0x20d), cpu.I);
    for (0..5) |i| {
        const val = 5 - i;
        try std.testing.expectEqual(@as(u8, @intCast(val)), cpu.V[i]);
    }
    // value that was not loaded
    try std.testing.expectEqual(@as(u8, 0), cpu.V[0x5]);

    // now try loading all registers
    try cpu.cycle();
    try cpu.cycle();
    try std.testing.expectEqual(std.mem.zeroes([16]u8), cpu.V);
}

fn opSaveFlags(self: Instruction, cpu: *Cpu) !?u12 {
    if (self.regX > 8) return error.FlagOverflow;
    @memcpy(cpu.flags[0 .. self.regX + 1], cpu.V[0 .. self.regX + 1]);
    cpu.flags_dirty = true;
    return null;
}

test "FX75 save flags" {
    var cpu = try Cpu.init(&[_]u8{
        0x60, 0x11, // some values to be saved in the flags
        0x61, 0x22,
        0x62, 0x33, // this one is not saved
        0xF1, 0x75,
    }, testing_seed, .{0} ** 7 ++ .{0xff});
    try std.testing.expect(!cpu.flags_dirty);
    try cpu.cycleN(4, null);
    try std.testing.expect(cpu.flags_dirty);
    try std.testing.expectEqual([_]u8{ 0x11, 0x22, 0, 0, 0, 0, 0, 0xff }, cpu.flags);
}

fn opLoadFlags(self: Instruction, cpu: *Cpu) !?u12 {
    if (self.regX > 8) return error.FlagOverflow;
    @memcpy(cpu.V[0 .. self.regX + 1], cpu.flags[0 .. self.regX + 1]);
    return null;
}

test "FX85 load flags" {
    var cpu = try Cpu.init(
        &[_]u8{ 0xF2, 0x85 },
        testing_seed,
        [_]u8{ 0x11, 0x22, 0x33, 0x44, 0, 0, 0, 0 },
    );
    try cpu.cycle();
    try std.testing.expectEqualSlices(u8, &.{ 0x11, 0x22, 0x33 }, cpu.V[0..3]);
}

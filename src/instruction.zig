const Instruction = @This();

const std = @import("std");

const CPU = @import("./cpu.zig");

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

var prng = std.rand.DefaultPrng.init(1337);
const testing_rand = prng.random();

/// split up an opcode into useful parts
pub fn decode(opcode: u16) Instruction {
    const nibbles = [4]u4{
        @truncate(u4, opcode >> 12),
        @truncate(u4, opcode >> 8),
        @truncate(u4, opcode >> 4),
        @truncate(u4, opcode >> 0),
    };
    return .{
        .nibbles = nibbles,
        .low8 = @truncate(u8, opcode),
        .low12 = @truncate(u12, opcode),
        .high4 = nibbles[0],
        .regX = nibbles[1],
        .regY = nibbles[2],
        .low4 = nibbles[3],
        .opcode = opcode,
    };
}

/// execute an instruction, returning the new program counter if execution should go somewhere other
/// than the next instruction
pub fn exec(self: Instruction, cpu: *CPU) ExecutionError!?u12 {
    return msd_opcodes[self.high4](self, cpu);
}

pub const ExecutionError = error{
    IllegalOpcode,
    NotImplemented,
    StackOverflow,
    BadReturn,
};

/// a function that executes an instruction and optionally returns the new program counter
const OpcodeFn = fn (self: Instruction, cpu: *CPU) ExecutionError!?u12;

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
fn opIllegal(self: Instruction, cpu: *const CPU) !?u12 {
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
fn op00EX(self: Instruction, cpu: *CPU) !?u12 {
    switch (self.opcode) {
        0x00E0 => {
            for (cpu.display) |*row| {
                std.mem.set(bool, row, false);
            }
            return null;
        },
        0x00EE => {
            if (cpu.sp == 0) {
                return error.BadReturn;
            } else {
                cpu.sp -= 1;
                return cpu.stack[cpu.sp];
            }
        },
        else => return error.IllegalOpcode,
    }
}

test "00E0 clear screen" {
    var cpu = try CPU.init(&[_]u8{
        0x00, 0xE0,
    }, testing_rand);
    // fill screen
    for (cpu.display) |*row| {
        for (row) |*pixel| {
            pixel.* = true;
        }
    }
    try cpu.cycle();
    for (cpu.display) |*row| {
        for (row) |pixel| {
            try std.testing.expectEqual(false, pixel);
        }
    }
}

test "00EE return" {
    var cpu = try CPU.init(&[_]u8{
        0x00, 0xEE, // return to 0x206
        0x00, 0x00,
        0x00, 0x00,
        0x00, 0xEE, // return again but now the stack is empty
    }, testing_rand);
    // set up somewhere to return to
    cpu.sp = 1;
    cpu.stack[0] = 0x206;
    try cpu.cycle();
    // make sure it sent us to the right address and decremented the stack pointer
    try std.testing.expectEqual(@as(u12, 0x206), cpu.pc);
    try std.testing.expectEqual(@as(@TypeOf(cpu.sp), 0), cpu.sp);
    // this should error as there's nothing on the stack anymore
    try std.testing.expectError(error.BadReturn, cpu.cycle());
}

/// 1NNN: jump to NNN
fn opJump(self: Instruction, cpu: *const CPU) !?u12 {
    _ = cpu;
    return self.low12;
}

test "1NNN jump" {
    var cpu = try CPU.init(&[_]u8{
        0x15, 0x62, // jump to 0x562
    }, testing_rand);
    try cpu.cycle();
    try std.testing.expectEqual(@as(u12, 0x562), cpu.pc);
}

/// 2NNN: call address NNN
fn opCall(self: Instruction, cpu: *CPU) !?u12 {
    if (cpu.sp == CPU.stack_size) {
        return error.StackOverflow;
    } else {
        cpu.stack[cpu.sp] = cpu.pc;
        cpu.sp += 1;
        return self.low12;
    }
}

test "2NNN call" {
    // calls an instruction, then jumps back to the start (without returning)
    var cpu = try CPU.init(&[_]u8{
        0x22, 0x08, // 0x200: call 0x208
        0x00, 0x00,
        0x00, 0x00,
        0x00, 0x00,
        0x12, 0x00, // 0x208: jump back to 0x200
    }, testing_rand);

    var i: @TypeOf(cpu.sp) = 0;
    // fill up the stack
    while (i < CPU.stack_size) : (i += 1) {
        // execute call
        try cpu.cycle();
        try std.testing.expectEqual(@as(u12, 0x208), cpu.pc);
        try std.testing.expectEqual(i + 1, cpu.sp);
        try std.testing.expectEqual(@as(u12, 0x200), cpu.stack[i]);
        // execute jump
        try cpu.cycle();
    }
    // now this one should fail
    try std.testing.expectError(error.StackOverflow, cpu.cycle());
}

/// calculate the new PC, using condition as whether the next instruction should be skipped
fn skipNextInstructionIf(cpu: *const CPU, condition: bool) u12 {
    return cpu.pc + @as(u12, if (condition) 4 else 2);
}

/// 3XNN: skip next instruction if VX == NN
fn opSkipEqImm(self: Instruction, cpu: *const CPU) !?u12 {
    return skipNextInstructionIf(cpu, cpu.V[self.regX] == self.low8);
}

test "3XNN skip if VX == NN" {
    var cpu = try CPU.init(&[_]u8{
        0x63, 0x58, // V3 = 0x58
        0x33, 0x58, // skip
        0x00, 0x00, // skipped
        0x33, 0x20, // won't skip
        0x32, 0x58, // won't skip
    }, testing_rand);

    try cpu.cycle();
    try cpu.cycle();
    try std.testing.expectEqual(@as(u12, 0x206), cpu.pc);
    try cpu.cycle();
    try std.testing.expectEqual(@as(u12, 0x208), cpu.pc);
    try cpu.cycle();
    try std.testing.expectEqual(@as(u12, 0x20A), cpu.pc);
}

/// 4XNN: skip next instruction if VX != NN
fn opSkipNeImm(self: Instruction, cpu: *const CPU) !?u12 {
    return skipNextInstructionIf(cpu, cpu.V[self.regX] != self.low8);
}

test "4XNN skip if VX != NN" {
    var cpu = try CPU.init(&[_]u8{
        0x63, 0x58, // V3 = 0x58
        0x43, 0x20, // skip
        0x00, 0x00, // skipped
        0x43, 0x58, // won't skip
        0x42, 0x58, // skip
    }, testing_rand);

    try cpu.cycle();
    try cpu.cycle();
    try std.testing.expectEqual(@as(u12, 0x206), cpu.pc);
    try cpu.cycle();
    try std.testing.expectEqual(@as(u12, 0x208), cpu.pc);
    try cpu.cycle();
    try std.testing.expectEqual(@as(u12, 0x20C), cpu.pc);
}

/// 5XY0: skip next instruction if VX == VY
fn opSkipEqReg(self: Instruction, cpu: *const CPU) !?u12 {
    if (self.low4 != 0x0) {
        return error.IllegalOpcode;
    }
    return skipNextInstructionIf(cpu, cpu.V[self.regX] == cpu.V[self.regY]);
}

test "5XY0 skip if VX == VY" {
    var cpu = try CPU.init(&[_]u8{
        0x60, 0x23, // V0 = 0x23
        0x61, 0x23, // V1 = 0x23
        0x50, 0x10, // skip
        0x00, 0x00, // skipped
        0x51, 0x00, // skip
        0x00, 0x00, // skipped
        0x50, 0x20, // won't skip
        0x50, 0x11, // error
    }, testing_rand);
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
fn opSetRegImm(self: Instruction, cpu: *CPU) !?u12 {
    cpu.V[self.regX] = self.low8;
    return null;
}

test "6XNN set VX to NN" {
    var cpu = try CPU.init(&[_]u8{
        0x60, 0x2F,
        0x61, 0x68,
    }, testing_rand);
    try cpu.cycle();
    try std.testing.expectEqual(@as(u8, 0x2F), cpu.V[0x0]);
    try cpu.cycle();
    try std.testing.expectEqual(@as(u8, 0x68), cpu.V[0x1]);
}

/// 7XNN: add NN to VX without carry
fn opAddImm(self: Instruction, cpu: *CPU) !?u12 {
    cpu.V[self.regX] +%= self.low8;
    return null;
}

test "7XNN add NN to VX" {
    var cpu = try CPU.init(&[_]u8{
        0x70, 0x53,
        0x70, 0xFF,
        0x71, 0x28,
    }, testing_rand);
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
fn opArithmetic(self: Instruction, cpu: *CPU) !?u12 {
    // vx is set to the return value of this function
    const ArithmeticOpcodeFn = fn (vx: u8, vy: u8, vf: *u8) ExecutionError!u8;
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

/// 8XY0: set VX to VY
fn opSetRegReg(vx: u8, vy: u8, vf: *const u8) !u8 {
    _ = vx;
    _ = vf;
    return vy;
}

/// 8XY1: set VX to VX | VY
fn opOr(vx: u8, vy: u8, vf: *const u8) !u8 {
    _ = vf;
    return vx | vy;
}

/// 8XY2: set VX to VX & VY
fn opAnd(vx: u8, vy: u8, vf: *const u8) !u8 {
    _ = vf;
    return vx & vy;
}

/// 8XY3: set VX to VX ^ VY
fn opXor(vx: u8, vy: u8, vf: *const u8) !u8 {
    _ = vf;
    return vx ^ vy;
}

/// 8XY4: set VX to VX + VY; set VF to 1 if carry occurred, 0 otherwise
fn opAdd(vx: u8, vy: u8, vf: *u8) !u8 {
    var new_vx = vx;
    if (@addWithOverflow(u8, vx, vy, &new_vx)) {
        vf.* = 1;
    } else {
        vf.* = 0;
    }
    return new_vx;
}

/// 8XY5: set VX to VX - VY; set VF to 0 if borrow occurred, 1 otherwise
fn opSub(vx: u8, vy: u8, vf: *u8) !u8 {
    var new_vx = vx;
    if (@subWithOverflow(u8, vx, vy, &new_vx)) {
        vf.* = 0;
    } else {
        vf.* = 1;
    }
    return new_vx;
}

/// 8XY6: set VX to VY >> 1, set VF to the former least significant bit of VY
fn opShiftRight(vx: u8, vy: u8, vf: *u8) !u8 {
    _ = vx;
    vf.* = vy & 0x01;
    return vy >> 1;
}

/// 8XY7: set VX to VY - VX; set VF to 0 if borrow occurred, 1 otherwise
fn opSubRev(vx: u8, vy: u8, vf: *u8) !u8 {
    var new_vx = vx;
    if (@subWithOverflow(u8, vy, vx, &new_vx)) {
        vf.* = 0;
    } else {
        vf.* = 1;
    }
    return new_vx;
}

/// 8XYE: set VX to VY << 1, set VF to the former most significant bit of VY
fn opShiftLeft(vx: u8, vy: u8, vf: *u8) !u8 {
    _ = vx;
    vf.* = vy >> 7;
    return vy << 1;
}

/// 9XY0: skip next instruction if VX != VY
fn opSkipNeReg(self: Instruction, cpu: *const CPU) !?u12 {
    if (self.low4 != 0x0) {
        return error.IllegalOpcode;
    }
    return skipNextInstructionIf(cpu, cpu.V[self.regX] != cpu.V[self.regY]);
}

/// ANNN: set I to NNN
fn opSetIImm(self: Instruction, cpu: *CPU) !?u12 {
    cpu.I = self.low12;
    return null;
}

/// BNNN: jump to NNN + V0
fn opJumpV0(self: Instruction, cpu: *const CPU) !?u12 {
    return self.low12 + cpu.V[0x0];
}

/// CXNN: set VX to rand() & NN
fn opRandom(self: Instruction, cpu: *CPU) !?u12 {
    cpu.V[self.regX] = cpu.rand.int(u8) & self.low8;
    return null;
}

/// DXYN: draw an 8xN sprite from memory starting at I at (VX, VY); set VF to 1 if any pixel was
/// turned off, 0 otherwise
fn opDraw(self: Instruction, cpu: *CPU) !?u12 {
    cpu.V[0xF] = 0;
    const sprite: []const u8 = cpu.mem[(cpu.I)..(cpu.I + self.low4)];
    const x_start = cpu.V[self.regX] % CPU.display_width;
    const y_start = cpu.V[self.regY] % CPU.display_height;
    for (sprite) |row, y_sprite| {
        var x_sprite: u4 = 0;
        while (x_sprite < 8) : (x_sprite += 1) {
            const mask = @as(u8, 0b10000000) >> @intCast(u3, x_sprite);
            const pixel = (row & mask == 0);
            const x = x_start + x_sprite;
            const y = y_start + y_sprite;
            if (x >= CPU.display_width or y >= CPU.display_height) {
                continue;
            }
            if (pixel and cpu.display[y][x]) {
                // pixel turned off
                cpu.V[0xF] = 1;
            }
            // draw using XOR
            cpu.display[y][x] = (pixel != cpu.display[y][x]);
        }
    }
    return null;
}

/// EX9E: skip next instruction if the key in VX is pressed
/// EXA1: skip next instruction if the key in VX is not pressed
fn opInput(self: Instruction, cpu: *CPU) !?u12 {
    return switch (self.low8) {
        0x9E => skipNextInstructionIf(cpu, cpu.keys[cpu.V[self.regX]]),
        0xA1 => skipNextInstructionIf(cpu, !cpu.keys[cpu.V[self.regX]]),
        else => error.IllegalOpcode,
    };
}

/// dispatch an instruction beginning with F
fn opFXYZ(self: Instruction, cpu: *CPU) !?u12 {
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
        break :blk fns;
    };

    return misc_opcode_fns[self.low8](self, cpu);
}

/// FX07: store the value of the delay timer in VX
fn opStoreDT(self: Instruction, cpu: *CPU) !?u12 {
    cpu.V[self.regX] = cpu.dt;
    return null;
}

/// FX0A: wait until any key is pressed, then store the key that was pressed in VX
fn opWaitForKey(self: Instruction, cpu: *CPU) !?u12 {
    _ = cpu;
    _ = self;
    return error.NotImplemented;
}

/// FX15: set the delay timer to the value of VX
fn opSetDT(self: Instruction, cpu: *CPU) !?u12 {
    cpu.dt = cpu.V[self.regX];
    return null;
}

/// FX18: set the sound timer to the value of VX
fn opSetST(self: Instruction, cpu: *CPU) !?u12 {
    cpu.st = cpu.V[self.regX];
    return null;
}

/// FX1E: increment I by the value of VX
fn opIncIReg(self: Instruction, cpu: *CPU) !?u12 {
    cpu.I +%= cpu.V[self.regX];
    return null;
}

/// FX29: set I to the address of the sprite for the digit in VX
fn opSetISprite(self: Instruction, cpu: *CPU) !?u12 {
    cpu.I = CPU.font_base_address + (@truncate(u4, cpu.V[self.regX]) * CPU.font_character_size);
    return null;
}

/// FX33: store the binary-coded decimal version of the value of VX in I, I + 1, and I + 2
fn opStoreBCD(self: Instruction, cpu: *CPU) !?u12 {
    const value = cpu.V[self.regX];
    cpu.mem[cpu.I] = value / 100;
    cpu.mem[cpu.I + 1] = (value / 10) % 10;
    cpu.mem[cpu.I + 2] = value % 10;
    return null;
}

/// FX55: store registers [V0, VX] in memory starting at I; set I to I + X + 1
fn opStore(self: Instruction, cpu: *CPU) !?u12 {
    var offset: u5 = 0;
    while (offset <= self.regX) : (offset += 1) {
        cpu.mem[cpu.I] = cpu.V[offset];
        cpu.I += 1;
    }
    return null;
}

/// FX65: load values from memory starting at I into registers [V0, Vx]; set I to I + X + 1
fn opLoad(self: Instruction, cpu: *CPU) !?u12 {
    var offset: u5 = 0;
    while (offset <= self.regX) : (offset += 1) {
        cpu.V[offset] = cpu.mem[cpu.I];
        cpu.I += 1;
    }
    return null;
}

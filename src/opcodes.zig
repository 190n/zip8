const std = @import("std");

const CPU = @import("./cpu.zig");

pub const ExecutionError = error{
    IllegalOpcode,
    NotImplemented,
    StackOverflow,
    BadReturn,
};

/// split an opcode into hex digits
fn split(opcode: u16) [4]u4 {
    return .{
        @truncate(u4, opcode >> 12),
        @truncate(u4, opcode >> 8),
        @truncate(u4, opcode >> 4),
        @truncate(u4, opcode >> 0),
    };
}

/// a function that executes an instruction and optionally returns the new program counter
pub const OpcodeFn = fn (self: *CPU, opcode: u16) ExecutionError!?u12;

/// functions that delegate opcodes by the most significant hex digit
pub const msd_opcodes = [16]OpcodeFn{
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
pub fn opIllegal(self: *const CPU, opcode: u16) !?u12 {
    _ = self;
    _ = opcode;
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
pub fn op00EX(self: *CPU, opcode: u16) !?u12 {
    switch (opcode) {
        0x00E0 => {
            for (self.display) |*row| {
                std.mem.set(bool, row, false);
            }
            return null;
        },
        0x00EE => {
            if (self.sp == 0) {
                return error.BadReturn;
            } else {
                self.sp -= 1;
                return self.stack[self.sp];
            }
        },
        else => return error.IllegalOpcode,
    }
}

/// 1NNN: jump to NNN
pub fn opJump(self: *const CPU, opcode: u16) !?u12 {
    _ = self;
    return @truncate(u12, opcode);
}

/// 2NNN: call address NNN
pub fn opCall(self: *CPU, opcode: u16) !?u12 {
    if (self.sp == CPU.stack_size) {
        return error.StackOverflow;
    } else {
        const target = @truncate(u12, opcode);
        self.stack[self.sp] = self.pc;
        self.sp += 1;
        return target;
    }
}

/// calculate the new PC, using condition as whether the next instruction should be skipped
fn skipTarget(self: *const CPU, condition: bool) u12 {
    return self.pc + @as(u12, if (condition) 4 else 2);
}

/// 3XNN: skip next instruction if VX == NN
pub fn opSkipEqImm(self: *const CPU, opcode: u16) !?u12 {
    // get register
    const vx = self.V[split(opcode)[1]];
    // get value to compare to
    const immediate = @truncate(u8, opcode);
    return skipTarget(self, vx == immediate);
}

/// 4XNN: skip next instruction if VX != NN
pub fn opSkipNeImm(self: *const CPU, opcode: u16) !?u12 {
    // get register
    const vx = self.V[split(opcode)[1]];
    // get value to compare to
    const immediate = @truncate(u8, opcode);
    return skipTarget(self, vx != immediate);
}

/// 5XY0: skip next instruction if VX == VY
pub fn opSkipEqReg(self: *const CPU, opcode: u16) !?u12 {
    if (split(opcode)[3] != 0x0) {
        return error.IllegalOpcode;
    }
    const vx = self.V[split(opcode)[1]];
    const vy = self.V[split(opcode)[2]];
    return skipTarget(self, vx == vy);
}

/// 6XNN: set VX to NN
pub fn opSetRegImm(self: *CPU, opcode: u16) !?u12 {
    const reg = split(opcode)[1];
    const val = @truncate(u8, opcode);
    self.V[reg] = val;
    return null;
}

/// 7XNN: add NN to VX without carry
pub fn opAddImm(self: *CPU, opcode: u16) !?u12 {
    const reg = split(opcode)[1];
    const val = @truncate(u8, opcode);
    self.V[reg] +%= val;
    return null;
}

/// dispatch an arithmetic instruction beginning with 8
pub fn opArithmetic(self: *CPU, opcode: u16) !?u12 {
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
        opIllegalArithmetic,
        opIllegalArithmetic,
        opIllegalArithmetic,
        opIllegalArithmetic,
        opIllegalArithmetic,
        opIllegalArithmetic,
        opShiftLeft, // 8XYE
        opIllegalArithmetic,
    };

    const which_fn = arithmetic_opcodes[split(opcode)[3]];
    const vx = &self.V[split(opcode)[1]];
    const vy = &self.V[split(opcode)[2]];
    vx.* = try which_fn(vx.*, vy.*, &self.V[0xF]);
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
pub fn opSkipNeReg(self: *CPU, opcode: u16) !?u12 {
    _ = self;
    _ = opcode;
    return error.NotImplemented;
}

/// ANNN: set I to NNN
pub fn opSetIImm(self: *CPU, opcode: u16) !?u12 {
    _ = self;
    _ = opcode;
    return error.NotImplemented;
}

/// BNNN: jump to NNN + V0
pub fn opJumpV0(self: *CPU, opcode: u16) !?u12 {
    _ = self;
    _ = opcode;
    return error.NotImplemented;
}

/// CXNN: set VX to rand() & NN
pub fn opRandom(self: *CPU, opcode: u16) !?u12 {
    _ = self;
    _ = opcode;
    return error.NotImplemented;
}

/// DXYN: draw an 8xN sprite from memory starting at I at (VX, VY)
pub fn opDraw(self: *CPU, opcode: u16) !?u12 {
    _ = self;
    _ = opcode;
    return error.NotImplemented;
}

/// EX9E: skip next instruction if the key in VX is pressed
/// EXA1: skip next instruction if the key in VX is not pressed
pub fn opInput(self: *CPU, opcode: u16) !?u12 {
    _ = self;
    _ = opcode;
    return error.NotImplemented;
}

/// dispatch an instruction beginning with F
pub fn opFXYZ(self: *CPU, opcode: u16) !?u12 {
    _ = self;
    _ = opcode;
    return error.NotImplemented;
}

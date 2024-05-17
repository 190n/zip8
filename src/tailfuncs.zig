const std = @import("std");

const tail = @import("./tail.zig");
const Cpu = tail.Cpu;
const Decoded = tail.Decoded;

inline fn cont(cpu: *Cpu, pc: u12, comptime inc_by_2: bool) void {
    if (cpu.instructions == 0) {
        @setCold(true);
        cpu.pc = pc;
        return;
    }
    cpu.instructions -= 1;
    var pc_mut = pc;
    if (inc_by_2) {
        pc_mut += 2;
    }
    const next = cpu.code[pc_mut];
    @call(.always_tail, next.func, .{ cpu, next.decoded.toInt(), pc_mut });
}

/// 00E0: clear the screen
pub fn clear(cpu: *Cpu, decoded: Decoded.Int, pc: u12) void {
    _ = Decoded.fromInt(decoded).none;
    @memset(&cpu.display, 0);
    cont(cpu, pc, true);
}

/// 00EE: return
pub fn ret(cpu: *Cpu, decoded: Decoded.Int, pc: u12) void {
    _ = pc; // autofix
    _ = Decoded.fromInt(decoded).none;
    const new_pc = cpu.stack.popOrNull() orelse @panic("empty stack");
    cont(cpu, new_pc, false);
}

/// 1NNN: jump to NNN
pub fn jump(cpu: *Cpu, decoded: Decoded.Int, pc: u12) void {
    _ = pc; // autofix
    const new_pc = Decoded.fromInt(decoded).nnn;
    cont(cpu, new_pc, false);
}

/// 2NNN: call address NNN
pub fn call(cpu: *Cpu, decoded: Decoded.Int, pc: u12) void {
    cpu.stack.append(pc + 2) catch @panic("full stack");
    const new_pc = Decoded.fromInt(decoded).nnn;
    cont(cpu, new_pc, false);
}

/// 3XNN: skip next instruction if VX == NN
pub fn skipIfEqual(cpu: *Cpu, decoded: Decoded.Int, pc: u12) void {
    const x, const nn = Decoded.fromInt(decoded).xnn;
    const new_pc = pc + @as(u12, if (cpu.v[x] == nn) 4 else 2);
    cont(cpu, new_pc, false);
}

/// 4XNN: skip next instruction if VX != NN
pub fn skipIfNotEqual(cpu: *Cpu, decoded: Decoded.Int, pc: u12) void {
    const x, const nn = Decoded.fromInt(decoded).xnn;
    const new_pc = pc + @as(u12, if (cpu.v[x] != nn) 4 else 2);
    cont(cpu, new_pc, false);
}

/// 5XY0: skip next instruction if VX == VY
pub fn skipIfRegistersEqual(cpu: *Cpu, decoded: Decoded.Int, pc: u12) void {
    _ = pc; // autofix
    _ = decoded;
    std.debug.panic("skipIfRegistersEqual at {x:0>3}", .{cpu.pc});
}

/// 6XNN: set VX to NN
pub fn setRegister(cpu: *Cpu, decoded: Decoded.Int, pc: u12) void {
    const x, const nn = Decoded.fromInt(decoded).xnn;
    cpu.v[x] = nn;
    cont(cpu, pc, true);
}

/// 7XNN: add NN to VX without carry
pub fn addImmediate(cpu: *Cpu, decoded: Decoded.Int, pc: u12) void {
    const x, const nn = Decoded.fromInt(decoded).xnn;
    cpu.v[x] +%= nn;
    cont(cpu, pc, true);
}

/// 8XY0: set VX to VY
pub fn setRegisterToRegister(cpu: *Cpu, decoded: Decoded.Int, pc: u12) void {
    const x, const y = Decoded.fromInt(decoded).xy;
    cpu.v[x] = cpu.v[y];
    cont(cpu, pc, true);
}

/// 8XY1: set VX to VX | VY
pub fn bitwiseOr(cpu: *Cpu, decoded: Decoded.Int, pc: u12) void {
    _ = pc; // autofix
    _ = decoded;
    std.debug.panic("bitwiseOr at {x:0>3}", .{cpu.pc});
}

/// 8XY2: set VX to VX & VY
pub fn bitwiseAnd(cpu: *Cpu, decoded: Decoded.Int, pc: u12) void {
    const x, const y = Decoded.fromInt(decoded).xy;
    cpu.v[x] &= cpu.v[y];
    cont(cpu, pc, true);
}

/// 8XY3: set VX to VX ^ VY
pub fn bitwiseXor(cpu: *Cpu, decoded: Decoded.Int, pc: u12) void {
    _ = pc; // autofix
    _ = decoded;
    std.debug.panic("bitwiseXor at {x:0>3}", .{cpu.pc});
}

/// 8XY4: set VX to VX + VY; set VF to 1 if carry occurred, 0 otherwise
pub fn addRegisters(cpu: *Cpu, decoded: Decoded.Int, pc: u12) void {
    const x, const y = Decoded.fromInt(decoded).xy;
    cpu.v[x], cpu.v[0xF] = @addWithOverflow(cpu.v[x], cpu.v[y]);
    cont(cpu, pc, true);
}

/// 8XY5: set VX to VX - VY; set VF to 0 if borrow occurred, 1 otherwise
pub fn subRegisters(cpu: *Cpu, decoded: Decoded.Int, pc: u12) void {
    const x, const y = Decoded.fromInt(decoded).xy;
    cpu.v[x], const overflow = @subWithOverflow(cpu.v[x], cpu.v[y]);
    cpu.v[0xF] = ~overflow;
    cont(cpu, pc, true);
}

/// 8XY6: set VX to VY >> 1, set VF to the former least significant bit of VY
pub fn shiftRight(cpu: *Cpu, decoded: Decoded.Int, pc: u12) void {
    _ = pc; // autofix
    _ = decoded;
    std.debug.panic("shiftRight at {x:0>3}", .{cpu.pc});
}

/// 8XY7: set VX to VY - VX; set VF to 0 if borrow occurred, 1 otherwise
pub fn subRegistersReverse(cpu: *Cpu, decoded: Decoded.Int, pc: u12) void {
    const x, const y = Decoded.fromInt(decoded).xy;
    cpu.v[x], const overflow = @subWithOverflow(cpu.v[y], cpu.v[x]);
    cpu.v[0xF] = ~overflow;
    cont(cpu, pc, true);
}

/// 8XYE: set VX to VY << 1, set VF to the former most significant bit of VY
pub fn shiftLeft(cpu: *Cpu, decoded: Decoded.Int, pc: u12) void {
    const x, const y = Decoded.fromInt(decoded).xy;
    cpu.v[0xF] = (cpu.v[y] >> 7) & 1;
    cpu.v[x] = cpu.v[y] << 1;
    cont(cpu, pc, true);
}

/// 9XY0: skip next instruction if VX != VY
pub fn skipIfRegistersNotEqual(cpu: *Cpu, decoded: Decoded.Int, pc: u12) void {
    _ = pc; // autofix
    _ = decoded;
    std.debug.panic("skipIfRegistersNotEqual at {x:0>3}", .{cpu.pc});
}

/// ANNN: set I to NNN
pub fn setI(cpu: *Cpu, decoded: Decoded.Int, pc: u12) void {
    cpu.i = Decoded.fromInt(decoded).nnn;
    cont(cpu, pc, true);
}

/// BNNN: jump to NNN + V0
pub fn jumpV0(cpu: *Cpu, decoded: Decoded.Int, pc: u12) void {
    _ = pc; // autofix
    _ = decoded;
    std.debug.panic("jumpV0 at {x:0>3}", .{cpu.pc});
}

/// CXNN: set VX to rand() & NN
pub fn random(cpu: *Cpu, decoded: Decoded.Int, pc: u12) void {
    const x, const nn = Decoded.fromInt(decoded).xnn;
    const byte = cpu.random.random().int(u8);
    cpu.v[x] = byte & nn;
    cont(cpu, pc, true);
}

/// DXYN: draw an 8xN sprite from memory starting at I at (VX, VY); set VF to 1 if any pixel was
/// turned off, 0 otherwise
pub fn draw(cpu: *Cpu, decoded: Decoded.Int, pc: u12) void {
    const x_reg, const y_reg, const n = Decoded.fromInt(decoded).xyn;
    const x: u16 = cpu.v[x_reg] % 64;
    const y: u16 = cpu.v[y_reg] % 32;
    var intersect: u8 = 0;
    for (0..@min(n, 32 - y)) |row| {
        const left = @bitReverse(cpu.mem[cpu.i + row]) << @truncate(x % 8);
        const right: u8 = @truncate(@as(u16, @bitReverse(cpu.mem[cpu.i + row])) >> @truncate(8 - (x % 8)));
        const index = (64 * (y + row) + x) / 8;
        intersect |= (cpu.display[index] & left);
        cpu.display[index] ^= left;
        if (x < 56) {
            intersect |= (cpu.display[index + 1] & right);
            cpu.display[index + 1] ^= right;
        }
    }
    cpu.v[0xF] = @intFromBool(intersect != 0);
    cont(cpu, pc, true);
}

/// EX9E: skip next instruction if the key in VX is pressed
pub fn skipIfPressed(cpu: *Cpu, decoded: Decoded.Int, pc: u12) void {
    _ = pc; // autofix
    _ = decoded;
    std.debug.panic("skipIfPressed at {x:0>3}", .{cpu.pc});
}

/// EXA1: skip next instruction if the key in VX is not pressed
pub fn skipIfNotPressed(cpu: *Cpu, decoded: Decoded.Int, pc: u12) void {
    _ = pc; // autofix
    _ = decoded;
    std.debug.panic("skipIfNotPressed at {x:0>3}", .{cpu.pc});
}

/// FX07: store the value of the delay timer in VX
pub fn readDt(cpu: *Cpu, decoded: Decoded.Int, pc: u12) void {
    const x, _ = Decoded.fromInt(decoded).xnn;
    cpu.v[x] = cpu.dt;
    cont(cpu, pc, true);
}

/// FX0A: wait until any key is pressed, then store the key that was pressed in VX
pub fn waitForKey(cpu: *Cpu, decoded: Decoded.Int, pc: u12) void {
    _ = pc; // autofix
    _ = decoded;
    std.debug.panic("waitForKey at {x:0>3}", .{cpu.pc});
}

/// FX15: set the delay timer to the value of VX
pub fn setDt(cpu: *Cpu, decoded: Decoded.Int, pc: u12) void {
    const x, _ = Decoded.fromInt(decoded).xnn;
    cpu.dt = cpu.v[x];
    cont(cpu, pc, true);
}

/// FX18: set the sound timer to the value of VX
pub fn setSt(cpu: *Cpu, decoded: Decoded.Int, pc: u12) void {
    _ = pc; // autofix
    _ = decoded;
    std.debug.panic("setSt at {x:0>3}", .{cpu.pc});
}

/// FX1E: increment I by the value of VX
pub fn incrementI(cpu: *Cpu, decoded: Decoded.Int, pc: u12) void {
    const x, _ = Decoded.fromInt(decoded).xnn;
    cpu.i +%= cpu.v[x];
    cont(cpu, pc, true);
}

/// FX29: set I to the address of the sprite for the digit in VX
pub fn setIToFont(cpu: *Cpu, decoded: Decoded.Int, pc: u12) void {
    const x, _ = Decoded.fromInt(decoded).xnn;
    const val: u4 = @truncate(cpu.v[x]);
    cpu.i = 5 * @as(u8, val);
    cont(cpu, pc, true);
}

/// FX33: store the binary-coded decimal version of the value of VX in I, I + 1, and I + 2
pub fn storeBcd(cpu: *Cpu, decoded: Decoded.Int, pc: u12) void {
    const x, _ = Decoded.fromInt(decoded).xnn;
    cpu.mem[cpu.i] = cpu.v[x] / 100;
    cpu.mem[cpu.i +% 1] = (cpu.v[x] / 10) % 10;
    cpu.mem[cpu.i +% 2] = cpu.v[x] % 10;
    @memset(cpu.code[cpu.i..][0..2], .{ .func = &tail.decode, .decoded = undefined });
    cont(cpu, pc, true);
}

/// FX55: store registers [V0, VX] in memory starting at I; set I to I + X + 1
pub fn store(cpu: *Cpu, decoded: Decoded.Int, pc: u12) void {
    const x: u8, _ = Decoded.fromInt(decoded).xnn;
    @memcpy(cpu.mem[cpu.i..][0 .. x + 1], cpu.v[0 .. x + 1]);
    @memset(cpu.code[cpu.i - 1 ..][0 .. x + 2], .{ .func = &tail.decode, .decoded = undefined });
    cpu.i = cpu.i + x + 1;
    cont(cpu, pc, true);
}

/// FX65: load values from memory starting at I into registers [V0, VX]; set I to I + X + 1
pub fn load(cpu: *Cpu, decoded: Decoded.Int, pc: u12) void {
    const x: u8, _ = Decoded.fromInt(decoded).xnn;
    @memcpy(cpu.v[0 .. x + 1], cpu.mem[cpu.i .. cpu.i + x + 1]);
    cpu.i = cpu.i + x + 1;
    cont(cpu, pc, true);
}

/// FX75: store registers [V0, VX] in flags. X < 8
pub fn storeFlags(cpu: *Cpu, decoded: Decoded.Int, pc: u12) void {
    _ = pc; // autofix
    _ = decoded;
    std.debug.panic("storeFlags at {x:0>3}", .{cpu.pc});
}

/// FX75: load flags into [V0, VX]. X < 8
pub fn loadFlags(cpu: *Cpu, decoded: Decoded.Int, pc: u12) void {
    _ = pc; // autofix
    _ = decoded;
    std.debug.panic("loadFlags at {x:0>3}", .{cpu.pc});
}

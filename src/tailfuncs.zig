const std = @import("std");

const tail = @import("./tail.zig");
const Cpu = tail.Cpu;
const Decoded = tail.Decoded;

inline fn cont(cpu: *Cpu, comptime inc_by_2: bool) void {
    if (cpu.instructions == 0) {
        @setCold(true);
        return;
    }
    cpu.instructions -= 1;
    if (inc_by_2) {
        cpu.pc += 2;
    }
    const next = cpu.code[cpu.pc];
    @call(.always_tail, next.func, .{ cpu, next.decoded.toInt() });
}

/// 00E0: clear the screen
pub fn clear(cpu: *Cpu, decoded: Decoded.Int) void {
    _ = decoded;
    @memset(&cpu.display, 0);
    cont(cpu, true);
}

/// 00EE: return
pub fn ret(cpu: *Cpu, decoded: Decoded.Int) void {
    _ = decoded;
    cpu.pc = cpu.stack.popOrNull() orelse @panic("empty stack");
    cont(cpu, false);
}

/// 1NNN: jump to NNN
pub fn jump(cpu: *Cpu, decoded: Decoded.Int) void {
    cpu.pc = Decoded.fromInt(decoded).nnn;
    cont(cpu, false);
}

/// 2NNN: call address NNN
pub fn call(cpu: *Cpu, decoded: Decoded.Int) void {
    cpu.stack.append(cpu.pc + 2) catch @panic("full stack");
    cpu.pc = Decoded.fromInt(decoded).nnn;
    cont(cpu, false);
}

/// 3XNN: skip next instruction if VX == NN
pub fn skipIfEqual(cpu: *Cpu, decoded: Decoded.Int) void {
    const x, const nn = Decoded.fromInt(decoded).xnn;
    cpu.pc += if (cpu.v[x] == nn) 4 else 2;
    cont(cpu, false);
}

/// 4XNN: skip next instruction if VX != NN
pub fn skipIfNotEqual(cpu: *Cpu, decoded: Decoded.Int) void {
    const x, const nn = Decoded.fromInt(decoded).xnn;
    cpu.pc += if (cpu.v[x] != nn) 4 else 2;
    cont(cpu, false);
}

/// 5XY0: skip next instruction if VX == VY
pub fn skipIfRegistersEqual(cpu: *Cpu, decoded: Decoded.Int) void {
    _ = decoded;
    std.debug.panic("skipIfRegistersEqual at {x:0>3}", .{cpu.pc});
}

/// 6XNN: set VX to NN
pub fn setRegister(cpu: *Cpu, decoded: Decoded.Int) void {
    const x, const nn = Decoded.fromInt(decoded).xnn;
    cpu.v[x] = nn;
    cont(cpu, true);
}

/// 7XNN: add NN to VX without carry
pub fn addImmediate(cpu: *Cpu, decoded: Decoded.Int) void {
    const x, const nn = Decoded.fromInt(decoded).xnn;
    cpu.v[x] +%= nn;
    cont(cpu, true);
}

/// 8XY0: set VX to VY
pub fn setRegisterToRegister(cpu: *Cpu, decoded: Decoded.Int) void {
    const x, const y = Decoded.fromInt(decoded).xy;
    cpu.v[x] = cpu.v[y];
    cont(cpu, true);
}

/// 8XY1: set VX to VX | VY
pub fn bitwiseOr(cpu: *Cpu, decoded: Decoded.Int) void {
    _ = decoded;
    std.debug.panic("bitwiseOr at {x:0>3}", .{cpu.pc});
}

/// 8XY2: set VX to VX & VY
pub fn bitwiseAnd(cpu: *Cpu, decoded: Decoded.Int) void {
    const x, const y = Decoded.fromInt(decoded).xy;
    cpu.v[x] &= cpu.v[y];
    cont(cpu, true);
}

/// 8XY3: set VX to VX ^ VY
pub fn bitwiseXor(cpu: *Cpu, decoded: Decoded.Int) void {
    _ = decoded;
    std.debug.panic("bitwiseXor at {x:0>3}", .{cpu.pc});
}

/// 8XY4: set VX to VX + VY; set VF to 1 if carry occurred, 0 otherwise
pub fn addRegisters(cpu: *Cpu, decoded: Decoded.Int) void {
    const x, const y = Decoded.fromInt(decoded).xy;
    cpu.v[x], cpu.v[0xF] = @addWithOverflow(cpu.v[x], cpu.v[y]);
    cont(cpu, true);
}

/// 8XY5: set VX to VX - VY; set VF to 0 if borrow occurred, 1 otherwise
pub fn subRegisters(cpu: *Cpu, decoded: Decoded.Int) void {
    const x, const y = Decoded.fromInt(decoded).xy;
    cpu.v[x], const overflow = @subWithOverflow(cpu.v[x], cpu.v[y]);
    cpu.v[0xF] = ~overflow;
    cont(cpu, true);
}

/// 8XY6: set VX to VY >> 1, set VF to the former least significant bit of VY
pub fn shiftRight(cpu: *Cpu, decoded: Decoded.Int) void {
    _ = decoded;
    std.debug.panic("shiftRight at {x:0>3}", .{cpu.pc});
}

/// 8XY7: set VX to VY - VX; set VF to 0 if borrow occurred, 1 otherwise
pub fn subRegistersReverse(cpu: *Cpu, decoded: Decoded.Int) void {
    _ = decoded;
    std.debug.panic("subRegistersReverse at {x:0>3}", .{cpu.pc});
}

/// 8XYE: set VX to VY << 1, set VF to the former most significant bit of VY
pub fn shiftLeft(cpu: *Cpu, decoded: Decoded.Int) void {
    const x, const y = Decoded.fromInt(decoded).xy;
    cpu.v[0xF] = (cpu.v[y] >> 7) & 1;
    cpu.v[x] = cpu.v[y] << 1;
    cont(cpu, true);
}

/// 9XY0: skip next instruction if VX != VY
pub fn skipIfRegistersNotEqual(cpu: *Cpu, decoded: Decoded.Int) void {
    _ = decoded;
    std.debug.panic("skipIfRegistersNotEqual at {x:0>3}", .{cpu.pc});
}

/// ANNN: set I to NNN
pub fn setI(cpu: *Cpu, decoded: Decoded.Int) void {
    cpu.i = Decoded.fromInt(decoded).nnn;
    cont(cpu, true);
}

/// BNNN: jump to NNN + V0
pub fn jumpV0(cpu: *Cpu, decoded: Decoded.Int) void {
    _ = decoded;
    std.debug.panic("jumpV0 at {x:0>3}", .{cpu.pc});
}

/// CXNN: set VX to rand() & NN
pub fn random(cpu: *Cpu, decoded: Decoded.Int) void {
    const x, const nn = Decoded.fromInt(decoded).xnn;
    const byte = cpu.random.random().int(u8);
    cpu.v[x] = byte & nn;
    cont(cpu, true);
}

/// DXYN: draw an 8xN sprite from memory starting at I at (VX, VY); set VF to 1 if any pixel was
/// turned off, 0 otherwise
pub fn draw(cpu: *Cpu, decoded: Decoded.Int) void {
    _ = decoded;
    // std.debug.panic("draw at {x:0>3}, {} to go", .{ cpu.pc, cpu.instructions });
    std.log.warn("draw", .{});
    cont(cpu, true);
}

/// EX9E: skip next instruction if the key in VX is pressed
pub fn skipIfPressed(cpu: *Cpu, decoded: Decoded.Int) void {
    _ = decoded;
    std.debug.panic("skipIfPressed at {x:0>3}", .{cpu.pc});
}

/// EXA1: skip next instruction if the key in VX is not pressed
pub fn skipIfNotPressed(cpu: *Cpu, decoded: Decoded.Int) void {
    _ = decoded;
    std.debug.panic("skipIfNotPressed at {x:0>3}", .{cpu.pc});
}

/// FX07: store the value of the delay timer in VX
pub fn readDt(cpu: *Cpu, decoded: Decoded.Int) void {
    _ = decoded;
    std.debug.panic("readDt at {x:0>3}", .{cpu.pc});
}

/// FX0A: wait until any key is pressed, then store the key that was pressed in VX
pub fn waitForKey(cpu: *Cpu, decoded: Decoded.Int) void {
    _ = decoded;
    std.debug.panic("waitForKey at {x:0>3}", .{cpu.pc});
}

/// FX15: set the delay timer to the value of VX
pub fn setDt(cpu: *Cpu, decoded: Decoded.Int) void {
    _ = decoded;
    std.debug.panic("setDt at {x:0>3}", .{cpu.pc});
}

/// FX18: set the sound timer to the value of VX
pub fn setSt(cpu: *Cpu, decoded: Decoded.Int) void {
    _ = decoded;
    std.debug.panic("setSt at {x:0>3}", .{cpu.pc});
}

/// FX1E: increment I by the value of VX
pub fn incrementI(cpu: *Cpu, decoded: Decoded.Int) void {
    const x, _ = Decoded.fromInt(decoded).xnn;
    cpu.i +%= cpu.v[x];
    cont(cpu, true);
}

/// FX29: set I to the address of the sprite for the digit in VX
pub fn setIToFont(cpu: *Cpu, decoded: Decoded.Int) void {
    const x, _ = Decoded.fromInt(decoded).xnn;
    const val: u4 = @truncate(cpu.v[x]);
    cpu.i = 5 * @as(u8, val);
    cont(cpu, true);
}

/// FX33: store the binary-coded decimal version of the value of VX in I, I + 1, and I + 2
pub fn storeBcd(cpu: *Cpu, decoded: Decoded.Int) void {
    const x, _ = Decoded.fromInt(decoded).xnn;
    cpu.mem[cpu.i] = cpu.v[x] / 100;
    cpu.mem[cpu.i +% 1] = (cpu.v[x] / 10) % 10;
    cpu.mem[cpu.i +% 2] = cpu.v[x] % 10;
    @memset(cpu.code[cpu.i..][0..2], .{ .func = &tail.decode, .decoded = undefined });
    cont(cpu, true);
}

/// FX55: store registers [V0, VX] in memory starting at I; set I to I + X + 1
pub fn store(cpu: *Cpu, decoded: Decoded.Int) void {
    const x, _ = Decoded.fromInt(decoded).xnn;
    @memcpy(cpu.mem[cpu.i..][0 .. x + 1], cpu.v[0 .. x + 1]);
    @memset(cpu.code[cpu.i..][0 .. x + 1], .{ .func = &tail.decode, .decoded = undefined });
    cpu.i = cpu.i + x + 1;
    cont(cpu, true);
}

/// FX65: load values from memory starting at I into registers [V0, VX]; set I to I + X + 1
pub fn load(cpu: *Cpu, decoded: Decoded.Int) void {
    const x, _ = Decoded.fromInt(decoded).xnn;
    @memcpy(cpu.v[0 .. x + 1], cpu.mem[cpu.i .. cpu.i + x + 1]);
    cpu.i = cpu.i + x + 1;
    cont(cpu, true);
}

/// FX75: store registers [V0, VX] in flags. X < 8
pub fn storeFlags(cpu: *Cpu, decoded: Decoded.Int) void {
    _ = decoded;
    std.debug.panic("storeFlags at {x:0>3}", .{cpu.pc});
}

/// FX75: load flags into [V0, VX]. X < 8
pub fn loadFlags(cpu: *Cpu, decoded: Decoded.Int) void {
    _ = decoded;
    std.debug.panic("loadFlags at {x:0>3}", .{cpu.pc});
}

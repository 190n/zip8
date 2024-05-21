const std = @import("std");

const tail = @import("./tail.zig");
const Cpu = tail.Cpu;
const Inst = tail.Inst;

inline fn cont(cpu: *Cpu, pc: [*]Inst, i: [*]u8, comptime inc_by_2: bool) void {
    if (cpu.instructions == 0) {
        @setCold(true);
        cpu.pc = @intCast((@intFromPtr(pc) - @intFromPtr(&cpu.code)) / @sizeOf(Inst));
        cpu.i = @intCast((@intFromPtr(i) - @intFromPtr(&cpu.mem)) / @sizeOf(u8));
        return;
    }
    cpu.instructions -= 1;
    const new_pc = if (inc_by_2) pc + 2 else pc;
    const next = new_pc[0];
    @call(.always_tail, tail.all_functions[@intFromEnum(next)], .{ cpu, next.toInt(), new_pc, i });
}

inline fn invalidate(cpu: *Cpu, mem_slice: []const u8) void {
    const i_n = (@intFromPtr(mem_slice.ptr) - @intFromPtr(&cpu.mem)) / @sizeOf(u8);
    // memory writes to address X may invalidate the instruction at address X, or at address X-1
    // so our range to invalidate is from i-1 to i+len
    @memset(
        cpu.code[i_n - 1 ..][0 .. mem_slice.len + 1],
        .{ .decode = {} },
    );
}

/// 00E0: clear the screen
pub fn clear(cpu: *Cpu, inst: Inst.Int, pc: [*]Inst, i: [*]u8) void {
    _ = Inst.fromInt(inst).clear;
    @memset(&cpu.display, 0);
    cont(cpu, pc, i, true);
}

/// 00EE: return
pub fn ret(cpu: *Cpu, inst: Inst.Int, pc: [*]Inst, i: [*]u8) void {
    _ = pc;
    _ = Inst.fromInt(inst).ret;
    const new_pc = cpu.stack.popOrNull() orelse @panic("empty stack");
    cont(cpu, new_pc, i, false);
}

/// 1NNN: jump to NNN
pub fn jump(cpu: *Cpu, inst: Inst.Int, pc: [*]Inst, i: [*]u8) void {
    _ = pc;
    const new_pc = &cpu.code[Inst.fromInt(inst).jump];
    cont(cpu, @ptrCast(new_pc), i, false);
}

/// 2NNN: call address NNN
pub fn call(cpu: *Cpu, inst: Inst.Int, pc: [*]Inst, i: [*]u8) void {
    cpu.stack.append(pc + 2) catch @panic("full stack");
    const new_pc = &cpu.code[Inst.fromInt(inst).call];
    cont(cpu, @ptrCast(new_pc), i, false);
}

/// 3XNN: skip next instruction if VX == NN
pub fn skipIfEqual(cpu: *Cpu, inst: Inst.Int, pc: [*]Inst, i: [*]u8) void {
    const x, const nn = Inst.fromInt(inst).skip_if_equal;
    const new_pc = if (cpu.v[x] == nn) pc + 4 else pc + 2;
    cont(cpu, new_pc, i, false);
}

/// 4XNN: skip next instruction if VX != NN
pub fn skipIfNotEqual(cpu: *Cpu, inst: Inst.Int, pc: [*]Inst, i: [*]u8) void {
    const x, const nn = Inst.fromInt(inst).skip_if_not_equal;
    const new_pc = if (cpu.v[x] != nn) pc + 4 else pc + 2;
    cont(cpu, new_pc, i, false);
}

/// 5XY0: skip next instruction if VX == VY
pub fn skipIfRegistersEqual(cpu: *Cpu, inst: Inst.Int, pc: [*]Inst, i: [*]u8) void {
    const x, const y = Inst.fromInt(inst).skip_if_registers_equal;
    const new_pc = if (cpu.v[x] == cpu.v[y]) pc + 4 else pc + 2;
    cont(cpu, new_pc, i, false);
}

/// 6XNN: set VX to NN
pub fn setRegister(cpu: *Cpu, inst: Inst.Int, pc: [*]Inst, i: [*]u8) void {
    const x, const nn = Inst.fromInt(inst).set_register;
    cpu.v[x] = nn;
    cont(cpu, pc, i, true);
}

/// 7XNN: add NN to VX without carry
pub fn addImmediate(cpu: *Cpu, inst: Inst.Int, pc: [*]Inst, i: [*]u8) void {
    const x, const nn = Inst.fromInt(inst).add_immediate;
    cpu.v[x] +%= nn;
    cont(cpu, pc, i, true);
}

/// 8XY0: set VX to VY
pub fn setRegisterToRegister(cpu: *Cpu, inst: Inst.Int, pc: [*]Inst, i: [*]u8) void {
    const x, const y = Inst.fromInt(inst).set_register_to_register;
    cpu.v[x] = cpu.v[y];
    cont(cpu, pc, i, true);
}

/// 8XY1: set VX to VX | VY
pub fn bitwiseOr(cpu: *Cpu, inst: Inst.Int, pc: [*]Inst, i: [*]u8) void {
    const x, const y = Inst.fromInt(inst).bitwise_or;
    cpu.v[x] |= cpu.v[y];
    cont(cpu, pc, i, true);
}

/// 8XY2: set VX to VX & VY
pub fn bitwiseAnd(cpu: *Cpu, inst: Inst.Int, pc: [*]Inst, i: [*]u8) void {
    const x, const y = Inst.fromInt(inst).bitwise_and;
    cpu.v[x] &= cpu.v[y];
    cont(cpu, pc, i, true);
}

/// 8XY3: set VX to VX ^ VY
pub fn bitwiseXor(cpu: *Cpu, inst: Inst.Int, pc: [*]Inst, i: [*]u8) void {
    const x, const y = Inst.fromInt(inst).bitwise_xor;
    cpu.v[x] ^= cpu.v[y];
    cont(cpu, pc, i, true);
}

/// 8XY4: set VX to VX + VY; set VF to 1 if carry occurred, 0 otherwise
pub fn addRegisters(cpu: *Cpu, inst: Inst.Int, pc: [*]Inst, i: [*]u8) void {
    const x, const y = Inst.fromInt(inst).add_registers;
    cpu.v[x], cpu.v[0xF] = @addWithOverflow(cpu.v[x], cpu.v[y]);
    cont(cpu, pc, i, true);
}

/// 8XY5: set VX to VX - VY; set VF to 0 if borrow occurred, 1 otherwise
pub fn subRegisters(cpu: *Cpu, inst: Inst.Int, pc: [*]Inst, i: [*]u8) void {
    const x, const y = Inst.fromInt(inst).sub_registers;
    cpu.v[x], const overflow = @subWithOverflow(cpu.v[x], cpu.v[y]);
    cpu.v[0xF] = ~overflow;
    cont(cpu, pc, i, true);
}

/// 8XY6: set VX to VY >> 1, set VF to the former least significant bit of VY
pub fn shiftRight(cpu: *Cpu, inst: Inst.Int, pc: [*]Inst, i: [*]u8) void {
    const x, const y = Inst.fromInt(inst).shift_right;
    cpu.v[0xF] = cpu.v[y] & 1;
    cpu.v[x] = cpu.v[y] >> 1;
    cont(cpu, pc, i, true);
}

/// 8XY7: set VX to VY - VX; set VF to 0 if borrow occurred, 1 otherwise
pub fn subRegistersReverse(cpu: *Cpu, inst: Inst.Int, pc: [*]Inst, i: [*]u8) void {
    const x, const y = Inst.fromInt(inst).sub_registers_reverse;
    cpu.v[x], const overflow = @subWithOverflow(cpu.v[y], cpu.v[x]);
    cpu.v[0xF] = ~overflow;
    cont(cpu, pc, i, true);
}

/// 8XYE: set VX to VY << 1, set VF to the former most significant bit of VY
pub fn shiftLeft(cpu: *Cpu, inst: Inst.Int, pc: [*]Inst, i: [*]u8) void {
    const x, const y = Inst.fromInt(inst).shift_left;
    cpu.v[0xF] = (cpu.v[y] >> 7) & 1;
    cpu.v[x] = cpu.v[y] << 1;
    cont(cpu, pc, i, true);
}

/// 9XY0: skip next instruction if VX != VY
pub fn skipIfRegistersNotEqual(cpu: *Cpu, inst: Inst.Int, pc: [*]Inst, i: [*]u8) void {
    const x, const y = Inst.fromInt(inst).skip_if_registers_not_equal;
    const new_pc = if (cpu.v[x] != cpu.v[y]) pc + 4 else pc + 2;
    cont(cpu, new_pc, i, false);
}

/// ANNN: set I to NNN
pub fn setI(cpu: *Cpu, inst: Inst.Int, pc: [*]Inst, i: [*]u8) void {
    _ = i;
    const new_i = &cpu.mem[Inst.fromInt(inst).set_i];
    cont(cpu, pc, @ptrCast(new_i), true);
}

/// BNNN: jump to NNN + V0
pub fn jumpV0(cpu: *Cpu, inst: Inst.Int, pc: [*]Inst, i: [*]u8) void {
    _ = pc;
    const new_pc = &cpu.code[Inst.fromInt(inst).jump_v0 + cpu.v[0]];
    cont(cpu, @ptrCast(new_pc), i, false);
}

/// CXNN: set VX to rand() & NN
pub fn random(cpu: *Cpu, inst: Inst.Int, pc: [*]Inst, i: [*]u8) void {
    const x, const nn = Inst.fromInt(inst).random;
    const byte = cpu.random.random().int(u8);
    cpu.v[x] = byte & nn;
    cont(cpu, pc, i, true);
}

/// DXYN: draw an 8xN sprite from memory starting at I at (VX, VY); set VF to 1 if any pixel was
/// turned off, 0 otherwise
pub fn draw(cpu: *Cpu, inst: Inst.Int, pc: [*]Inst, i: [*]u8) void {
    const x_reg, const y_reg, const n = Inst.fromInt(inst).draw;
    const x: u16 = cpu.v[x_reg] % 64;
    const y: u16 = cpu.v[y_reg] % 32;
    var intersect: u8 = 0;
    for (0..@min(n, 32 - y)) |row| {
        const left = @bitReverse(i[row]) << @truncate(x % 8);
        const right: u8 = @truncate(@as(u16, @bitReverse(i[row])) >> @truncate(8 - (x % 8)));
        const index = (64 * (y + row) + x) / 8;
        intersect |= (cpu.display[index] & left);
        cpu.display[index] ^= left;
        if (x < 56) {
            intersect |= (cpu.display[index + 1] & right);
            cpu.display[index + 1] ^= right;
        }
    }
    cpu.v[0xF] = @intFromBool(intersect != 0);
    cont(cpu, pc, i, true);
}

/// EX9E: skip next instruction if the key in VX is pressed
pub fn skipIfPressed(cpu: *Cpu, inst: Inst.Int, pc: [*]Inst, i: [*]u8) void {
    _ = i;
    _ = pc;
    _ = inst;
    std.debug.panic("skipIfPressed at {x:0>3}", .{cpu.pc});
}

/// EXA1: skip next instruction if the key in VX is not pressed
pub fn skipIfNotPressed(cpu: *Cpu, inst: Inst.Int, pc: [*]Inst, i: [*]u8) void {
    _ = i;
    _ = pc;
    _ = inst;
    std.debug.panic("skipIfNotPressed at {x:0>3}", .{cpu.pc});
}

/// FX07: store the value of the delay timer in VX
pub fn readDt(cpu: *Cpu, inst: Inst.Int, pc: [*]Inst, i: [*]u8) void {
    const x = Inst.fromInt(inst).read_dt;
    cpu.v[x] = cpu.dt;
    cont(cpu, pc, i, true);
}

/// FX0A: wait until any key is pressed, then store the key that was pressed in VX
pub fn waitForKey(cpu: *Cpu, inst: Inst.Int, pc: [*]Inst, i: [*]u8) void {
    _ = i;
    _ = pc;
    _ = inst;
    std.debug.panic("waitForKey at {x:0>3}", .{cpu.pc});
}

/// FX15: set the delay timer to the value of VX
pub fn setDt(cpu: *Cpu, inst: Inst.Int, pc: [*]Inst, i: [*]u8) void {
    const x = Inst.fromInt(inst).set_dt;
    cpu.dt = cpu.v[x];
    cont(cpu, pc, i, true);
}

/// FX18: set the sound timer to the value of VX
pub fn setSt(cpu: *Cpu, inst: Inst.Int, pc: [*]Inst, i: [*]u8) void {
    const x = Inst.fromInt(inst).set_st;
    cpu.st = cpu.v[x];
    cont(cpu, pc, i, true);
}

/// FX1E: increment I by the value of VX
pub fn incrementI(cpu: *Cpu, inst: Inst.Int, pc: [*]Inst, i: [*]u8) void {
    const x = Inst.fromInt(inst).increment_i;
    const new_i = i + cpu.v[x];
    cont(cpu, pc, new_i, true);
}

/// FX29: set I to the address of the sprite for the digit in VX
pub fn setIToFont(cpu: *Cpu, inst: Inst.Int, pc: [*]Inst, i: [*]u8) void {
    _ = i;
    const x = Inst.fromInt(inst).set_i_to_font;
    const val: u4 = @truncate(cpu.v[x]);
    const new_i = &cpu.mem[5 * @as(u8, val)];
    cont(cpu, pc, @ptrCast(new_i), true);
}

/// FX33: store the binary-coded decimal version of the value of VX in I, I + 1, and I + 2
pub fn storeBcd(cpu: *Cpu, inst: Inst.Int, pc: [*]Inst, i: [*]u8) void {
    const x = Inst.fromInt(inst).store_bcd;
    i[0] = cpu.v[x] / 100;
    i[1] = (cpu.v[x] / 10) % 10;
    i[2] = cpu.v[x] % 10;
    invalidate(cpu, i[0..3]);
    cont(cpu, pc, i, true);
}

/// FX55: store registers [V0, VX] in memory starting at I; set I to I + X + 1
pub fn store(cpu: *Cpu, inst: Inst.Int, pc: [*]Inst, i: [*]u8) void {
    const x: u8 = Inst.fromInt(inst).store;
    @memcpy(i[0 .. x + 1], cpu.v[0 .. x + 1]);
    invalidate(cpu, i[0 .. x + 1]);
    cont(cpu, pc, i + x + 1, true);
}

/// FX65: load values from memory starting at I into registers [V0, VX]; set I to I + X + 1
pub fn load(cpu: *Cpu, inst: Inst.Int, pc: [*]Inst, i: [*]u8) void {
    const x: u8 = Inst.fromInt(inst).load;
    @memcpy(cpu.v[0 .. x + 1], i[0 .. x + 1]);
    cont(cpu, pc, i + x + 1, true);
}

/// FX75: store registers [V0, VX] in flags. X < 8
pub fn storeFlags(cpu: *Cpu, inst: Inst.Int, pc: [*]Inst, i: [*]u8) void {
    _ = i;
    _ = pc;
    _ = inst;
    std.debug.panic("storeFlags at {x:0>3}", .{cpu.pc});
}

/// FX75: load flags into [V0, VX]. X < 8
pub fn loadFlags(cpu: *Cpu, inst: Inst.Int, pc: [*]Inst, i: [*]u8) void {
    _ = i;
    _ = pc;
    _ = inst;
    std.debug.panic("loadFlags at {x:0>3}", .{cpu.pc});
}

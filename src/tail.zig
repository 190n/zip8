const std = @import("std");

const font_data = @import("./font.zig").font_data;

pub const Cpu = struct {
    v: [16]u8 = .{0} ** 16,
    i: u12 = 0,
    pc: u12 = 0x200,
    stack: std.BoundedArray(u12, 16) = .{},
    display: [64 * 32 / 8]u8,
    mem: [4096]u8,
    code: [4096]Inst,
    instructions: usize = 0,

    pub fn init(rom: []const u8) Cpu {
        var cpu = Cpu{
            .display = undefined,
            .mem = undefined,
            .code = undefined,
        };
        @memcpy(cpu.mem[0..font_data.len], font_data);
        @memset(cpu.mem[font_data.len..0x200], 0);
        @memcpy(cpu.mem[0x200..][0..rom.len], rom);
        @memset(cpu.mem[0x200 + rom.len ..], 0);
        @memset(&cpu.display, 0);
        @memset(&cpu.code, .{ .func = &decode, .decoded = undefined });
        return cpu;
    }

    pub fn run(self: *Cpu, instructions: usize) void {
        self.instructions = instructions;
        self.code[self.pc].func(self, self.code[self.pc].decoded);
    }
};

const GadgetFunc = *const fn (*Cpu, Decoded) callconv(.Unspecified) void;

pub const Decoded = union {
    xy: [2]u4,
    xnn: struct { u4, u8 },
    nnn: u12,
    xyn: [3]u4,

    fn from(opcode: u16, cpu: *Cpu, which: enum { xy, xnn, nnn, xyn }) Decoded {
        _ = cpu; // autofix
        switch (which) {
            .xy => {
                const x: u4 = @truncate(opcode >> 8);
                const y: u4 = @truncate(opcode >> 4);
                return Decoded{ .xy = .{ x, y } };
            },
            .xnn => {
                const x: u4 = @truncate(opcode >> 8);
                const nn: u8 = @truncate(opcode);
                return Decoded{ .xnn = .{ x, nn } };
            },
            .nnn => return Decoded{ .nnn = @truncate(opcode) },
            .xyn => {
                const x: u4 = @truncate(opcode >> 8);
                const y: u4 = @truncate(opcode >> 4);
                const n: u4 = @truncate(opcode);
                return Decoded{ .xyn = .{ x, y, n } };
            },
        }
    }
};

const Inst = struct {
    func: GadgetFunc,
    decoded: Decoded,
};

fn decode(cpu: *Cpu, decoded: Decoded) void {
    _ = decoded;

    const opcode = std.mem.readInt(u16, cpu.mem[cpu.pc..][0..2], .big);
    const inst: Inst = switch (@as(u4, @truncate(opcode >> 12))) {
        0x0 => switch (opcode & 0xff) {
            0xE0 => .{ .func = &funcs.clear, .decoded = undefined },
            0xEE => .{ .func = &funcs.ret, .decoded = undefined },
            else => .{ .func = &invalid, .decoded = undefined },
        },
        0x1 => .{ .func = &funcs.jump, .decoded = Decoded.from(opcode, cpu, .nnn) },
        0x2 => .{ .func = &funcs.call, .decoded = Decoded.from(opcode, cpu, .nnn) },
        0x3 => .{ .func = &funcs.skipIfEqual, .decoded = Decoded.from(opcode, cpu, .xnn) },
        0x4 => .{ .func = &funcs.skipIfNotEqual, .decoded = Decoded.from(opcode, cpu, .xnn) },
        0x5 => switch (opcode & 0xf) {
            0x0 => .{ .func = &funcs.skipIfRegistersEqual, .decoded = Decoded.from(opcode, cpu, .xy) },
            else => .{ .func = &invalid, .decoded = undefined },
        },
        0x6 => .{ .func = &funcs.setRegister, .decoded = Decoded.from(opcode, cpu, .xnn) },
        0x7 => .{ .func = &funcs.addImmediate, .decoded = Decoded.from(opcode, cpu, .xnn) },
        0x8 => .{
            .func = switch (@as(u4, @truncate(opcode))) {
                0x0 => &funcs.setRegisterToRegister,
                0x1 => &funcs.bitwiseOr,
                0x2 => &funcs.bitwiseAnd,
                0x3 => &funcs.bitwiseXor,
                0x4 => &funcs.addRegisters,
                0x5 => &funcs.subRegisters,
                0x6 => &funcs.shiftRight,
                0x7 => &funcs.subRegistersReverse,
                0xE => &funcs.shiftLeft,
                else => &invalid,
            },
            .decoded = Decoded.from(opcode, cpu, .xy),
        },
        0x9 => switch (opcode & 0xf) {
            0x0 => .{ .func = &funcs.skipIfRegistersNotEqual, .decoded = Decoded.from(opcode, cpu, .xy) },
            else => .{ .func = &invalid, .decoded = undefined },
        },
        0xA => .{ .func = &funcs.setI, .decoded = Decoded.from(opcode, cpu, .nnn) },
        0xB => .{ .func = &funcs.jumpV0, .decoded = Decoded.from(opcode, cpu, .nnn) },
        0xC => .{ .func = &funcs.random, .decoded = Decoded.from(opcode, cpu, .xnn) },
        0xD => .{ .func = &funcs.draw, .decoded = Decoded.from(opcode, cpu, .xyn) },
        0xE => switch (opcode & 0xff) {
            0x9E => .{ .func = &funcs.skipIfPressed, .decoded = Decoded.from(opcode, cpu, .xnn) },
            0xA1 => .{ .func = &funcs.skipIfNotPressed, .decoded = Decoded.from(opcode, cpu, .xnn) },
            else => .{ .func = &invalid, .decoded = undefined },
        },
        0xF => .{
            .func = switch (opcode & 0xff) {
                0x07 => &funcs.readDt,
                0x0A => &funcs.waitForKey,
                0x15 => &funcs.setDt,
                0x18 => &funcs.setSt,
                0x1E => &funcs.incrementI,
                0x29 => &funcs.setIToFont,
                0x33 => &funcs.storeBcd,
                0x55 => &funcs.store,
                0x65 => &funcs.load,
                0x75 => &funcs.storeFlags,
                0x85 => &funcs.loadFlags,
                else => &invalid,
            },
            .decoded = Decoded.from(opcode, cpu, .xnn),
        },
    };
    cpu.code[cpu.pc] = inst;
    @call(.always_tail, inst.func, .{ cpu, inst.decoded });
}

fn invalid(cpu: *Cpu, decoded: Decoded) void {
    _ = decoded; // autofix
    std.debug.panic(
        "invalid instruction: {x:0>4}",
        .{std.mem.readInt(u16, cpu.mem[cpu.pc..][0..2], .big)},
    );
}

const funcs = @import("./tailfuncs.zig");

// export fn inc_stub(cpu: *Cpu, decoded: Decoded, pc: u16) void {
//     // const decoded: Decoded = @bitCast(decoded_i);
//     decoded.xy[0].*, cpu.v[0xf] = @addWithOverflow(decoded.xy[0].*, decoded.xy[1].*);
//     const next = cpu.code[cpu.pc + 2];
//     @call(.always_tail, next.func, .{ cpu, next.decoded, pc + 2 });
// }

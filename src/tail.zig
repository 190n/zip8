const std = @import("std");

const font_data = @import("./font.zig").font_data;
const tailfuncs = @import("./tailfuncs.zig");

pub const Cpu = struct {
    v: [16]u8 = .{0} ** 16,
    i: u12 = 0,
    pc: u12 = 0x200,
    stack: std.BoundedArray(u12, 16) = .{},
    display: [64 * 32 / 8]u8,
    mem: [4096]u8,
    code: [4096]Inst,
    instructions: u16 = 0,
    random: std.rand.DefaultPrng,

    pub fn init(rom: []const u8) Cpu {
        var cpu = Cpu{
            .display = undefined,
            .mem = undefined,
            .code = undefined,
            .random = std.rand.DefaultPrng.init(blk: {
                var buf: u64 = undefined;
                std.posix.getrandom(std.mem.asBytes(&buf)) catch unreachable;
                break :blk buf;
            }),
        };
        @memcpy(cpu.mem[0..font_data.len], font_data);
        @memset(cpu.mem[font_data.len..0x200], 0);
        @memcpy(cpu.mem[0x200..][0..rom.len], rom);
        @memset(cpu.mem[0x200 + rom.len ..], 0);
        @memset(&cpu.display, 0);
        @memset(&cpu.code, .{ .func = &decode, .decoded = undefined });
        return cpu;
    }

    pub fn run(self: *Cpu, instructions: u16) void {
        self.instructions = instructions;
        self.code[self.pc].func(self, self.code[self.pc].decoded.toInt());
    }
};

const GadgetFunc = *const fn (*Cpu, u32) void;

pub const Decoded = union {
    xy: [2]u4,
    xnn: struct { u4, u8 },
    nnn: u12,
    xyn: [3]u4,

    pub const Int = @Type(.{ .Int = .{
        .signedness = .unsigned,
        .bits = 8 * @sizeOf(Decoded),
    } });

    fn decode(opcode: u16, which: enum { xy, xnn, nnn, xyn }) Decoded {
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

    pub inline fn fromInt(x: Int) Decoded {
        return @as(*const Decoded, @ptrCast(&x)).*;
    }

    pub inline fn toInt(self: Decoded) Int {
        return @as(*align(@alignOf(Decoded)) const Int, @ptrCast(&self)).*;
    }
};

const Inst = struct {
    func: GadgetFunc,
    decoded: Decoded,
};

pub fn decode(cpu: *Cpu, _: Decoded.Int) void {
    const opcode = std.mem.readInt(u16, cpu.mem[cpu.pc..][0..2], .big);
    const inst: Inst = switch (@as(u4, @truncate(opcode >> 12))) {
        0x0 => switch (opcode & 0xff) {
            0xE0 => .{ .func = &tailfuncs.clear, .decoded = undefined },
            0xEE => .{ .func = &tailfuncs.ret, .decoded = undefined },
            else => .{ .func = &invalid, .decoded = undefined },
        },
        0x1 => .{ .func = &tailfuncs.jump, .decoded = Decoded.decode(opcode, .nnn) },
        0x2 => .{ .func = &tailfuncs.call, .decoded = Decoded.decode(opcode, .nnn) },
        0x3 => .{ .func = &tailfuncs.skipIfEqual, .decoded = Decoded.decode(opcode, .xnn) },
        0x4 => .{ .func = &tailfuncs.skipIfNotEqual, .decoded = Decoded.decode(opcode, .xnn) },
        0x5 => switch (opcode & 0xf) {
            0x0 => .{ .func = &tailfuncs.skipIfRegistersEqual, .decoded = Decoded.decode(opcode, .xy) },
            else => .{ .func = &invalid, .decoded = undefined },
        },
        0x6 => .{ .func = &tailfuncs.setRegister, .decoded = Decoded.decode(opcode, .xnn) },
        0x7 => .{ .func = &tailfuncs.addImmediate, .decoded = Decoded.decode(opcode, .xnn) },
        0x8 => .{
            .func = switch (@as(u4, @truncate(opcode))) {
                0x0 => &tailfuncs.setRegisterToRegister,
                0x1 => &tailfuncs.bitwiseOr,
                0x2 => &tailfuncs.bitwiseAnd,
                0x3 => &tailfuncs.bitwiseXor,
                0x4 => &tailfuncs.addRegisters,
                0x5 => &tailfuncs.subRegisters,
                0x6 => &tailfuncs.shiftRight,
                0x7 => &tailfuncs.subRegistersReverse,
                0xE => &tailfuncs.shiftLeft,
                else => &invalid,
            },
            .decoded = Decoded.decode(opcode, .xy),
        },
        0x9 => switch (opcode & 0xf) {
            0x0 => .{ .func = &tailfuncs.skipIfRegistersNotEqual, .decoded = Decoded.decode(opcode, .xy) },
            else => .{ .func = &invalid, .decoded = undefined },
        },
        0xA => .{ .func = &tailfuncs.setI, .decoded = Decoded.decode(opcode, .nnn) },
        0xB => .{ .func = &tailfuncs.jumpV0, .decoded = Decoded.decode(opcode, .nnn) },
        0xC => .{ .func = &tailfuncs.random, .decoded = Decoded.decode(opcode, .xnn) },
        0xD => .{ .func = &tailfuncs.draw, .decoded = Decoded.decode(opcode, .xyn) },
        0xE => switch (opcode & 0xff) {
            0x9E => .{ .func = &tailfuncs.skipIfPressed, .decoded = Decoded.decode(opcode, .xnn) },
            0xA1 => .{ .func = &tailfuncs.skipIfNotPressed, .decoded = Decoded.decode(opcode, .xnn) },
            else => .{ .func = &invalid, .decoded = undefined },
        },
        0xF => .{
            .func = switch (opcode & 0xff) {
                0x07 => &tailfuncs.readDt,
                0x0A => &tailfuncs.waitForKey,
                0x15 => &tailfuncs.setDt,
                0x18 => &tailfuncs.setSt,
                0x1E => &tailfuncs.incrementI,
                0x29 => &tailfuncs.setIToFont,
                0x33 => &tailfuncs.storeBcd,
                0x55 => &tailfuncs.store,
                0x65 => &tailfuncs.load,
                0x75 => &tailfuncs.storeFlags,
                0x85 => &tailfuncs.loadFlags,
                else => &invalid,
            },
            .decoded = Decoded.decode(opcode, .xnn),
        },
    };
    cpu.code[cpu.pc] = inst;
    @call(.always_tail, inst.func, .{ cpu, inst.decoded.toInt() });
}

fn invalid(cpu: *Cpu, _: Decoded.Int) void {
    std.debug.panic(
        "invalid instruction: {x:0>4}",
        .{std.mem.readInt(u16, cpu.mem[cpu.pc..][0..2], .big)},
    );
}

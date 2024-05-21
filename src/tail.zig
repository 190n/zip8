const std = @import("std");

const font_data = @import("./font.zig").font_data;
const tailfuncs = @import("./tailfuncs.zig");

pub const Cpu = struct {
    v: [16]u8 = .{0} ** 16,
    i: u12 = 0,
    pc: u12 = 0x200,
    stack: std.BoundedArray([*]Inst, 16) = .{},
    display: [64 * 32 / 8]u8,
    mem: [4096]u8,
    code: [4096]Inst,
    instructions: u16 = 0,
    dt: u8 = 0,
    st: u8 = 0,
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
        @memset(&cpu.code, .{ .decode = {} });
        return cpu;
    }

    pub fn run(self: *Cpu, instructions: u16) void {
        self.instructions = instructions;
        all_functions[@intFromEnum(self.code[self.pc])](
            self,
            self.code[self.pc].toInt(),
            self.code[self.pc..].ptr,
            self.mem[self.i..].ptr,
        );
    }

    pub fn timerTick(self: *Cpu) void {
        self.dt -|= 1;
        self.st -|= 1;
    }
};

const GadgetFunc = *const fn (*Cpu, Inst.Int, [*]Inst, [*]u8) void;

pub const InstTag = enum(u8) {
    /// this instruction needs to be decoded
    decode = 0,
    /// this instruction has been decoded and is known to be invalid
    invalid = 1,

    // real opcodes follow
    clear = 2,
    ret,
    jump,
    call,
    skip_if_equal,
    skip_if_not_equal,
    skip_if_registers_equal,
    set_register,
    add_immediate,
    set_register_to_register,
    bitwise_or,
    bitwise_and,
    bitwise_xor,
    add_registers,
    sub_registers,
    shift_right,
    sub_registers_reverse,
    shift_left,
    skip_if_registers_not_equal,
    set_i,
    jump_v0,
    random,
    draw,
    skip_if_pressed,
    skip_if_not_pressed,
    read_dt,
    wait_for_key,
    set_dt,
    set_st,
    increment_i,
    set_i_to_font,
    store_bcd,
    store,
    load,
    store_flags,
    load_flags,
};

pub const all_functions = blk: {
    var functions: [38]GadgetFunc = undefined;
    for (&functions, 0..) |*f, i| {
        f.* = switch (i) {
            0 => &decode,
            1 => &invalid,
            else => func: {
                const tag: InstTag = @enumFromInt(i);
                // snake to camel case
                var tag_name = @tagName(tag).*;
                var underscores = 0;
                for (&tag_name, 0..) |*c, tag_name_index| {
                    if (c.* == '_') {
                        underscores += 1;
                        c.* = tag_name[tag_name_index + 1] - ('a' - 'A');
                        std.mem.copyForwards(
                            u8,
                            tag_name[tag_name_index + 1 .. tag_name.len - 1],
                            tag_name[tag_name_index + 2 ..],
                        );
                    }
                }
                break :func &@field(tailfuncs, tag_name[0 .. tag_name.len - underscores]);
            },
        };
    }
    break :blk functions;
};

pub const Inst = union(InstTag) {
    const Nnn = u12;
    const Xnn = struct { u4, u8 };
    const Xy = [2]u4;
    const Xyn = [3]u4;
    const X = u4;

    decode: void,
    invalid: u16,
    clear: void,
    ret: void,
    jump: Nnn,
    call: Nnn,
    skip_if_equal: Xnn,
    skip_if_not_equal: Xnn,
    skip_if_registers_equal: Xy,
    set_register: Xnn,
    add_immediate: Xnn,
    set_register_to_register: Xy,
    bitwise_or: Xy,
    bitwise_and: Xy,
    bitwise_xor: Xy,
    add_registers: Xy,
    sub_registers: Xy,
    shift_right: Xy,
    sub_registers_reverse: Xy,
    shift_left: Xy,
    skip_if_registers_not_equal: Xy,
    set_i: Nnn,
    jump_v0: Nnn,
    random: Xnn,
    draw: Xyn,
    skip_if_pressed: X,
    skip_if_not_pressed: X,
    read_dt: X,
    wait_for_key: X,
    set_dt: X,
    set_st: X,
    increment_i: X,
    set_i_to_font: X,
    store_bcd: X,
    store: X,
    load: X,
    store_flags: X,
    load_flags: X,

    pub const Int = @Type(.{ .Int = .{
        .signedness = .unsigned,
        .bits = 8 * @sizeOf(Inst),
    } });

    fn extract(opcode: u16, comptime Which: type) Which {
        switch (Which) {
            void => {},
            Xy => {
                const x: u4 = @truncate(opcode >> 8);
                const y: u4 = @truncate(opcode >> 4);
                return .{ x, y };
            },
            Xnn => {
                const x: u4 = @truncate(opcode >> 8);
                const nn: u8 = @truncate(opcode);
                return .{ x, nn };
            },
            Nnn => return @truncate(opcode),
            Xyn => {
                const x: u4 = @truncate(opcode >> 8);
                const y: u4 = @truncate(opcode >> 4);
                const n: u4 = @truncate(opcode);
                return .{ x, y, n };
            },
            X => return @truncate(opcode >> 8),
            else => unreachable,
        }
    }

    pub inline fn fromInt(x: Int) Inst {
        return @as(*const Inst, @ptrCast(&x)).*;
    }

    pub inline fn toInt(self: Inst) Int {
        return @as(*align(@alignOf(Inst)) const Int, @ptrCast(&self)).*;
    }
};

pub fn decode(cpu: *Cpu, _: Inst.Int, pc: [*]Inst, i: [*]u8) void {
    const pc_n = (@intFromPtr(pc) - @intFromPtr(&cpu.code)) / @sizeOf(Inst);
    const opcode = std.mem.readInt(u16, cpu.mem[pc_n..][0..2], .big);
    const inst: Inst = switch (@as(u4, @truncate(opcode >> 12))) {
        0x0 => switch (opcode & 0xff) {
            0xE0 => .{ .clear = {} },
            0xEE => .{ .ret = {} },
            else => .{ .invalid = opcode },
        },
        0x1 => .{ .jump = Inst.extract(opcode, Inst.Nnn) },
        0x2 => .{ .call = Inst.extract(opcode, Inst.Nnn) },
        0x3 => .{ .skip_if_equal = Inst.extract(opcode, Inst.Xnn) },
        0x4 => .{ .skip_if_not_equal = Inst.extract(opcode, Inst.Xnn) },
        0x5 => switch (opcode & 0xf) {
            0x0 => .{ .skip_if_registers_equal = Inst.extract(opcode, Inst.Xy) },
            else => .{ .invalid = opcode },
        },
        0x6 => .{ .set_register = Inst.extract(opcode, Inst.Xnn) },
        0x7 => .{ .add_immediate = Inst.extract(opcode, Inst.Xnn) },
        0x8 => switch (@as(u4, @truncate(opcode))) {
            inline else => |low| @unionInit(
                Inst,
                @tagName(switch (low) {
                    0x0 => InstTag.set_register_to_register,
                    0x1 => InstTag.bitwise_or,
                    0x2 => InstTag.bitwise_and,
                    0x3 => InstTag.bitwise_xor,
                    0x4 => InstTag.add_registers,
                    0x5 => InstTag.sub_registers,
                    0x6 => InstTag.shift_right,
                    0x7 => InstTag.sub_registers_reverse,
                    0xE => InstTag.shift_left,
                    else => InstTag.invalid,
                }),
                switch (low) {
                    0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0xE => Inst.extract(opcode, Inst.Xy),
                    else => opcode,
                },
            ),
        },
        0x9 => switch (opcode & 0xf) {
            0x0 => .{ .skip_if_registers_not_equal = Inst.extract(opcode, Inst.Xy) },
            else => .{ .invalid = opcode },
        },
        0xA => .{ .set_i = Inst.extract(opcode, Inst.Nnn) },
        0xB => .{ .jump_v0 = Inst.extract(opcode, Inst.Nnn) },
        0xC => .{ .random = Inst.extract(opcode, Inst.Xnn) },
        0xD => .{ .draw = Inst.extract(opcode, Inst.Xyn) },
        0xE => switch (opcode & 0xff) {
            0x9E => .{ .skip_if_pressed = Inst.extract(opcode, Inst.X) },
            0xA1 => .{ .skip_if_not_pressed = Inst.extract(opcode, Inst.X) },
            else => .{ .invalid = opcode },
        },
        0xF => switch (@as(u8, @truncate(opcode))) {
            inline else => |low| @unionInit(
                Inst,
                @tagName(switch (low) {
                    0x07 => InstTag.read_dt,
                    0x0A => InstTag.wait_for_key,
                    0x15 => InstTag.set_dt,
                    0x18 => InstTag.set_st,
                    0x1E => InstTag.increment_i,
                    0x29 => InstTag.set_i_to_font,
                    0x33 => InstTag.store_bcd,
                    0x55 => InstTag.store,
                    0x65 => InstTag.load,
                    0x75 => InstTag.store_flags,
                    0x85 => InstTag.load_flags,
                    else => InstTag.invalid,
                }),
                switch (low) {
                    0x07, 0x0A, 0x15, 0x18, 0x1E, 0x29, 0x33, 0x55, 0x65, 0x75, 0x85 => Inst.extract(opcode, Inst.X),
                    else => opcode,
                },
            ),
        },
    };
    pc[0] = inst;
    @call(.always_tail, all_functions[@intFromEnum(inst)], .{ cpu, inst.toInt(), pc, i });
}

fn invalid(cpu: *Cpu, inst: Inst.Int, pc: [*]Inst, i: [*]u8) void {
    _ = i;
    const pc_n = (@intFromPtr(pc) - @intFromPtr(&cpu.code)) / @sizeOf(Inst);
    std.debug.panic(
        "invalid instruction: {X:0>4} at 0x{X:0>3}",
        .{ Inst.fromInt(inst).invalid, pc_n },
    );
}

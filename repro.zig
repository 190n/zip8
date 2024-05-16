const std = @import("std");

const SideData = union {
    foo: u8,
    bar: u8,
};

const Inst = struct {
    func: Gadget,
    data: SideData,
};

const Emulator = struct {
    memory: [128]u8,
    code: [64]Inst,
    pc: u8 = 0,
};

const Gadget = *const fn (*Emulator, SideData) void;

fn foo(emulator: *Emulator, side_data: SideData) void {
    _ = emulator;
    std.log.info("foo {}", .{side_data.foo});
}

fn bar(emulator: *Emulator, side_data: SideData) void {
    _ = emulator;
    _ = side_data;
    @trap();
}

fn invalid(emulator: *Emulator, _: SideData) void {
    _ = emulator;
}

fn decode(emulator: *Emulator, _: SideData) void {
    const raw_instruction = std.mem.readInt(u16, emulator.memory[emulator.pc..][0..2], .big);
    const inst: Inst = switch ((raw_instruction >> 8) & 0xf) {
        0xf => .{ .func = &foo, .data = .{ .foo = @truncate(raw_instruction) } },
        0xb => .{ .func = &bar, .data = .{ .bar = @truncate(raw_instruction) } },
        else => .{ .func = &invalid, .data = undefined },
    };
    @call(.always_tail, inst.func, .{ emulator, inst.data });
}

pub fn main() void {
    var emulator = Emulator{
        .memory = undefined,
        .code = undefined,
    };
    @memset(&emulator.code, .{ .func = &decode, .data = undefined });
    const rom = [_]u8{ 0x0f, 0x23, 0x0b, 0x80 };
    @memcpy(emulator.memory[0..rom.len], &rom);
    emulator.code[emulator.pc].func(&emulator, emulator.code[emulator.pc].data);
}

const std = @import("std");

const Cpu = @import("./cpu.zig");
const build_options = @import("build_options");

fn cpuPtrCast(in: anytype) switch (@TypeOf(in)) {
    ?*anyopaque => *Cpu,
    ?*const anyopaque => *const Cpu,
    else => unreachable,
} {
    return @ptrCast(@alignCast(in.?));
}

export const ZIP8_ERR_ILLEGAL_OPCODE: u16 = @intFromError(error.IllegalOpcode);
export const ZIP8_ERR_STACK_OVERFLOW: u16 = @intFromError(error.StackOverflow);
export const ZIP8_ERR_BAD_RETURN: u16 = @intFromError(error.BadReturn);
export const ZIP8_ERR_PROGRAM_TOO_LONG: u16 = @intFromError(error.ProgramTooLong);
export const ZIP8_ERR_FLAG_OVERFLOW: u16 = @intFromError(error.FlagOverflow);

export fn zip8GetErrorName(err: u16) [*:0]const u8 {
    return @errorName(@errorFromInt(err));
}

export fn zip8CpuGetSize() usize {
    return @sizeOf(Cpu);
}

export fn zip8CpuInit(
    err: ?*u16,
    cpu: ?*anyopaque,
    program: ?[*]const u8,
    program_len: usize,
    seed: u64,
    flags: u64,
) c_int {
    // directly storing in the pointer breaks this on RP2040 for whatever reason
    // cpuPtrCast(cpu).* = Cpu.init(program.?[0..program_len], seed) catch |e| {
    Cpu.initInPlace(
        cpuPtrCast(cpu),
        program.?[0..program_len],
        seed,
        @bitCast(std.mem.nativeToLittle(u64, flags)),
    ) catch |e| {
        err.?.* = @intFromError(e);
        return 1;
    };
    return 0;
}

export fn zip8CpuCycle(err: ?*u16, cpu: ?*anyopaque) c_int {
    cpuPtrCast(cpu).cycle() catch |e| {
        err.?.* = @intFromError(e);
        return 1;
    };
    return 0;
}

export fn zip8CpuSetKeys(cpu: ?*anyopaque, keys: u16) void {
    var new_keys: [16]bool = undefined;
    for (&new_keys, 0..) |*key, i_usize| {
        const i: u4 = @intCast(i_usize);
        key.* = (keys >> i) & 1 != 0;
    }
    cpuPtrCast(cpu).setKeys(&new_keys);
}

export fn zip8CpuIsWaitingForKey(cpu: ?*const anyopaque) bool {
    return cpuPtrCast(cpu).next_key_register != null;
}

export fn zip8CpuTimerTick(cpu: ?*anyopaque) void {
    cpuPtrCast(cpu).timerTick();
}

export fn zip8CpuDisplayIsDirty(cpu: ?*const anyopaque) bool {
    return cpuPtrCast(cpu).display_dirty;
}

export fn zip8CpuSetDisplayNotDirty(cpu: ?*anyopaque) void {
    cpuPtrCast(cpu).display_dirty = false;
}

export fn zip8CpuGetDisplay(cpu: ?*const anyopaque) [*]const u8 {
    return &cpuPtrCast(cpu).display;
}

export fn zip8CpuGetInstruction(cpu: ?*const anyopaque) u16 {
    const mem: []const u8 = &cpuPtrCast(cpu).mem;
    const pc = cpuPtrCast(cpu).pc;
    const high = mem[pc];
    const low = mem[pc + 1];
    return (@as(u16, high) << 8) + low;
}

export fn zip8CpuGetProgramCounter(cpu: ?*const anyopaque) u16 {
    return cpuPtrCast(cpu).pc;
}

export fn zip8CpuGetFlags(cpu: ?*const anyopaque) u64 {
    return std.mem.nativeToLittle(u64, @as(u64, @bitCast(cpuPtrCast(cpu).flags)));
}

export fn zip8CpuFlagsAreDirty(cpu: ?*const anyopaque) bool {
    return cpuPtrCast(cpu).flags_dirty;
}

export fn zip8CpuSetFlagsNotDirty(cpu: ?*anyopaque) void {
    cpuPtrCast(cpu).flags_dirty = false;
}

comptime {
    if (build_options.experimental_render_hooks) {
        const render_hook_exports = struct {
            fn zip8CpuGetDrawBytes(cpu: ?*const anyopaque) callconv(.C) usize {
                return cpuPtrCast(cpu).draw_bytes_this_frame;
            }

            fn zip8CpuResetDrawBytes(cpu: ?*anyopaque) callconv(.C) void {
                cpuPtrCast(cpu).draw_bytes_this_frame = 0;
            }
        };

        @export(render_hook_exports.zip8CpuGetDrawBytes, .{ .name = "zip8CpuGetDrawBytes" });
        @export(render_hook_exports.zip8CpuResetDrawBytes, .{ .name = "zip8CpuResetDrawBytes" });
    }
}

comptime {
    if (@import("builtin").target.isWasm()) {
        const wasm_only_functions = struct {
            var buf: [65536]u8 = undefined;
            var fba = std.heap.FixedBufferAllocator.init(&buf);
            const allocator = fba.allocator();

            fn zip8CpuAlloc() callconv(.C) ?[*]u8 {
                return (allocator.alignedAlloc(u8, @alignOf(Cpu), @sizeOf(Cpu)) catch return null).ptr;
            }

            fn wasmAlloc(n: usize) callconv(.C) ?[*]u8 {
                return (allocator.alignedAlloc(u8, @import("builtin").target.maxIntAlignment(), n) catch return null).ptr;
            }
        };

        @export(wasm_only_functions.zip8CpuAlloc, .{ .name = "zip8CpuAlloc" });
        @export(wasm_only_functions.wasmAlloc, .{ .name = "wasmAlloc" });
    }
}

test "C-compatible usage" {
    const cpu_buf = try std.testing.allocator.alignedAlloc(
        u8,
        @import("builtin").target.maxIntAlignment(),
        zip8CpuGetSize(),
    );
    defer std.testing.allocator.free(cpu_buf);
    var err: u16 = 0;

    const long_program: []const u8 = &(.{0} ** 3585);
    const valid_program: []const u8 = &.{
        // set some registers
        0x60, 0xff,
        0x61, 0x80,
        0x62, 0x23,
        // this one is invalid
        0xf3, 0x00,
    };

    try std.testing.expectEqual(@as(c_int, 1), zip8CpuInit(
        &err,
        cpu_buf.ptr,
        long_program.ptr,
        long_program.len,
        1337,
        0,
    ));
    try std.testing.expectEqualStrings("ProgramTooLong", std.mem.span(zip8GetErrorName(err)));

    // this program should work for 3 instructions and then hit invalid opcode
    try std.testing.expectEqual(@as(c_int, 0), zip8CpuInit(&err, cpu_buf.ptr, valid_program.ptr, valid_program.len, 1337, 0));
    for (0..3) |_| {
        try std.testing.expectEqual(@as(c_int, 0), zip8CpuCycle(&err, cpu_buf.ptr));
    }
    try std.testing.expectEqual(@as(c_int, 1), zip8CpuCycle(&err, cpu_buf.ptr));
    try std.testing.expectEqualStrings("IllegalOpcode", std.mem.span(zip8GetErrorName(err)));
    try std.testing.expectEqual(ZIP8_ERR_ILLEGAL_OPCODE, err);
    try std.testing.expectEqual(@as(u16, 0x206), zip8CpuGetProgramCounter(cpu_buf.ptr));
    try std.testing.expectEqual(@as(u16, 0xf300), zip8CpuGetInstruction(cpu_buf.ptr));
}

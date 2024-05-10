const std = @import("std");
const bindings = @import("./bindings.zig");

extern fn zip8Log([*:0]const u8, usize) void;

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    _ = ret_addr;
    _ = error_return_trace;
    zip8Log(@ptrCast(msg.ptr), msg.len);
    while (true) {}
}

pub fn logFn(
    comptime level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    const level_prefix = comptime level.asText();
    const prefix = comptime level_prefix ++ switch (scope) {
        .default => ": ",
        else => " (" ++ @tagName(scope) ++ "): ",
    };

    var buf: [1024:0]u8 = undefined;
    const string = std.fmt.bufPrintZ(&buf, prefix ++ format, args) catch &buf;
    zip8Log(string.ptr, string.len);
}

pub const std_options = std.Options{
    .log_level = .info,
    .logFn = logFn,
};

comptime {
    std.testing.refAllDecls(@import("instruction.zig"));
    std.testing.refAllDecls(@import("cpu.zig"));
    std.testing.refAllDecls(@import("bindings.zig"));
}

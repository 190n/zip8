const std = @import("std");
const bindings = @import("./bindings.zig");

// const consoleLog: ?*const fn ([*]const u8, usize) void = switch (@import("builtin").cpu.arch) {
//     .wasm32 => @extern(?*const fn ([*]const u8, usize) void, .{ .name = "consoleLog" }),
//     else => null,
// };
extern fn consoleLog([*]const u8, usize) void;

pub const std_options = struct {
    pub fn logFn(
        comptime level: std.log.Level,
        comptime scope: @TypeOf(.EnumLiteral),
        comptime format: []const u8,
        args: anytype,
    ) void {
        const level_prefix = comptime level.asText();
        const prefix = comptime level_prefix ++ switch (scope) {
            .default => ": ",
            else => " (" ++ @tagName(scope) ++ "): ",
        };

        var buf: [1024]u8 = undefined;
        const string = std.fmt.bufPrint(&buf, prefix ++ format, args) catch &buf;
        if (@import("builtin").cpu.arch == .wasm32) {
            consoleLog(string.ptr, string.len);
        }
    }
};

comptime {
    std.testing.refAllDecls(@import("instruction.zig"));
    std.testing.refAllDecls(@import("cpu.zig"));
    std.testing.refAllDecls(@import("bindings.zig"));
}

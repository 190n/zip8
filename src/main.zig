const std = @import("std");
const bindings = @import("./bindings.zig");

comptime {
    std.testing.refAllDecls(@import("instruction.zig"));
    std.testing.refAllDecls(@import("cpu.zig"));
    std.testing.refAllDecls(@import("bindings.zig"));
}

const std = @import("std");

pub fn run() !void {
    return error.OutOfMemory;
}

pub fn main() anyerror!void {
    run() catch |e| {
        std.debug.print("error: {s}", .{@errorName(e)});
        std.process.exit(1);
    };
    std.process.exit(0);
}

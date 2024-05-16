const std = @import("std");

const Cpu = @import("./tail.zig").Cpu;

// pub const std_options = std.Options{
//     .log_level = .warn,
// };

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();
    const argv = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, argv);

    if (argv.len != 3) {
        std.log.err("usage: {s} <ROM path> <number of cycles>", .{argv[0]});
        return error.BadUsage;
    }

    const rom = try std.fs.cwd().readFileAlloc(allocator, argv[1], 4096 - 512);
    defer allocator.free(rom);
    var instructions = try std.fmt.parseInt(usize, argv[2], 10);

    var cpu = Cpu.init(rom);

    const before = std.posix.getrusage(std.posix.rusage.SELF);

    while (instructions > 0) {
        const to_run = @min(instructions, std.math.maxInt(u16));
        cpu.run(to_run);
        instructions -= to_run;
    }

    const after = std.posix.getrusage(std.posix.rusage.SELF);
    const before_sec = @as(f64, @floatFromInt(before.utime.tv_sec)) +
        @as(f64, @floatFromInt(before.utime.tv_usec)) / 1_000_000.0;
    const after_sec = @as(f64, @floatFromInt(after.utime.tv_sec)) +
        @as(f64, @floatFromInt(after.utime.tv_usec)) / 1_000_000.0;
    const total_cpu_time = after_sec - before_sec;
    const ins_per_sec = @as(f64, @floatFromInt(instructions)) / total_cpu_time;

    var s: [64]u8 = undefined;
    const written = try std.fmt.bufPrint(&s, "{}", .{std.fmt.fmtIntSizeDec(@intFromFloat(ins_per_sec))});
    std.debug.print("{s} ins/sec\n", .{written[0 .. written.len - 1]});
}

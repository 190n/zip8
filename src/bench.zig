const std = @import("std");

const Cpu = @import("./tail.zig").Cpu;

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
    const instructions = try std.fmt.parseInt(usize, argv[2], 10);
    var instructions_remaining = instructions;

    var cpu = Cpu.init(rom);

    const before = std.posix.getrusage(std.posix.rusage.SELF);

    while (instructions_remaining > 0) {
        // const to_run = @min(instructions_remaining, std.math.maxInt(u16));
        const to_run = 250;
        cpu.run(to_run);
        cpu.timerTick();
        instructions_remaining -|= to_run;
    }

    const after = std.posix.getrusage(std.posix.rusage.SELF);
    const before_sec = @as(f64, @floatFromInt(before.utime.tv_sec)) +
        @as(f64, @floatFromInt(before.utime.tv_usec)) / 1_000_000.0;
    const after_sec = @as(f64, @floatFromInt(after.utime.tv_sec)) +
        @as(f64, @floatFromInt(after.utime.tv_usec)) / 1_000_000.0;
    const total_cpu_time = after_sec - before_sec;
    const ins_per_sec = @as(f64, @floatFromInt(instructions)) / total_cpu_time;

    var s: [64]u8 = undefined;
    const written = try std.fmt.bufPrint(&s, "{}", .{std.fmt.fmtIntSizeDec(std.math.lossyCast(u64, ins_per_sec))});
    std.debug.print("{s} ins/sec\n", .{written[0 .. written.len - 1]});

    for (0..32) |y| {
        for (0..64) |x| {
            const pix: u1 = @truncate(cpu.display[(64 * y + x) / 8] >> @truncate(x));
            std.debug.print("{s}", .{
                if (pix == 0)
                    "  "
                else
                    "##",
            });
        }
        std.debug.print("\n", .{});
    }
}

const CPU = @import("./CPU.zig");

pub const Timer = struct {
    sleepMicroseconds: fn (u32) void,
    getTime: fn () i128,
};

pub const Input = struct {
    isKeyPressed: fn (u4) bool,
    waitForKey: fn (u4) void,
};

pub const Display = struct {
    refresh: fn ([CPU.display_height][CPU.display_width]bool) void,
};

pub const Sound = struct {
    on: fn () void,
    off: fn () void,
};

timer: *const Timer,
input: *const Input,
display: *const Display,
sound: *const Sound,

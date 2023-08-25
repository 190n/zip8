fn rowToByte(comptime str: *const [4]u8) u8 {
    var byte: u8 = 0;
    inline for (str, 0..) |c, i| {
        const bit_index: u3 = @intCast(7 - i);
        if (c == 'O') {
            byte |= (1 << bit_index);
        }
    }
    return byte;
}

fn linesToChar(comptime str: []const u8) [5]u8 {
    return .{
        rowToByte(str[0..4]),
        rowToByte(str[5..9]),
        rowToByte(str[10..14]),
        rowToByte(str[15..19]),
        rowToByte(str[20..24]),
    };
}

const char_strings = .{
    \\OOOO
    \\O  O
    \\O  O
    \\O  O
    \\OOOO
    ,
    \\  O 
    \\ OO 
    \\  O 
    \\  O 
    \\ OOO
    ,
    \\OOOO
    \\   O
    \\OOOO
    \\O   
    \\OOOO
    ,
    \\OOOO
    \\   O
    \\OOOO
    \\   O
    \\OOOO
    ,
    \\O  O
    \\O  O
    \\OOOO
    \\   O
    \\   O
    ,
    \\OOOO
    \\O   
    \\OOOO
    \\   O
    \\OOOO
    ,
    \\OOOO
    \\O   
    \\OOOO
    \\O  O
    \\OOOO
    ,
    \\OOOO
    \\   O
    \\  O 
    \\ O  
    \\ O  
    ,
    \\OOOO
    \\O  O
    \\OOOO
    \\O  O
    \\OOOO
    ,
    \\OOOO
    \\O  O
    \\OOOO
    \\   O
    \\OOOO
    ,
    \\OOOO
    \\O  O
    \\OOOO
    \\O  O
    \\O  O
    ,
    \\OOO 
    \\O  O
    \\OOO 
    \\O  O
    \\OOO 
    ,
    \\OOOO
    \\O   
    \\O   
    \\O   
    \\OOOO
    ,
    \\OOO 
    \\O  O
    \\O  O
    \\O  O
    \\OOO 
    ,
    \\OOOO
    \\O   
    \\OOOO
    \\O   
    \\OOOO
    ,
    \\OOOO
    \\O   
    \\OOOO
    \\O   
    \\O   
};

pub const font_data: []const u8 = blk: {
    var data: []const u8 = &.{};
    for (char_strings) |s| {
        const sprite = linesToChar(s);
        _ = sprite;
        data = data ++ &linesToChar(s);
    }
    break :blk data;
};

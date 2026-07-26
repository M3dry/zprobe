const std = @import("std");

pub inline fn probe(comptime zone: []const u8, comptime name: []const u8, args: anytype, comptime args_info: []const std.builtin.Type.StructField) void {
    if (args_info.len > 8) @compileError("Arg count for a USDT probe is larger than 8");
    const args_string = comptime generateArgsString(args_info);

    asm volatile (
        \\ 1:
        \\ nop
        \\
        \\ .pushsection .note.stapsdt,"a","note"
        \\ .balign 4
        \\
        \\ .long 8
        \\ .long desc_end - desc_start
        \\ .long 3
        \\
        \\ .asciz "stapsdt"
        \\
        \\ .balign 4
        \\ desc_start:
        \\ .quad 1b          # probe location
        \\ .quad 0           # base address
        \\ .quad 0           # semaphore address
        \\
        \\ .asciz "
        ++ zone ++
        \\"
        \\ .asciz "
        ++ name ++
        \\"
        \\ .asciz "
        ++ args_string ++
        \\"
        \\
        \\ .balign 4
        \\ desc_end:
        \\
        \\ .popsection
        :
        : [arg0] "nor" (index(args, args_info, 0, args_info.len)),
          [arg1] "nor" (index(args, args_info, 1, args_info.len)),
          [arg2] "nor" (index(args, args_info, 2, args_info.len)),
          [arg3] "nor" (index(args, args_info, 3, args_info.len)),
          [arg4] "nor" (index(args, args_info, 4, args_info.len)),
          [arg5] "nor" (index(args, args_info, 5, args_info.len)),
          [arg6] "nor" (index(args, args_info, 6, args_info.len)),
          [arg7] "nor" (index(args, args_info, 7, args_info.len)),
        : .{ .memory = true }
    );
}

fn IndexReturn(comptime args_info: []const std.builtin.Type.StructField, comptime ix: usize, comptime len: usize) type {
    if (ix >= len) return comptime u32;
    return args_info[ix].type;
}

inline fn index(args: anytype, comptime args_info: []const std.builtin.Type.StructField, comptime ix: usize, comptime len: usize) IndexReturn(args_info, ix, len) {
    if (ix >= len) return 0;
    return args[ix];
}

fn generateArgsString(comptime fields: []const std.builtin.Type.StructField) []const u8 {
    var result: []const u8 = "";

    for (fields, 0..) |field, i| {
        result = result ++ sdtType(field.type) ++ "@%[arg" ++ std.fmt.comptimePrint("{}", .{i}) ++ "]";
        if (i + 1 != fields.len) result = result ++ " ";
    }

    return result;
}

fn sdtType(comptime T: type) []const u8 {
    return switch (@typeInfo(T)) {
        .int => |info| switch (info.bits) {
            8 => "1",
            16 => "2",
            32 => "4",
            64 => "8",
            else => @compileError("unsupported integer size"),
        },
        .comptime_int => "8",
        .float => |info| switch (info.bits) {
            16 => "2",
            32 => "4",
            64 => "8",
            80 => "10",
            128 => "16",
            else => @compileError("unsupported float size"),
        },
        .comptime_float => "8",
        .pointer => "8",
        else => @compileError("unsupported USDT type"),
    };
}

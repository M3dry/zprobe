const std = @import("std");
const Level = @import("tracing.zig").Level;

pub inline fn event(comptime provider: []const u8, comptime level: Level, comptime name: []const u8, args: anytype, comptime args_info: []const std.builtin.Type.StructField) void {
    const level_prefix = comptime switch (level) {
        .err => "error/",
        .warn => "warn/",
        .info => "info/",
        .debug => "debug/",
        .trace => "trace/",
    };
    const usdt_name = level_prefix ++ name;
    emit(provider, usdt_name, args, args_info);
}

pub inline fn spanEnter(comptime provider: []const u8, comptime name: []const u8, args: anytype, comptime args_info: []const std.builtin.Type.StructField) void {
    const usdt_name = comptime "__span_" ++ name;
    emit(provider, usdt_name, args, args_info);
}

pub inline fn spanExit(comptime provider: []const u8, comptime name: []const u8) void {
    const usdt_name = comptime "~__span_" ++ name;
    emit(provider, usdt_name, .{}, &.{});
}

fn isSlice(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .pointer => |p| p.size == .slice,
        else => false,
    };
}

fn flattenedTypes(comptime args_info: []const std.builtin.Type.StructField, comptime i: usize) []const type {
    if (i >= args_info.len) return &.{};
    const field_types = if (isSlice(args_info[i].type)) &[_]type{ u64, u64 } else &[_]type{args_info[i].type};
    return field_types ++ flattenedTypes(args_info, i + 1);
}

inline fn emit(comptime provider: []const u8, comptime name: []const u8, args: anytype, comptime args_info: []const std.builtin.Type.StructField) void {
    const args_string = comptime generateArgsString(args_info);

    asm volatile (
        \\ 1:
        \\ nop
        \\
        \\ .pushsection .note.stapsdt,"a","note"
        \\ .balign 4
        \\
        \\ .long 8
        \\ .long desc_end_%= - desc_start_%=
        \\ .long 3
        \\
        \\ .asciz "stapsdt"
        \\
        \\ .balign 4
        \\ desc_start_%=:
        \\ .quad 1b          # probe location
        \\ .quad 0           # base address
        \\ .quad 0           # semaphore address
        \\
        \\ .asciz "
        ++ provider ++
        \\"
        \\ .asciz "
        ++ name ++
        \\"
        \\ .asciz "
        ++ args_string ++
        \\"
        \\
        \\ .balign 4
        \\ desc_end_%=:
        \\
        \\ .popsection
        :
        : [arg0] "nor" (index(args, 0, args_info)),
          [arg1] "nor" (index(args, 1, args_info)),
          [arg2] "nor" (index(args, 2, args_info)),
          [arg3] "nor" (index(args, 3, args_info)),
          [arg4] "nor" (index(args, 4, args_info)),
          [arg5] "nor" (index(args, 5, args_info)),
          [arg6] "nor" (index(args, 6, args_info)),
          [arg7] "nor" (index(args, 7, args_info)),
        : .{ .memory = true }
    );
}

fn IndexReturn(comptime ix: usize, comptime args_info: []const std.builtin.Type.StructField) type {
    const flattened = flattenedTypes(args_info, 0);

    if (ix >= flattened.len) return comptime u32;
    if (flattened.len > 8) @compileError("Maximal param count (8) exceeded");
    return flattened[ix];
}

inline fn index(args: anytype, comptime ix: usize, comptime args_info: []const std.builtin.Type.StructField) IndexReturn(ix, args_info) {
    const flattened = comptime flattenedTypes(args_info, 0);

    if (ix >= flattened.len) return 0;

    const field, const slice_size = comptime blk: {
        var i: usize = ix;
        var field_ix = 0;
        var slice_size: ?bool = null;
        const fields = @typeInfo(@TypeOf(args)).@"struct".fields;

        for (fields, 0..) |field, f_ix| {
            if (isSlice(field.type) and (i == 0 or i == 1)) {
                if (i == 0) slice_size = false;
                if (i == 1) slice_size = true;

                i = 0;
                field_ix = f_ix;
                break;
            }

            if (i == 0) {
                slice_size = null;
                field_ix = f_ix;
                break;
            }

            if (isSlice(field.type)) {
                i -= 2;
            } else {
                i -= 1;
            }
        }

        break :blk .{fields[field_ix], slice_size};
    };

    if (slice_size) |size| {
        if (size) {
            return @field(args, field.name).len;
        } else {
            return @intFromPtr(@field(args, field.name).ptr);
        }
    } else {
        return @field(args, field.name);
    }
}

fn generateArgsString(comptime args_info: []const std.builtin.Type.StructField) []const u8 {
    var result: []const u8 = "";
    var slot: usize = 0;

    for (args_info) |field| {
        if (isSlice(field.type)) {
            result = result ++ "8@%[arg" ++ std.fmt.comptimePrint("{}", .{slot}) ++ "] 8@%[arg" ++ std.fmt.comptimePrint("{}", .{slot + 1}) ++ "] ";
            slot += 2;
        } else {
            result = result ++ sdtType(field.type) ++ "@%[arg" ++ std.fmt.comptimePrint("{}", .{slot}) ++ "] ";
            slot += 1;
        }
    }

    if (slot > 0) result = result[0 .. result.len - 1];
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

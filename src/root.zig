const std = @import("std");
const opts = @import("options");
const usdt = @import("usdt.zig");
const tracing = @import("tracing.zig");
const rdtsc_ = @import("rdtsc.zig");

pub const Level = tracing.Level;
pub const LevelFlags = tracing.LevelFlags;
pub const ProbeKind = tracing.ProbeKind;
pub const ProbeEvent = tracing.ProbeEvent;
pub const Subscriber = tracing.Subscriber;
pub const FileSubscriber = tracing.FileSubscriber;

pub const Config = struct {
    provider: []const u8,
    level_flags: LevelFlags,
    backend_usdt: bool,
    backend_tracing: bool,
};

pub const config: Config = .{
    .provider = opts.provider,
    .level_flags = .{
        .err = opts.err,
        .warn = opts.warn,
        .info = opts.info,
        .debug = opts.debug,
        .trace = opts.trace,
    },
    .backend_usdt = opts.backend_usdt,
    .backend_tracing = opts.backend_tracing,
};

pub fn Span(comptime name: []const u8, comptime Args: type) type {
    return struct {
        args: Args,

        pub fn enter(self: @This()) void {
            const fields = comptime @typeInfo(Args).@"struct".fields;
            if (config.backend_usdt) {
                usdt.spanEnter(config.provider, name, self.args, fields);
            }
            if (config.backend_tracing) {
                var buf: [256]u8 = undefined;
                const args_fmt = formatArgs(fields, self.args, buf[0..]);
                tracing.dispatch(.{
                    .kind = .span_enter,
                    .name = name,
                    .args_fmt = args_fmt,
                    .timestamp = rdtsc_.rdtsc(),
                });
            }
        }

        pub fn exit(self: @This()) void {
            _ = self;
            if (config.backend_usdt) {
                usdt.spanExit(config.provider, name);
            }
            if (config.backend_tracing) {
                tracing.dispatch(.{
                    .kind = .span_exit,
                    .name = name,
                    .args_fmt = "",
                    .timestamp = rdtsc_.rdtsc(),
                });
            }
        }
    };
}

pub fn span(comptime name: []const u8, args: anytype) Span(name, @TypeOf(args)) {
    return .{ .args = args };
}

pub fn event(comptime level: Level, comptime name: []const u8, args: anytype) void {
    if (comptime !@field(config.level_flags, @tagName(level))) return;

    const Args = @TypeOf(args);
    const fields = comptime switch (@typeInfo(Args)) {
        .@"struct" => |s| s.fields,
        else => @compileError("event args must be a tuple or struct"),
    };

    if (config.backend_usdt) {
        usdt.event(config.provider, level, name, args, fields);
    }
    if (config.backend_tracing) {
        var buf: [256]u8 = undefined;
        const args_fmt = formatArgs(fields, args, buf[0..]);
        tracing.dispatch(.{
            .kind = .event,
            .name = name,
            .args_fmt = args_fmt,
            .timestamp = rdtsc_.rdtsc(),
        });
    }
}

pub fn rdtsc() u64 {
    return rdtsc_.rdtsc();
}

fn isStringType(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .pointer => |p| switch (@typeInfo(p.child)) {
            .array => |a| a.child == u8,
            else => p.size == .slice and p.child == u8,
        },
        else => false,
    };
}

fn formatArgs(comptime fields: []const std.builtin.Type.StructField, args: anytype, buf: []u8) []const u8 {
    var pos: usize = 0;
    inline for (fields, 0..) |field, i| {
        if (i > 0) {
            if (pos + 2 > buf.len) break;
            buf[pos] = ',';
            buf[pos + 1] = ' ';
            pos += 2;
        }
        if (field.name.len > 0) {
            if (pos + field.name.len + 1 > buf.len) break;
            for (field.name, 0..) |c, j| buf[pos + j] = c;
            pos += field.name.len;
            buf[pos] = '=';
            pos += 1;
        }
        const value = @field(args, field.name);
        const T = @TypeOf(value);
        const is_str = comptime isStringType(T);
        const formatted = if (is_str)
            std.fmt.bufPrint(buf[pos..], "{s}", .{@as([]const u8, value)}) catch break
        else
            std.fmt.bufPrint(buf[pos..], "{any}", .{value}) catch break;
        pos += formatted.len;
    }
    return buf[0..pos];
}

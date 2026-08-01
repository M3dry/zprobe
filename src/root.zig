const std = @import("std");
const opts = @import("options");
const usdt = @import("usdt.zig");
const tracing = @import("tracing.zig");
const rdtsc_ = @import("rdtsc.zig");

pub const Level = tracing.Level;
pub const LevelFlags = tracing.LevelFlags;
pub const ProbeKind = tracing.ProbeKind;
pub const ProbeEvent = tracing.ProbeEvent;
pub const Field = tracing.Field;
pub const FieldValue = tracing.FieldValue;
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

fn toFieldValue(value: anytype) FieldValue {
    const T = @TypeOf(value);
    return switch (@typeInfo(T)) {
        .int => |info| switch (info.signedness) {
            .signed => FieldValue{ .int = @intCast(value) },
            .unsigned => FieldValue{ .uint = @intCast(value) },
        },
        .comptime_int => if (value < 0)
            FieldValue{ .int = @intCast(value) }
        else
            FieldValue{ .uint = @intCast(value) },
        .float => FieldValue{ .float = @floatCast(value) },
        .comptime_float => FieldValue{ .float = @floatCast(value) },
        .bool => FieldValue{ .boolean = value },
        .pointer => |p| blk: {
            if (p.size == .slice and p.child == u8)
                break :blk FieldValue{ .string = value };
            if (p.size == .one and comptime @typeInfo(p.child) == .array)
                if (@typeInfo(p.child).array.child == u8)
                    break :blk FieldValue{ .string = @as([]const u8, value) };
            break :blk FieldValue{ .pointer = @intFromPtr(value) };
        },
        else => @compileError("unsupported field type: " ++ @typeName(T)),
    };
}

fn toFields(comptime fields_info: []const std.builtin.Type.StructField, args: anytype, buf: *[8]Field) []const Field {
    inline for (fields_info, 0..) |f, i| {
        buf[i] = .{ .name = f.name, .value = toFieldValue(@field(args, f.name)) };
    }
    return buf[0..fields_info.len];
}

pub fn Span(comptime name: []const u8, comptime Args: type) type {
    return struct {
        args: Args,

        pub inline fn enter(self: @This()) void {
            const fields_info = comptime @typeInfo(Args).@"struct".fields;
            if (config.backend_usdt) {
                usdt.spanEnter(config.provider, name, self.args, fields_info);
            }
            if (config.backend_tracing) {
                var field_buf: [8]Field = undefined;
                const fields = toFields(fields_info, self.args, &field_buf);
                tracing.dispatch(.{
                    .kind = .span_enter,
                    .name = name,
                    .fields = fields,
                    .timestamp = rdtsc_.rdtsc(),
                });
            }
        }

        pub inline fn exit(self: @This()) void {
            _ = self;
            if (config.backend_usdt) {
                usdt.spanExit(config.provider, name);
            }
            if (config.backend_tracing) {
                tracing.dispatch(.{
                    .kind = .span_exit,
                    .name = name,
                    .fields = &[_]Field{},
                    .timestamp = rdtsc_.rdtsc(),
                });
            }
        }
    };
}

pub fn span(comptime name: []const u8, args: anytype) Span(name, @TypeOf(args)) {
    return .{ .args = args };
}

pub inline fn event(comptime level: Level, comptime name: []const u8, args: anytype) void {
    if (comptime !@field(config.level_flags, @tagName(level))) return;

    const Args = @TypeOf(args);
    const fields_info = comptime switch (@typeInfo(Args)) {
        .@"struct" => |s| s.fields,
        else => @compileError("event args must be a tuple or struct"),
    };

    if (config.backend_usdt) {
        usdt.event(config.provider, level, name, args, fields_info);
    }
    if (config.backend_tracing) {
        var field_buf: [8]Field = undefined;
        const fields = toFields(fields_info, args, &field_buf);
        tracing.dispatch(.{
            .kind = .{ .event = level },
            .name = name,
            .fields = fields,
            .timestamp = rdtsc_.rdtsc(),
        });
    }
}

pub fn rdtsc() u64 {
    return rdtsc_.rdtsc();
}

pub fn setDefaultConsole() void {
    tracing.setDefaultConsole();
}

pub fn formatFields(writer: *std.Io.Writer, fields: []const Field) std.Io.Writer.Error!void {
    return tracing.formatFields(writer, fields);
}

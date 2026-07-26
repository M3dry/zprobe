const std = @import("std");

pub const Level = enum(u3) {
    err,
    warn,
    info,
    debug,
    trace,
};

pub const LevelFlags = packed struct(u5) {
    err: bool = false,
    warn: bool = false,
    info: bool = false,
    debug: bool = false,
    trace: bool = false,

    pub const all: LevelFlags = .{ .err = true, .warn = true, .info = true, .debug = true, .trace = true };
    pub const release: LevelFlags = .{ .err = true, .warn = true, .info = true, .debug = false, .trace = false };
    pub const errors: LevelFlags = .{ .err = true, .warn = false, .info = false, .debug = false, .trace = false };
};

pub const ProbeKind = enum(u2) {
    event,
    span_enter,
    span_exit,
};

pub const ProbeEvent = struct {
    kind: ProbeKind,
    name: []const u8,
    args_fmt: []const u8,
    timestamp: u64,
};

pub const Subscriber = struct {
    name: []const u8,
    ctx: *anyopaque,
    onProbe: *const fn (ctx: *anyopaque, event: ProbeEvent) void,

    pub fn register(sub: Subscriber) void {
        for (&subscribers) |*slot| {
            if (slot.* == null) {
                slot.* = sub;
                return;
            }
        }
    }

    pub fn unregister(name: []const u8) void {
        for (&subscribers) |*slot| {
            if (slot.*) |s| {
                if (std.mem.eql(u8, s.name, name)) {
                    slot.* = null;
                    return;
                }
            }
        }
    }
};

const MAX_SUBSCRIBERS = 16;
var subscribers: [MAX_SUBSCRIBERS]?Subscriber = .{null} ** MAX_SUBSCRIBERS;

pub fn dispatch(event: ProbeEvent) void {
    for (&subscribers) |slot| {
        if (slot) |sub| {
            sub.onProbe(sub.ctx, event);
        }
    }
}

pub const FileSubscriber = struct {
    writer: std.Io.File.Writer,
    subscriber: Subscriber,

    pub fn init(dst: *FileSubscriber, io: std.Io, file: std.Io.File, buffer: []u8, name: []const u8) void {
        dst.* = .{
            .writer = file.writer(io, buffer),
            .subscriber = .{
                .name = name,
                .ctx = dst,
                .onProbe = onProbe,
            },
        };
    }

    fn onProbe(ctx: *anyopaque, event: ProbeEvent) void {
        const self: *FileSubscriber = @alignCast(@ptrCast(ctx));

        (switch (event.kind) {
            .event => self.writer.interface.print("[event] {s} {s}\n", .{ event.name, event.args_fmt }),
            .span_enter => self.writer.interface.print("[enter] {s} {s}\n", .{ event.name, event.args_fmt }),
            .span_exit => self.writer.interface.print("[exit] {s}\n", .{ event.name }),
        }) catch {};
    }
};

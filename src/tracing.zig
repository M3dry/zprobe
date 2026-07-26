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

pub const FieldValue = union(enum) {
    int: i64,
    uint: u64,
    float: f64,
    string: []const u8,
    boolean: bool,
    pointer: u64,
};

pub const Field = struct {
    name: []const u8,
    value: FieldValue,
};

pub const ProbeEvent = struct {
    kind: ProbeKind,
    name: []const u8,
    fields: []const Field,
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

pub fn formatFields(writer: *std.Io.Writer, fields: []const Field) std.Io.Writer.Error!void {
    for (fields, 0..) |f, i| {
        if (i > 0) try writer.writeAll(", ");
        if (f.name.len > 0) {
            try writer.writeAll(f.name);
            try writer.writeAll("=");
        }
        switch (f.value) {
            .int => |v| try writer.print("{}", .{v}),
            .uint => |v| try writer.print("{}", .{v}),
            .float => |v| try writer.print("{d}", .{v}),
            .string => |v| try writer.print("{s}", .{v}),
            .boolean => |v| try writer.print("{}", .{v}),
            .pointer => |v| try writer.print("0x{x}", .{v}),
        }
    }
}

const console_ctx: u8 = 0;

fn consoleOnProbe(ctx: *anyopaque, event: ProbeEvent) void {
    _ = ctx;
    var buf: [256]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    formatFields(&w, event.fields) catch {};
    const fmt = w.buffered();
    switch (event.kind) {
        .event => std.debug.print("[event] {s} {s}\n", .{ event.name, fmt }),
        .span_enter => std.debug.print("[enter] {s} {s}\n", .{ event.name, fmt }),
        .span_exit => std.debug.print("[exit]  {s}\n", .{ event.name }),
    }
}

pub const console = Subscriber{
    .name = "zprobe.console",
    .ctx = @constCast(@ptrCast(&console_ctx)),
    .onProbe = consoleOnProbe,
};

pub fn setDefaultConsole() void {
    Subscriber.register(console);
}

pub const FileSubscriber = struct {
    writer: std.Io.File.Writer,
    depth: u32,
    subscriber: Subscriber,

    pub fn init(dst: *FileSubscriber, io: std.Io, file: std.Io.File, buffer: []u8, name: []const u8) void {
        dst.* = .{
            .writer = file.writer(io, buffer),
            .depth = 0,
            .subscriber = .{
                .name = name,
                .ctx = dst,
                .onProbe = onProbe,
            },
        };
    }

    fn printDepth(self: *FileSubscriber) !void {
        for (0..self.depth) |_| {
            try self.writer.interface.writeAll(" ");
        }
    }

    fn onProbe(ctx: *anyopaque, event: ProbeEvent) void {
        const self: *FileSubscriber = @alignCast(@ptrCast(ctx));

        switch (event.kind) {
            .event => {
                self.printDepth() catch {};
                self.writer.interface.print("[event] {s} ", .{ event.name }) catch {};
                formatFields(&self.writer.interface, event.fields) catch {};
                self.writer.interface.print("\n", .{}) catch {};
            },
            .span_enter => {
                self.printDepth() catch {};
                self.writer.interface.print("[enter] {s} ", .{ event.name }) catch {};
                formatFields(&self.writer.interface, event.fields) catch {};
                self.writer.interface.print("\n", .{}) catch {};
                self.depth += 1;
            },
            .span_exit => {
                self.depth -= 1;
            },
        }
    }
};

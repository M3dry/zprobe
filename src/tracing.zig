const std = @import("std");

pub const Level = enum(u3) {
    err,
    warn,
    info,
    debug,
    trace,

    pub fn asText(self: Level) []const u8 {
        return switch (self) {
            .err => "error",
            .warn => "warning",
            .info => "info",
            .debug => "debug",
            .trace => "trace",
        };
    }
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

pub const ProbeKind = union(enum) {
    event: Level,
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

pub const FileSubscriber = struct {
    writer: std.Io.File.Writer,
    terminal_mode: std.Io.Terminal.Mode,
    depth: u32,
    subscriber: Subscriber,

    pub fn init(dst: *FileSubscriber, io: std.Io, file: std.Io.File, buffer: []u8, name: []const u8) void {
        dst.* = .{
            .writer = file.writer(io, buffer),
            .terminal_mode = std.Io.Terminal.Mode.detect(io, file, false, false) catch .no_color,
            .depth = 0,
            .subscriber = .{
                .name = name,
                .ctx = dst,
                .onProbe = onProbe,
            },
        };
    }

    fn terminal(self: *FileSubscriber) std.Io.Terminal {
        return .{ .writer = &self.writer.interface, .mode = self.terminal_mode };
    }

    fn printDepth(self: *FileSubscriber) !void {
        for (0..self.depth) |_| {
            try self.writer.interface.writeAll(" ");
        }
    }

    fn colorFor(level: Level) std.Io.Terminal.Color {
        return switch (level) {
            .err => .red,
            .warn => .yellow,
            .info => .green,
            .debug => .magenta,
            .trace => .cyan,
        };
    }

    fn setTag(t: std.Io.Terminal, color: std.Io.Terminal.Color, text: []const u8) !void {
        t.setColor(color) catch {};
        t.setColor(.bold) catch {};
        try t.writer.writeAll(text);
        t.setColor(.reset) catch {};
    }

    fn onProbe(ctx: *anyopaque, event: ProbeEvent) void {
        const self: *FileSubscriber = @alignCast(@ptrCast(ctx));
        const t = self.terminal();

        switch (event.kind) {
            .event => |level| {
                self.printDepth() catch {};
                setTag(t, colorFor(level), "[") catch {};
                setTag(t, colorFor(level), level.asText()) catch {};
                setTag(t, colorFor(level), "]") catch {};
                self.writer.interface.print(" {s} ", .{ event.name }) catch {};
                formatFields(&self.writer.interface, event.fields) catch {};
                self.writer.interface.print("\n", .{}) catch {};
            },
            .span_enter => {
                self.printDepth() catch {};
                setTag(t, .cyan, "[enter]") catch {};
                self.writer.interface.print(" {s} ", .{ event.name }) catch {};
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

const std = @import("std");
const zprobe = @import("zprobe");

pub fn main(init: std.process.Init) !void {
    var file_subscriber: zprobe.FileSubscriber = undefined;
    zprobe.FileSubscriber.init(&file_subscriber, init.io, std.Io.File.stdout(), &.{}, "Stdout");
    // defer file_subscriber.writer.flush() catch {};
    file_subscriber.subscriber.register();

    const s = zprobe.span("physics", .{ .world = "main" });
    s.enter();
    defer s.exit();

    zprobe.event(.info, "simulate step", .{ .dt = 0.015, .entity = 42 });
    zprobe.event(.debug, "broadphase pairs", .{ .count = 240 });
}

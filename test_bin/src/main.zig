const std = @import("std");
const zprobe = @import("zprobe");

pub fn main(init: std.process.Init) !void {
    _ = init;
    zprobe.probe("test", "the", .{100, "literal"});
}

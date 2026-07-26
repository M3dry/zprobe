const usdt = @import("usdt.zig");

pub inline fn probe(comptime zone: []const u8, comptime name: []const u8, args: anytype) void {
    const Args = @TypeOf(args);

    switch (@typeInfo(Args)) {
        .@"struct" => |s| {
            usdt.probe(zone, name, args, s.fields);
        },
        else => @compileError("probe args must be a tule"),
    }
}

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zprobe_mod = b.dependency("zprobe", .{
        .target = target,
        .optimize = optimize,
        .provider = "test",
        .backend_usdt = true,
    }).module("root");

    const exe_opts: std.Build.ExecutableOptions = .{
        .name = "Test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zprobe", .module = zprobe_mod }
            },
        }),
    };
    const exe = b.addExecutable(exe_opts);
    exe.use_llvm = true;
    b.installArtifact(exe);

    const exe_check = b.addExecutable(exe_opts);
    exe_check.use_llvm = true;
    const check = b.step("check", "Check compilation");
    check.dependOn(&exe_check.step);
}

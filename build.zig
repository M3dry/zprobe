const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const provider = b.option([]const u8, "provider", "USDT provider name") orelse "zprobe";
    const override_usdt = b.option(bool, "backend_usdt", "Enable USDT backend");
    const override_tracing = b.option(bool, "backend_tracing", "Enable tracing backend");
    const level_err = b.option(bool, "level_err", "Enable error level") orelse true;
    const level_warn = b.option(bool, "level_warn", "Enable warn level") orelse true;
    const level_info = b.option(bool, "level_info", "Enable info level") orelse true;
    const level_debug = b.option(bool, "level_debug", "Enable debug level") orelse (optimize == .Debug);
    const level_trace = b.option(bool, "level_trace", "Enable trace level") orelse (optimize == .Debug);

    const opts = b.addOptions();
    opts.addOption([]const u8, "provider", provider);
    opts.addOption(bool, "err", level_err);
    opts.addOption(bool, "warn", level_warn);
    opts.addOption(bool, "info", level_info);
    opts.addOption(bool, "debug", level_debug);
    opts.addOption(bool, "trace", level_trace);
    opts.addOption(bool, "backend_usdt", override_usdt orelse (optimize != .Debug));
    opts.addOption(bool, "backend_tracing", override_tracing orelse (optimize == .Debug));

    const options_module = opts.createModule();

    const mod = b.addModule("root", .{
        .root_source_file = b.path("src/root.zig"),
        .imports = &.{
            .{ .name = "options", .module = options_module },
        },
        .target = target,
        .optimize = optimize,
    });

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    mod_tests.use_llvm = true;

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}

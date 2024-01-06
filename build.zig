const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const args_dep = b.dependency("args", .{});
    const args_mod = args_dep.module("args");

    const basic_exe = b.addExecutable(.{
        .name = "cbm-basic",
        .root_source_file = .{ .path = "src/basic.zig" },
        .target = target,
        .optimize = optimize,
    });
    basic_exe.addModule("args", args_mod);
    b.installArtifact(basic_exe);

    const run_basic_cmd = b.addRunArtifact(basic_exe);
    run_basic_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_basic_cmd.addArgs(args);
    }

    const run_step = b.step("basic", "Run the app");
    run_step.dependOn(&run_basic_cmd.step);

    const test_step = b.step("test", "Tests all tools");
    {
        const basic_test = b.addTest(.{
            .root_source_file = .{ .path = "src/basic.zig" },
        });
        test_step.dependOn(&b.addRunArtifact(basic_test).step);
    }
}

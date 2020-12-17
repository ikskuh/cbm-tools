const std = @import("std");

const pkgs = struct {
    const args = std.build.Pkg{
        .name = "args",
        .path = "./deps/args/args.zig",
    };
};

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const basic_exe = b.addExecutable("cbm-basic", "src/basic.zig");
    basic_exe.setTarget(target);
    basic_exe.setBuildMode(mode);
    basic_exe.addPackage(pkgs.args);
    basic_exe.install();

    const run_basic_cmd = basic_exe.run();
    run_basic_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_basic_cmd.addArgs(args);
    }

    const run_step = b.step("basic", "Run the app");
    run_step.dependOn(&run_basic_cmd.step);

    const test_step = b.step("test", "Tests all tools");
    {
        const basic_test = b.addTest("src/basic.zig");
        test_step.dependOn(&basic_test.step);
    }
}

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sqlite_h = b.addTranslateC(.{
        .root_source_file = b.path("src/vendor/sqlite3.h"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    sqlite_h.addIncludePath(b.path("src/vendor"));
    const sqlite_mod = sqlite_h.createModule();
    sqlite_mod.addCSourceFile(.{
        .file = b.path("src/vendor/sqlite3.c"),
        .flags = &.{},
    });

    const exe = b.addExecutable(.{
        .name = "zigzwang",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{
                    .name = "sqlite",
                    .module = sqlite_mod,
                },
            },
        }),
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const exe_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{
                    .name = "sqlite",
                    .module = sqlite_mod,
                },
            },
        }),
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}

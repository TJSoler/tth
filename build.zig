const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // TTH library module
    const mod = b.addModule("tth", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    // Optional: Create an executable for testing/demo purposes
    const exe = b.addExecutable(.{
        .name = "tth",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/tth.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "tth", .module = mod },
            },
        }),
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Test executable for the library module
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    // Test executable for main.zig
    const exe_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/tth.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "tth", .module = mod },
            },
        }),
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    // Test step runs all tests
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);

    // Benchmark executable
    const bench_exe = b.addExecutable(.{
        .name = "bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/benchmark.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const bench_step = b.step("bench", "Run benchmarks");
    const bench_cmd = b.addRunArtifact(bench_exe);
    bench_step.dependOn(&bench_cmd.step);

    if (b.args) |args| {
        bench_cmd.addArgs(args);
    }
}

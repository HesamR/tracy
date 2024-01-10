const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const enable = b.option(bool, "enable", "enable profiling") orelse true;
    const has_callstack = b.option(bool, "has_callstack", "has callstack sampling") orelse true;
    const callstack_depth = b.option(u8, "callstack_depth", "depth of callstack") orelse 16;

    const options = b.addOptions();
    options.addOption(bool, "enable", enable);
    options.addOption(bool, "has_callstack", has_callstack);
    options.addOption(u8, "callstack_depth", callstack_depth);

    const lib = b.addStaticLibrary(.{
        .name = "tracy",
        .target = target,
        .optimize = optimize,
    });

    lib.linkLibC();
    lib.linkLibCpp();

    lib.addCSourceFile(.{
        .file = .{ .path = "c-src/TracyClient.cpp" },
        .flags = &.{"-std=c++14"},
    });

    if (enable) {
        lib.defineCMacro("TRACY_ENABLE", null);
    }

    const module = b.addModule("main", .{
        .root_source_file = .{ .path = "src/tracy.zig" },
        .target = target,
        .optimize = optimize,
    });

    module.addOptions("options", options);
    module.linkLibrary(lib);

    if (target.result.os.tag == .windows) {
        module.linkSystemLibrary("Ws2_32", .{});
        module.linkSystemLibrary("Dbghelp", .{});
    }

    const test_exe = b.addTest(.{
        .root_source_file = .{ .path = "src/tracy.zig" },
        .target = target,
        .optimize = optimize,
    });

    test_exe.root_module.addOptions("options", options);
    test_exe.linkLibrary(lib);

    const run_test = b.addRunArtifact(test_exe);
    const test_step = b.step("test", "run the test");
    test_step.dependOn(&run_test.step);
}

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = b.addModule("main", .{
        .root_source_file = .{ .path = "libs/tracy/src/tracy.zig" },
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
    });

    if (target.result.os.tag == .windows) {
        module.linkSystemLibrary("Ws2_32", .{});
        module.linkSystemLibrary("Dbghelp", .{});
    }

    module.addCSourceFile(.{
        .file = .{ .path = "libs/tracy/c-src/TracyClient.cpp" },
        .flags = &.{
            "-std=c++14",
            "-DTRACY_ENABLE",
        },
    });
}

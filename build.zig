const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Private Modules
    const mod_internal = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("./internal/root.zig"),
    });

    // Dependencies
    const httpz = b.dependency("httpz", .{
        .target = target,
        .optimize = optimize,
    });

    const pg = b.dependency("pg", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "server",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("./cmd/server/main.zig"),
            .imports = &.{
                .{ .name = "internal", .module = mod_internal },
                .{ .name = "httpz", .module = httpz.module("httpz") },
                .{ .name = "pg", .module = pg.module("pg") },
            },
        }),
    });

    b.installArtifact(exe);
}

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Dependencies
    const httpz = b.dependency("httpz", .{
        .target = target,
        .optimize = optimize,
    });

    const pg = b.dependency("pg", .{
        .target = target,
        .optimize = optimize,
    });

    // zmpl: absolute templates path keeps the build independent of the cwd.
    const zmpl = b.dependency("zmpl", .{
        .target = target,
        .optimize = optimize,
        .zmpl_templates_paths = @as([]const []const u8, &.{
            b.fmt("prefix=html,path={s}", .{b.pathFromRoot("html")}),
        }),
    });

    const web_static = b.createModule(.{ .root_source_file = b.path("html/static/assets.zig") });

    // Private Modules
    const mod_internal = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("./internal/root.zig"),
        .imports = &.{
            .{ .name = "httpz", .module = httpz.module("httpz") },
            .{ .name = "pg", .module = pg.module("pg") },
            .{ .name = "zmpl", .module = zmpl.module("zmpl") },
            .{ .name = "web_static", .module = web_static },
        },
    });

    // Executable
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

    // Tests
    const tests = b.addTest(.{ .root_module = mod_internal });
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);
}

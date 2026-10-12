const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Dependencies
    const httpz = b.dependency("httpz", .{
        .target = target,
        .optimize = optimize,
    });

    // -Dtls=true links OpenSSL into pg.zig; the default build needs no OpenSSL.
    // The paths are forwarded only with -Dtls=true (pg.zig enables OpenSSL
    // whenever a path is set).
    const tls = b.option(bool, "tls", "Enable Postgres TLS via OpenSSL (default: false)") orelse false;
    const openssl_lib_path = b.option(std.Build.LazyPath, "openssl_lib_path", "OpenSSL library dir (with -Dtls=true)");
    const openssl_include_path = b.option(std.Build.LazyPath, "openssl_include_path", "OpenSSL include dir (with -Dtls=true)");
    const pg = b.dependency("pg", .{
        .target = target,
        .optimize = optimize,
        .openssl = if (tls) true else null,
        .openssl_lib_path = if (tls) openssl_lib_path else null,
        .openssl_include_path = if (tls) openssl_include_path else null,
    });

    const build_options = b.addOptions();
    build_options.addOption(bool, "tls", tls);

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
                .{ .name = "build_options", .module = build_options.createModule() },
            },
        }),
    });

    b.installArtifact(exe);

    // Tests
    const tests = b.addTest(.{ .root_module = mod_internal });
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);
    const exe_tests = b.addTest(.{ .root_module = exe.root_module });
    test_step.dependOn(&b.addRunArtifact(exe_tests).step);
}

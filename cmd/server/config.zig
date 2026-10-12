// TLS to Postgres (needs a binary built with `zig build -Dtls=true`):
//   PBA_DATABASE_SSLMODE      disable (default) | require | verify-full
//   PBA_DATABASE_SSLROOTCERT  CA file for verify-full; unset uses the system trust store
pub const SslMode = enum { disable, require, @"verify-full" };

pub fn parseSslMode(value: ?[]const u8) error{InvalidSslMode}!SslMode {
    const v = value orelse return .disable;
    return std.meta.stringToEnum(SslMode, v) orelse error.InvalidSslMode;
}

// the following is a configuration object that can be used
// to configure the server.
pub const Configuration = struct {
    Server: struct {
        InterfaceFunc: *const fn (u16) httpz.Config.Address = httpz.Config.Address.localhost,
        Port: u16 = 8080,
    } = .{},

    Database: ?struct {
        User: []const u8,
        Password: []const u8,
        Host: []const u8,
        Port: u16,
        Database: []const u8,
        SslMode: SslMode = .disable,
        SslRootCert: ?[]const u8 = null,
        Pool: struct {
            size: u16 = 10,
            timeout: u32 = 10 * std.time.ms_per_s,
        } = .{},
    } = null,

    pub fn load(self: *@This(), environ_map: *std.process.Environ.Map) !void {
        // NOTE: This is the prefex for all the environment variables.

        if (environ_map.get("PBA_SERVER_INTERFACEFUNC")) |interfacefunc| {
            if (std.mem.eql(u8, interfacefunc, "0.0.0.0")) {
                self.Server.InterfaceFunc = httpz.Config.Address.all;
            }
        }

        if (environ_map.get("PBA_SERVER_PORT")) |port| {
            const port_as_int = std.fmt.parseInt(u16, port, 10) catch |err| {
                std.log.err("failed to parse PBA_SERvER_PORT as u16 integer (err: {s})", .{@errorName(err)});
                return err;
            };

            self.Server.Port = port_as_int;
        }

        const sslmode_env = environ_map.get("PBA_DATABASE_SSLMODE");
        const sslmode = parseSslMode(sslmode_env) catch |err| {
            std.log.err("invalid PBA_DATABASE_SSLMODE \"{s}\" (expected disable, require or verify-full)", .{sslmode_env.?});
            return err;
        };
        const sslrootcert = environ_map.get("PBA_DATABASE_SSLROOTCERT");
        if (sslrootcert != null and sslmode != .@"verify-full") {
            std.log.warn("PBA_DATABASE_SSLROOTCERT is ignored unless PBA_DATABASE_SSLMODE=verify-full", .{});
        }

        const user = environ_map.get("PBA_DATABASE_USER");
        const password = environ_map.get("PBA_DATABASE_PASSWORD");
        const host = environ_map.get("PBA_DATABASE_HOST");
        const port = environ_map.get("PBA_DATABASE_PORT");
        const database = environ_map.get("PBA_DATABASE_DATABASE");
        if ((user != null and password != null and host != null and port != null and database != null)) {
            self.Database = .{
                .User = user.?,
                .Password = password.?,
                .Host = host.?,
                .Port = std.fmt.parseInt(u16, port.?, 10) catch |err| {
                    std.log.err("failed to parse PBA_DATABASE_PORT as u16 integer (err: {s})", .{@errorName(err)});
                    return err;
                },
                .Database = database.?,
                .SslMode = sslmode,
                .SslRootCert = if (sslmode == .@"verify-full") sslrootcert else null,
                .Pool = .{
                    .size = std.fmt.parseInt(u16, environ_map.get("PBA_DATABASE_POOL_SIZE") orelse "10", 10) catch blk: {
                        break :blk 10;
                    },
                    .timeout = std.fmt.parseInt(u32, environ_map.get("PBA_DATABASE_POOL_TIMEOUT") orelse "10", 10) catch blk: {
                        break :blk 10;
                    } * std.time.ms_per_s,
                },
            };
        }

        if (self.Database) |db| {
            std.log.info("starting with an active database @{s}:{d} (sslmode: {s})", .{ db.Host, db.Port, @tagName(db.SslMode) });
        } else {
            std.log.warn("starting without an active database, ensure all database variables are set", .{});
        }
    }
};

const std = @import("std");
const httpz = @import("httpz");

test parseSslMode {
    try std.testing.expectEqual(SslMode.disable, try parseSslMode(null));
    try std.testing.expectEqual(SslMode.disable, try parseSslMode("disable"));
    try std.testing.expectEqual(SslMode.require, try parseSslMode("require"));
    try std.testing.expectEqual(SslMode.@"verify-full", try parseSslMode("verify-full"));
    try std.testing.expectError(error.InvalidSslMode, parseSslMode("prefer"));
}

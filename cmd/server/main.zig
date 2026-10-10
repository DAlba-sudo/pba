var pool: ?*pg.Pool = null;

var io: std.Io = undefined;
var allocator: std.mem.Allocator = undefined;

pub fn main(init: process.Init) !void {
    io = init.io;
    allocator = init.gpa;

    var configuration = config.Configuration{};
    try configuration.load(init.environ_map);
    try init_database(configuration);
    defer {
        if (pool) |p| {
            p.deinit();
        }
    }

    var server = try internal.routes.Server.init(io, allocator, .{
        .address = configuration.Server.InterfaceFunc(configuration.Server.Port),
        .request = .{
            .max_form_count = 16,
        },
    }, internal.routes.App{
        .p = pool,
    });
    defer server.deinit();
    defer server.stop();

    var router = try server.router(.{});

    router.get("/health", internal.routes.health, .{});
    router.post("/api/account", internal.routes.api.create_account, .{});
    router.delete("/api/account", internal.routes.api.delete_account, .{});
    router.post("/api/operation", internal.routes.api.create_operation, .{});
    router.delete("/api/operation", internal.routes.api.delete_operation, .{});
    router.get("/api/search/operations", internal.routes.api.search_operations_by_title, .{});
    router.post("/api/account/money", internal.routes.api.total_money_as_of, .{});

    try server.listen();
}

// takes an already initialized configuration and reads it's values
// so it can setup the postgres pool.
fn init_database(c: config.Configuration) !void {
    if (c.Database) |db| {
        pool = pg.Pool.init(io, allocator, .{
            .size = db.Pool.size,
            .timeout = db.Pool.timeout,
            .auth = .{
                .username = db.User,
                .password = db.Password,
                .database = db.Database,
            },
            .connect = .{
                .host = db.Host,
                .port = db.Port,
            },
        }) catch |err| {
            std.log.err("failed to initialize database with given information, proceeding without database (err: {s})", .{@errorName(err)});
            return;
        };
        const _pool = pool.?;

        std.log.info("successfully connected to the database", .{});
        errdefer _pool.deinit();

        _ = try _pool.exec(internal.types.Account.DEF, .{});
        _ = try _pool.exec(internal.types.Operation.DEF, .{});
    }
}

const std = @import("std");
const process = std.process;
const config = @import("config.zig");
const httpz = @import("httpz");
const pg = @import("pg");
const internal = @import("internal");

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
        .io = io,
    });
    defer server.deinit();
    defer server.stop();

    var router = try server.router(.{});

    router.get("/health", internal.routes.health, .{});

    router.post("/api/account", api.Account.Create, .{});
    router.delete("/api/account", api.Account.Delete, .{});
    router.get("/api/account/search", api.Account.Search, .{});
    router.get("/api/account/:id", api.Account.GetId, .{});

    router.post("/api/operation", api.Operation.Create, .{});
    router.delete("/api/operation", api.Operation.Delete, .{});
    router.get("/api/operation/search", api.Operation.Search, .{});
    router.post("/api/operation/draft", api.Operation.Draft, .{});
    router.post("/api/operation/recurring", api.Operation.Recurring, .{});

    router.get("/api/money/total", api.Money.Total, .{});

    // HTMX UI: `/` is the only full page; `/ui/*` answer fragments.
    router.get("/", web.handlers_cards.index, .{});
    router.get("/ui/accounts/page", web.handlers_cards.accountsPage, .{});
    router.get("/ui/cards/:id", web.handlers_cards.card, .{});
    router.get("/ui/cards/:id/ops", web.handlers_cards.cardOps, .{});
    router.delete("/ui/operations/:id", web.delete_handlers.operationDelete, .{});
    router.delete("/ui/accounts/:id", web.delete_handlers.accountDelete, .{});
    router.get("/ui/accounts/new", web.account_forms.accountNew, .{});
    router.post("/ui/accounts", web.account_forms.accountCreate, .{});
    router.get("/ui/modal/close", web.account_forms.modalClose, .{});
    router.get("/ui/operations/new", web.operation_forms.operationNew, .{});
    router.post("/ui/operations", web.operation_forms.operationCreate, .{});
    router.get(web.static.htmx_path, web.static.htmxJs, .{});
    router.get(web.static.css_path, web.static.appCss, .{});

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
        _ = try _pool.exec(internal.types.Operation.MIGRATE_DRAFT, .{});
    }
}

const std = @import("std");
const process = std.process;
const config = @import("config.zig");
const httpz = @import("httpz");
const pg = @import("pg");

const internal = @import("internal");
const routes = internal.routes;
const api = routes.api;
const web = internal.web;

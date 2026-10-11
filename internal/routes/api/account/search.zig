// This is a global search function that takes in multiple parameters. It can search
// accounts using the following:
// - name
// - initial_balance
pub fn search(root: routes.App, req: *httpz.Request, res: *httpz.Response) !void {
    errdefer {
        res.setStatus(.internal_server_error);
        res.json(.{ .err = "There was an issue with the internal server." }, .{}) catch {
            std.log.err("failure to log error to end-user", .{});
        };
    }
    if (root.p == null) {
        std.log.warn("no database available, search not possible", .{});
        return error.DatabaseNotAvailable;
    }
    const p = root.p.?;

    const map = try req.query();
    const name = try routes.Contract(map, "name", .{ .string = "" });
    const initial_balance = try routes.Contract(map, "initial_balance", .{ .float = 0.00 });

    // Parameter Order:
    // - name
    // - initial_balance
    const query =
        \\ SELECT id, created_at, updated_at, deleted_at, initial_balance, name FROM
        \\  account WHERE ($1 ::text = '' OR name ILIKE '%' || $1 ::text || '%')
        \\  AND ($2 ::float8 = 0.00 OR initial_balance = $2)
        \\  AND deleted_at IS NULL
    ;

    const rows = try p.queryOpts(query, .{
        name.string,
        initial_balance.float,
    }, .{ .column_names = true });
    defer rows.deinit();

    var list: std.ArrayList(types.Account) = .empty;
    var mapper = rows.mapper(types.Account, .{
        .dupe = true,
        .allocator = res.arena,
    });
    while (try mapper.next()) |acc| {
        try list.append(req.arena, acc);
    }

    res.setStatus(.ok);
    try res.json(list.items, .{});
}

const routes = @import("../../root.zig");
const types = @import("../../../types/root.zig");

const std = @import("std");
const json = std.json;

const httpz = @import("httpz");

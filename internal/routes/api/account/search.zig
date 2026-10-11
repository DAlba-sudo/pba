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

    const accounts = try types.Account.search(p, res.arena, .{
        .name = name.string.?,
        .initial_balance = initial_balance.float.?,
    });

    res.setStatus(.ok);
    try res.json(accounts, .{});
}

const routes = @import("../../root.zig");
const types = @import("../../../types/root.zig");

const std = @import("std");

const httpz = @import("httpz");

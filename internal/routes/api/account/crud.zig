pub fn delete(root: routes.App, req: *httpz.Request, res: *httpz.Response) !void {
    if (root.p == null) {
        std.log.err("database pool is not initialized, cannot delete account", .{});
        return error.DatabaseNotInitialized;
    }
    const p = root.p.?;

    const map = req.formData() catch |err| {
        std.log.err("failed to parse query parameters (err: {s})", .{@errorName(err)});
        return err;
    };

    const id = try routes.Contract(map, "id", .{ .int = null });

    try types.Account.delete_by_id(p, id.int.?);
    res.setStatus(.ok);
}

pub fn create(root: routes.App, req: *httpz.Request, res: *httpz.Response) !void {
    if (root.p == null) {
        std.log.err("database pool is not initialized, cannot create account", .{});
        return error.DatabaseNotInitialized;
    }
    const p = root.p.?;

    const map = req.formData() catch |err| {
        std.log.err("failed to parse query parameters (err: {s})", .{@errorName(err)});
        return err;
    };

    const name = try routes.Contract(map, "name", .{ .string = null });
    const initial_budget = try routes.Contract(map, "initial_balance", .{ .float = null });

    const created_account = try types.Account.create(p, req.arena, name.string.?, initial_budget.float.?);
    res.setStatus(.created);
    try res.json(created_account, .{});
}

pub fn get_id(root: routes.App, req: *httpz.Request, res: *httpz.Response) !void {
    errdefer {
        res.setStatus(.internal_server_error);
        res.json(.{ .err = "Could not retrieve an account." }, .{}) catch {
            std.log.err("failure to log error to end-user", .{});
        };
    }
    if (root.p == null) {
        std.log.warn("no database available, search not possible", .{});
        return error.DatabaseNotAvailable;
    }
    const p = root.p.?;

    const _id = req.param("id");
    if (_id) |id| {
        const account_id = try std.fmt.parseInt(i32, id, 10);
        const account = try types.Account.get_by_id(p, req.arena, account_id);
        if (account) |acc| {
            res.setStatus(.ok);
            try res.json(acc, .{});
            return;
        }
    }

    res.setStatus(.not_found);
    return error.AccountNotFound;
}

const routes = @import("../../root.zig");
const types = @import("../../../types/root.zig");

const std = @import("std");
const json = std.json;

const httpz = @import("httpz");

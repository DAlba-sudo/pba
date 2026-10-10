const httpz = @import("httpz");
const pg = @import("pg");
const types = @import("../types/root.zig");
const analysis = @import("../analysis/root.zig");
const std = @import("std");
const json = std.json;
const time = @import("../time/root.zig");
const VERSION = @import("../root.zig").VERSION;

pub const App = struct {
    p: ?*pg.Pool,
};
pub const Server = httpz.Server(App);

pub fn health(_: App, _: *httpz.Request, res: *httpz.Response) !void {
    const info: struct {
        version: []const u8 = VERSION,
    } = .{};

    json.Stringify.value(info, .{}, res.writer()) catch |err| {
        std.log.err("failed to write general health info (err: {s})", .{@errorName(err)});
        return err;
    };

    res.setStatus(.ok);
}

// These functions are all related to the API. These cause side-effects.
pub const api = struct {
    // Requires a name and an initial acocunt balance, parseable as a float.
    pub fn create_account(root: App, req: *httpz.Request, res: *httpz.Response) !void {
        if (root.p == null) {
            std.log.err("database pool is not initialized, cannot create account", .{});
            return error.DatabaseNotInitialized;
        }
        const p = root.p.?;

        const map = req.formData() catch |err| {
            std.log.err("failed to parse query parameters (err: {s})", .{@errorName(err)});
            return err;
        };

        // contracts
        const name = try Contract(map, "name", .{ .string = null });
        const initial_budget = try Contract(map, "initial_balance", .{ .float = null });

        const created_account = try types.Account.create(p, req.arena, name.string.?, initial_budget.float.?);
        res.setStatus(.created);
        json.Stringify.value(created_account, .{}, res.writer()) catch |err| {
            std.log.err("failed to write created account (err: {s})", .{@errorName(err)});
            return err;
        };
    }

    pub fn delete_account(root: App, req: *httpz.Request, res: *httpz.Response) !void {
        if (root.p == null) {
            std.log.err("database pool is not initialized, cannot delete account", .{});
            return error.DatabaseNotInitialized;
        }
        const p = root.p.?;

        const map = req.formData() catch |err| {
            std.log.err("failed to parse query parameters (err: {s})", .{@errorName(err)});
            return err;
        };

        // contracts
        const id = try Contract(map, "id", .{ .int = null });

        try types.Account.delete_by_id(p, id.int.?);
        res.setStatus(.ok);
    }

    pub fn create_operation(root: App, req: *httpz.Request, res: *httpz.Response) !void {
        if (root.p == null) {
            std.log.err("database pool is not initialized, cannot create operation", .{});
            return error.DatabaseNotInitialized;
        }
        const p = root.p.?;

        const map = req.formData() catch |err| {
            std.log.err("failed to parse query parameters (err: {s})", .{@errorName(err)});
            return err;
        };

        // contracts
        const account_id = try Contract(map, "account_id", .{ .int = null });
        const amount = try Contract(map, "amount", .{ .float = null });
        const title = try Contract(map, "title", .{ .string = null });
        const comment = try Contract(map, "comment", .{ .string = "" });
        const date = try Contract(map, "date", .{ .string = null });

        const timestamp: i64 = time.parseIsoDateToTimestamp(date.string.?) catch |err| {
            std.log.err("failed to parse date string (err: {s})", .{@errorName(err)});
            return err;
        };

        const created_operation = try types.Operation.create(p, req.arena, amount.float.?, timestamp, title.string.?, comment.string.?, account_id.int.?);
        res.setStatus(.created);
        json.Stringify.value(created_operation, .{}, res.writer()) catch |err| {
            std.log.err("failed to write created operation (err: {s})", .{@errorName(err)});
            return err;
        };
    }

    pub fn delete_operation(root: App, req: *httpz.Request, res: *httpz.Response) !void {
        if (root.p == null) {
            std.log.err("database pool is not initialized, cannot delete operation", .{});
            return error.DatabaseNotInitialized;
        }
        const p = root.p.?;

        const map = req.formData() catch |err| {
            std.log.err("failed to parse query parameters (err: {s})", .{@errorName(err)});
            return err;
        };

        // contracts
        const id = try Contract(map, "id", .{ .int = null });

        try types.Operation.delete_by_id(p, id.int.?);
        res.setStatus(.ok);
    }

    pub fn search_operations_by_title(root: App, req: *httpz.Request, res: *httpz.Response) !void {
        if (root.p == null) {
            std.log.err("database pool is not initialized, cannot search operations", .{});
            return error.DatabaseNotInitialized;
        }
        const p = root.p.?;

        const map = req.query() catch |err| {
            std.log.err("failed to parse query parameters (err: {s})", .{@errorName(err)});
            return err;
        };

        // contracts
        const title = try Contract(map, "title", .{ .string = "" });
        const limit = try Contract(map, "limit", .{ .int = 10 });
        const pointer = try Contract(map, "pointer", .{ .int = 0 });

        const operations = try types.Operation.search_by_title(p, req.arena, title.string.?, limit.int.?, pointer.int.?);
        res.setStatus(.ok);
        try res.json(operations, .{});
    }

    pub fn total_money_as_of(root: App, req: *httpz.Request, res: *httpz.Response) !void {
        const map = try req.formData();

        const account_id = try Contract(map, "account_id", .{ .int = null });
        const date = try Contract(map, "date", .{ .string = null });

        const timestamp = try time.parseIsoDateToTimestamp(date.string.?);

        const sum = analysis.total_money_as_of(root.p.?, req.arena, timestamp, account_id.int.?) catch |err| {
            std.log.err("failed to calculate total money as of now (err: {s})", .{@errorName(err)});
            return err;
        };

        return res.json(.{ .total = sum }, .{}) catch |err| {
            std.log.err("failed to write total money as of now (err: {s})", .{@errorName(err)});
            return err;
        };
    }
};

const Payload = union(enum) {
    int: ?i32,
    float: ?f32,
    string: ?[]const u8,
};

pub fn Contract(map: *httpz.key_value.StringKeyValue, key: []const u8, result: Payload) !Payload {
    const v = map.get(key);

    var p: Payload = switch (result) {
        .string => Payload{ .string = result.string },
        .int => Payload{ .int = result.int },
        .float => Payload{ .float = result.float },
    };

    if (v) |value| {
        switch (result) {
            .string => {
                if (value.len == 0) {
                    p = Payload{ .string = null };
                } else {
                    p = Payload{ .string = value };
                }
            },
            .int => p = Payload{ .int = std.fmt.parseInt(i32, value, 10) catch blk: {
                break :blk null;
            } },
            .float => p = Payload{ .float = std.fmt.parseFloat(f32, value) catch blk: {
                break :blk null;
            } },
        }

        const has_value = switch (result) {
            .string => p.string != null,
            .int => p.int != null,
            .float => p.float != null,
        };

        if (has_value) {
            return p;
        }
    }

    const has_value = switch (result) {
        .string => p.string != null,
        .int => p.int != null,
        .float => p.float != null,
    };

    if (has_value) {
        return p;
    }

    return error.ContractViolation;
}

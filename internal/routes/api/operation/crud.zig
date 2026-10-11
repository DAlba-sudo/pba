pub fn create(root: routes.App, req: *httpz.Request, res: *httpz.Response) !void {
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
    const account_id = try routes.Contract(map, "account_id", .{ .int = null });
    const amount = try routes.Contract(map, "amount", .{ .float = null });
    const title = try routes.Contract(map, "title", .{ .string = null });
    const comment = try routes.Contract(map, "comment", .{ .string = "" });
    const date = try routes.Contract(map, "date", .{ .string = null });
    const date_as_int: i32 = try time.parseHtmlDateToPgDate(date.string.?);

    const created_operation = types.Operation.create(
        p,
        req.arena,
        amount.float.?,
        date_as_int,
        title.string.?,
        comment.string.?,
        account_id.int.?,
    ) catch |err| {
        std.log.err("failed to create operation in request (err: {s})", .{@errorName(err)});
        return err;
    };
    res.setStatus(.created);
    json.Stringify.value(created_operation, .{}, res.writer()) catch |err| {
        std.log.err("failed to write created operation (err: {s})", .{@errorName(err)});
        return err;
    };
}

pub fn delete(root: routes.App, req: *httpz.Request, res: *httpz.Response) !void {
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
    const id = try routes.Contract(map, "id", .{ .int = null });

    try types.Operation.delete_by_id(p, id.int.?);
    res.setStatus(.ok);
}

const routes = @import("../../root.zig");
const types = @import("../../../types/root.zig");
const time = @import("../../../time/root.zig");

const std = @import("std");
const json = std.json;

const httpz = @import("httpz");

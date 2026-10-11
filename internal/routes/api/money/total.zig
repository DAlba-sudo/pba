pub fn total(root: routes.App, req: *httpz.Request, res: *httpz.Response) !void {
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

    // Contracts
    const map = try req.query();
    var account_id = try routes.Contract(map, "account_id", .{ .int = -1 });
    var date = try routes.Contract(map, "date", .{ .string = "" });

    // Normalization for the function
    if (account_id.int == -1) {
        account_id.int = null;
    }

    if (date.string.?.len == 0) {
        date.string = null;
    }

    res.setStatus(.ok);
    try res.json(.{
        .sum = try analysis.Money.money(p, account_id.int, date.string),
    }, .{});
}

const std = @import("std");
const routes = @import("../../root.zig");
const httpz = @import("httpz");
const pg = @import("pg");
const analysis = @import("../../../analysis/root.zig");

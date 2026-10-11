// This is a global search function that takes in multiple parameters. It can search
// operations using the following:
// - title
// - account_id
// - date
// - comment
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
    const title = try routes.Contract(map, "title", .{ .string = "" });
    const comment = try routes.Contract(map, "comment", .{ .string = "" });
    const date = try routes.Contract(map, "date", .{ .string = "" });
    const account_id = try routes.Contract(map, "account_id", .{ .int = -1 });

    const date_str = date.string.?;
    const operations = try types.Operation.search(p, res.arena, .{
        .title = title.string.?,
        .comment = comment.string.?,
        .date = if (date_str.len > 0) try time.parseHtmlDateToPgDate(date_str) else null,
        .account_id = if (account_id.int.? == -1) null else account_id.int.?,
    });

    res.setStatus(.ok);
    try res.json(operations, .{});
}

const routes = @import("../../root.zig");
const types = @import("../../../types/root.zig");
const time = @import("../../../time/root.zig");

const std = @import("std");

const httpz = @import("httpz");

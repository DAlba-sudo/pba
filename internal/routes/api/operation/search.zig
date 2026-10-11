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

    var date_as_int: i32 = -1;
    if (date.string.?.len > 0) {
        date_as_int = try time.parseHtmlDateToPgDate(date.string.?);
    }

    // Parameter Order:
    // - title
    // - comment
    // - date (text)
    // - date (cast)
    // - account_id
    const query =
        \\ SELECT id, created_at, updated_at, deleted_at, value, date, title, comment, account_id FROM
        \\  operation WHERE deleted_at IS NULL
        \\  AND ($1 ::text = '' OR title ILIKE '%' || $1 ::text || '%')
        \\  AND ($2 ::text = '' OR comment ILIKE '%' || $2 ::text || '%')
        \\  AND ($3 ::text = '' OR date = $4 )
        \\  AND ($5 ::int = -1 OR account_id = $5)
    ;

    const rows = try p.queryOpts(query, .{
        title.string,
        comment.string,
        date.string,
        date_as_int,
        account_id.int,
    }, .{ .column_names = true });
    defer rows.deinit();

    var list: std.ArrayList(types.Operation) = .empty;
    var mapper = rows.mapper(types.Operation, .{
        .dupe = true,
        .allocator = res.arena,
    });
    while (try mapper.next()) |op| {
        try list.append(req.arena, op);
    }

    res.setStatus(.ok);
    try res.json(list.items, .{});
}

const routes = @import("../../root.zig");
const types = @import("../../../types/root.zig");
const time = @import("../../../time/root.zig");

const std = @import("std");
const json = std.json;

const httpz = @import("httpz");

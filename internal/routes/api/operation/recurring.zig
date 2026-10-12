// POST /api/operation/recurring: creates one independent operation per date of
// a weekly or monthly series, atomically. Form fields: account_id, amount,
// title, comment, date (blank = today), draft, repeat (weekly|monthly), until,
// weekdays (e.g. "mon,thu"; weekly only).
//
// 201 with the created operations in ascending date order, 400 `{"err"}` on
// invalid input, 404 `{"err"}` for an unknown or deleted account.
pub fn recurring(root: routes.App, req: *httpz.Request, res: *httpz.Response) !void {
    errdefer {
        res.setStatus(.internal_server_error);
        res.json(.{ .err = "There was an issue with the internal server." }, .{}) catch {
            std.log.err("failure to log error to end-user", .{});
        };
    }
    const p = root.p orelse {
        std.log.err("database pool is not initialized, cannot create operations", .{});
        return error.DatabaseNotInitialized;
    };

    const map = try req.formData();
    const account_id = routes.Contract(map, "account_id", .{ .int = null }) catch
        return routes.jsonError(res, .bad_request, "account_id: Must be an integer.");
    const amount = routes.Contract(map, "amount", .{ .float = null }) catch
        return routes.jsonError(res, .bad_request, "amount: Must be a number.");
    const title = routes.Contract(map, "title", .{ .string = null }) catch
        return routes.jsonError(res, .bad_request, "title: Required.");
    const comment = map.get("comment") orelse "";
    const draft = crud.parseOptionalDraft(map) orelse return routes.jsonError(res, .bad_request, crud.msg_draft);

    const date = map.get("date") orelse "";
    const start = if (date.len == 0) time.todayPgDate(root.io) else time.parseHtmlDateToPgDate(date) catch
        return routes.jsonError(res, .bad_request, "date: Enter a date as YYYY-MM-DD.");

    const v = try time.recurrence.validate(
        res.arena,
        start,
        map.get("repeat") orelse "",
        map.get("until") orelse "",
        time.recurrence.Weekdays.parse(map.get("weekdays") orelse ""),
    );
    if (v.firstError()) |e| {
        return routes.jsonError(res, .bad_request, try std.fmt.allocPrint(res.arena, "{s}: {s}", .{ e.field, e.msg }));
    }

    const created = try types.Operation.create_many(
        p,
        res.arena,
        amount.float.?,
        v.days,
        title.string.?,
        comment,
        account_id.int.?,
        draft,
    ) orelse return routes.jsonError(res, .not_found, "account_id: Account not found.");
    res.setStatus(.created);
    try res.json(created, .{});
}

const routes = @import("../../root.zig");
const types = @import("../../../types/root.zig");
const time = @import("../../../time/root.zig");
const crud = @import("crud.zig");

const std = @import("std");
const httpz = @import("httpz");

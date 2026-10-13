// GET /api/money/series?from=YYYY-MM-DD&to=YYYY-MM-DD[&account_id=N][&by_account=1]
// Responds `{"points":[[unix_seconds, balance], ...],"with_drafts":[balance, ...]}`,
// one point per day. `points` excludes drafts; `with_drafts[i]` is the balance
// on the same day as `points[i]` with every live draft counted.
// With `by_account=1` and no `account_id`, it also adds
// `"accounts":[{"id":N,"name":"...","balance":[balance, ...]}, ...]` (aligned
// with `points`) and `"truncated":true` when only the first accounts are listed.
pub fn series(root: routes.App, req: *httpz.Request, res: *httpz.Response) !void {
    const p = root.p orelse return routes.jsonError(res, .service_unavailable, "Database not connected.");

    const map = try req.query();
    const from_s = map.get("from") orelse return routes.jsonError(res, .bad_request, "from is required.");
    const to_s = map.get("to") orelse return routes.jsonError(res, .bad_request, "to is required.");
    const from = time.parseHtmlDateToPgDate(from_s) catch return routes.jsonError(res, .bad_request, "from must be YYYY-MM-DD.");
    const to = time.parseHtmlDateToPgDate(to_s) catch return routes.jsonError(res, .bad_request, "to must be YYYY-MM-DD.");
    const account_id: ?i32 = if (map.get("account_id")) |s| std.fmt.parseInt(i32, s, 10) catch null else null;
    const by_account = account_id == null and std.mem.eql(u8, map.get("by_account") orelse "", "1");

    const pts = analysis.Money.series(p, res.arena, account_id, from, to) catch |err| switch (err) {
        error.InvalidRange => return routes.jsonError(res, .bad_request, "Range must be ascending and under 10 years."),
        else => {
            std.log.err("failed to build money series (err: {s})", .{@errorName(err)});
            return routes.jsonError(res, .internal_server_error, "There was an issue with the internal server.");
        },
    };

    const breakdown: ?analysis.Money.Breakdown = if (by_account)
        analysis.Money.seriesByAccount(p, res.arena, from, to) catch |err| {
            std.log.err("failed to build money series by account (err: {s})", .{@errorName(err)});
            return routes.jsonError(res, .internal_server_error, "There was an issue with the internal server.");
        }
    else
        null;

    const w = res.writer();
    try w.writeAll("{\"points\":[");
    for (pts, 0..) |pt, i| {
        if (i != 0) try w.writeByte(',');
        const unix = (@as(i64, pt.day) + 10957) * 86400;
        try w.print("[{d},{d}]", .{ unix, pt.balance });
    }
    try w.writeAll("],\"with_drafts\":[");
    for (pts, 0..) |pt, i| {
        if (i != 0) try w.writeByte(',');
        try w.print("{d}", .{pt.with_drafts});
    }
    try w.writeByte(']');
    if (breakdown) |b| {
        try w.writeAll(",\"accounts\":[");
        for (b.accounts, 0..) |a, i| {
            if (i != 0) try w.writeByte(',');
            try w.print("{{\"id\":{d},\"name\":", .{a.id});
            try std.json.Stringify.value(a.name, .{}, w);
            try w.writeAll(",\"balance\":[");
            for (a.balance, 0..) |v, j| {
                if (j != 0) try w.writeByte(',');
                try w.print("{d}", .{v});
            }
            try w.writeAll("]}");
        }
        try w.writeByte(']');
        if (b.truncated) try w.writeAll(",\"truncated\":true");
    }
    try w.writeByte('}');
    res.content_type = .JSON;
}

const std = @import("std");
const httpz = @import("httpz");
const routes = @import("../../root.zig");
const analysis = @import("../../../analysis/root.zig");
const time = @import("../../../time/root.zig");

//! Balance-over-time page (`/graph`); the chart itself is drawn by static/graph.js
//! from `/api/money/series`.
const std = @import("std");
const httpz = @import("httpz");
const App = @import("../routes/root.zig").App;
const time = @import("../time/root.zig");
const forms = @import("forms.zig");
const render = @import("render.zig");
const view = @import("view.zig");

/// GET /graph: bounds default to the last 90 days; y bounds stay empty (auto).
pub fn page(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    res.header("Cache-Control", "no-store");
    const p = app.p orelse return render.flash(res, .service_unavailable, view.msg_no_db);
    const today = time.todayPgDate(app.io);
    const f = forms.Filters.fromRequest(req, today) catch
        return render.flash(res, .internal_server_error, "Something went wrong, please try again.");
    const header = view.buildHeader(p, res.arena, f) catch
        return render.flash(res, .internal_server_error, "Something went wrong, please try again.");

    var from_buf: [10]u8 = undefined;
    var to_buf: [10]u8 = undefined;
    const ctx = .{
        .accounts = header.accounts,
        .all_selected = header.all_selected,
        .from = try res.arena.dupe(u8, time.formatPgDate(today - 90, &from_buf)),
        .to = try res.arena.dupe(u8, time.formatPgDate(today, &to_buf)),
    };
    render.send(app, res, "graph", true, ctx) catch
        render.flash(res, .internal_server_error, "Something went wrong, please try again.");
}

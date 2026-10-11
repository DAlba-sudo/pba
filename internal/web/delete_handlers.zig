//! Soft deletes from the dashboard. Filters arrive in the query (htmx sends
//! DELETE params in the URL); missing or already deleted rows answer a 404 flash.
const std = @import("std");
const httpz = @import("httpz");
const App = @import("../routes/root.zig").App;
const types = @import("../types/root.zig");
const render = @import("render.zig");
const cards = @import("handlers_cards.zig");

/// DELETE /ui/operations/:id : re-renders its account's card (first page, `oq` kept).
/// BLOCKED: needs `Operation.get_by_id` to compile (phase-1 boundary change requested).
pub fn operationDelete(_: App, _: *httpz.Request, res: *httpz.Response) !void {
    res.setStatus(.not_implemented);
}

/// DELETE /ui/accounts/:id : the `/` fragment after deletion. A filter on the
/// deleted account resets to all accounts and the new URL is pushed.
pub fn accountDelete(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    const p = app.p orelse return cards.noDatabase(res);
    const id = cards.pathId(req) orelse return notFound(res, "Account");
    var f = cards.filtersFrom(app, req) catch |err| return cards.fail(res, "parse filters", err);

    const deleted = types.Account.delete_live(p, id) catch |err| return cards.fail(res, "delete account", err);
    if (!deleted) return notFound(res, "Account");
    if (f.account == id) {
        f.account = null;
        const query = f.toQuery(res.arena) catch |err| return cards.fail(res, "build url", err);
        const url = std.fmt.allocPrint(res.arena, "/{s}{s}", .{ if (query.len > 0) "?" else "", query }) catch |err|
            return cards.fail(res, "build url", err);
        res.header("HX-Push-Url", url);
    }
    cards.renderDashboardFragment(app, res, f);
}

fn notFound(res: *httpz.Response, comptime what: []const u8) void {
    render.flash(res, .not_found, what ++ " not found.");
}

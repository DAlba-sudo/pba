//! Soft deletes and the draft toggle from the dashboard. Delete filters arrive
//! in the query (htmx sends DELETE params in the URL); missing or already
//! deleted rows answer a 404 flash.
const std = @import("std");
const httpz = @import("httpz");
const App = @import("../routes/root.zig").App;
const types = @import("../types/root.zig");
const time = @import("../time/root.zig");
const forms = @import("forms.zig");
const render = @import("render.zig");
const cards = @import("handlers_cards.zig");

/// DELETE /ui/operations/:id : re-renders its account's card (first page, `oq` kept).
pub fn operationDelete(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    const p = app.p orelse return cards.noDatabase(res);
    const id = cards.pathId(req) orelse return notFound(res, "Operation");
    const f = cards.filtersFrom(app, req) catch |err| return cards.fail(res, "parse filters", err);
    const oq = cards.cardQuery(req) catch |err| return cards.fail(res, "parse query", err);

    const op = types.Operation.get_by_id(p, res.arena, id) catch |err| return cards.fail(res, "get operation", err);
    const account_id = (op orelse return notFound(res, "Operation")).account_id;
    const deleted = types.Operation.delete_live(p, id) catch |err| return cards.fail(res, "delete operation", err);
    if (!deleted) return notFound(res, "Operation");
    cards.renderCardFragment(app, res, account_id, f, oq);
}

/// Most operations one bulk request may change (bounds `max_form_count`).
const max_bulk = 200;

/// POST body of a card bulk action on `/ui/cards/:id/operations/...`.
pub const BulkForm = struct {
    account_id: i32,
    map: *const forms.StringKeyValue,
    /// Checked `sel` operation ids (1..max_bulk).
    ids: []const i32,
    f: forms.Filters,
    oq: []const u8,
};

/// Parses a bulk action form; on bad input answers a flash and returns null.
pub fn bulkForm(app: App, req: *httpz.Request, res: *httpz.Response) ?BulkForm {
    const account_id = cards.pathId(req) orelse return answered(notFound(res, "Account"));
    const map = req.formData() catch return answered(render.flash(res, .bad_request, "Invalid form data."));
    const f = forms.Filters.fromMap(res.arena, map, time.todayPgDate(app.io)) catch |err|
        return answered(cards.fail(res, "parse filters", err));
    const collected = forms.collectIds(res.arena, map, "sel", max_bulk) catch |err|
        return answered(cards.fail(res, "collect ids", err));
    const ids = switch (collected) {
        .ok => |ids| ids,
        .invalid_id => return answered(render.flash(res, .bad_request, "Invalid operation id.")),
        .too_many => return answered(render.flash(res, .bad_request, "Too many operations selected.")),
        .none => return answered(render.flash(res, .bad_request, "No operations selected.")),
    };
    return .{
        .account_id = account_id,
        .map = map,
        .ids = ids,
        .f = f,
        .oq = std.mem.trim(u8, map.get("oq") orelse "", " \t\r\n"),
    };
}

/// POST /ui/cards/:id/operations/delete (form `sel`=<operation id>, repeated,
/// plus filters and `oq`): soft-deletes the selected operations of that
/// account and re-renders its card. Ids from other accounts are ignored.
pub fn operationsDelete(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    const p = app.p orelse return cards.noDatabase(res);
    const b = bulkForm(app, req, res) orelse return;
    _ = types.Operation.delete_live_many(p, b.account_id, b.ids) catch |err| return cards.fail(res, "delete operations", err);
    cards.renderCardFragment(app, res, b.account_id, b.f, b.oq);
}

/// POST /ui/cards/:id/operations/draft (like `operationsDelete`, plus
/// `draft`=true|false): sets the flag on the selected operations.
pub fn operationsDraft(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    const p = app.p orelse return cards.noDatabase(res);
    const b = bulkForm(app, req, res) orelse return;
    const draft = types.Operation.parseDraft(b.map.get("draft") orelse "") orelse
        return render.flash(res, .bad_request, "Invalid draft flag.");
    _ = types.Operation.set_draft_many(p, b.account_id, b.ids, draft) catch |err| return cards.fail(res, "set draft", err);
    cards.renderCardFragment(app, res, b.account_id, b.f, b.oq);
}

/// POST /ui/operations/:id/draft (form `draft`=true|false, filters, `oq`):
/// sets the flag and re-renders the card like `operationDelete`. POST params
/// arrive in the body, so filters are read from the form.
pub fn operationDraft(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    const p = app.p orelse return cards.noDatabase(res);
    const id = cards.pathId(req) orelse return notFound(res, "Operation");
    const map = req.formData() catch return render.flash(res, .bad_request, "Invalid form data.");
    const draft = types.Operation.parseDraft(map.get("draft") orelse "") orelse
        return render.flash(res, .bad_request, "Invalid draft flag.");
    const f = forms.Filters.fromMap(res.arena, map, time.todayPgDate(app.io)) catch |err| return cards.fail(res, "parse filters", err);
    const oq = std.mem.trim(u8, map.get("oq") orelse "", " \t\r\n");

    const op = types.Operation.set_draft(p, res.arena, id, draft) catch |err| return cards.fail(res, "set draft", err);
    cards.renderCardFragment(app, res, (op orelse return notFound(res, "Operation")).account_id, f, oq);
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

/// The response is already written: no form.
fn answered(_: void) ?BulkForm {
    return null;
}

fn notFound(res: *httpz.Response, comptime what: []const u8) void {
    render.flash(res, .not_found, what ++ " not found.");
}

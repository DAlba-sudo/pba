//! Dashboard page (`/`), account pages and card fragments. Every handler answers
//! errors with a flash fragment, never httpz's plain-text 500.
const std = @import("std");
const httpz = @import("httpz");
const pg = @import("pg");
const App = @import("../routes/root.zig").App;
const Account = @import("../types/root.zig").Account;
const time = @import("../time/root.zig");
const forms = @import("forms.zig");
const render = @import("render.zig");
const view = @import("view.zig");

const Filters = forms.Filters;

pub fn filtersFrom(app: App, req: *httpz.Request) !Filters {
    return Filters.fromRequest(req, time.todayPgDate(app.io));
}

/// Trimmed card search text (`oq`), "" when absent.
pub fn cardQuery(req: *httpz.Request) ![]const u8 {
    return std.mem.trim(u8, (try req.query()).get("oq") orelse "", " \t\r\n");
}

/// `:id` path parameter as a positive id.
pub fn pathId(req: *httpz.Request) ?i32 {
    return forms.parseId(req.param("id") orelse "");
}

pub fn fail(res: *httpz.Response, what: []const u8, err: anyerror) void {
    std.log.err("failed to {s} (err: {s})", .{ what, @errorName(err) });
    render.flash(res, .internal_server_error, "Something went wrong, please try again.");
}

pub fn noDatabase(res: *httpz.Response) void {
    render.flash(res, .service_unavailable, view.msg_no_db);
}

/// Template context shared by the full page (`dashboard`) and its fragment (`cards`).
const Dashboard = struct {
    header: view.HeaderView,
    total: view.Total,
    page: view.AccountsPage,
    more: bool,
    show_empty: bool,
    graph: GraphView,
};

/// Default bounds of the balance chart: the last 90 days.
const GraphView = struct { from: []const u8, to: []const u8 };

fn buildGraph(app: App, arena: std.mem.Allocator) !GraphView {
    const today = time.todayPgDate(app.io);
    var from_buf: [10]u8 = undefined;
    var to_buf: [10]u8 = undefined;
    return .{
        .from = try arena.dupe(u8, time.formatPgDate(today - 90, &from_buf)),
        .to = try arena.dupe(u8, time.formatPgDate(today, &to_buf)),
    };
}

fn buildDashboard(app: App, arena: std.mem.Allocator, f: Filters) !Dashboard {
    const p = app.p orelse return .{
        .header = view.offlineHeader(f),
        .total = view.offline_total,
        .page = .{ .cards = &.{}, .has_more = false, .next_query = "", .empty = view.msg_no_db },
        .more = false,
        .show_empty = true,
        .graph = try buildGraph(app, arena),
    };
    const page = try view.buildAccountsPage(p, arena, f, null);
    return .{
        .header = try view.buildHeader(p, arena, f),
        .total = try view.buildTotal(p, arena, f),
        .page = page,
        .more = page.has_more,
        .show_empty = page.empty.len > 0,
        .graph = try buildGraph(app, arena),
    };
}

/// GET / : full page, or the `#cards` fragment with OOB header parts for htmx.
pub fn index(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    res.header("Vary", "HX-Request, HX-History-Restore-Request");
    res.header("Cache-Control", "no-store");
    const f = filtersFrom(app, req) catch |err| return fail(res, "parse dashboard filters", err);
    if (render.isFragment(req)) return renderDashboardFragment(app, res, f);
    const d = buildDashboard(app, res.arena, f) catch |err| return fail(res, "build dashboard", err);
    render.send(app, res, "dashboard", true, d) catch |err| fail(res, "render dashboard", err);
}

/// `#cards` inner HTML for `f` plus OOB `#total`, `#account-menu`, `#date-menu`.
pub fn renderDashboardFragment(app: App, res: *httpz.Response, f: Filters) void {
    if (app.p == null) return noDatabase(res);
    const d = buildDashboard(app, res.arena, f) catch |err| return fail(res, "build dashboard", err);
    render.send(app, res, "cards", false, d) catch |err| fail(res, "render dashboard fragment", err);
}

/// GET /ui/accounts/page?cursor=<last id> : next cards plus a new sentinel if more.
pub fn accountsPage(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    const p = app.p orelse return noDatabase(res);
    const f = filtersFrom(app, req) catch |err| return fail(res, "parse filters", err);
    const query = req.query() catch |err| return fail(res, "parse query", err);
    const after = forms.parseId(query.get("cursor") orelse "") orelse
        return render.flash(res, .bad_request, "Invalid cursor.");
    const page = view.buildAccountsPage(p, res.arena, f, after) catch |err| return fail(res, "build accounts page", err);
    render.send(app, res, "accounts_page", false, .{ .page = page, .more = page.has_more, .show_empty = false }) catch |err|
        fail(res, "render accounts page", err);
}

/// GET /ui/cards/:id : one card (first page of operations) plus OOB `#total`.
pub fn card(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    const id = pathId(req) orelse return render.flash(res, .not_found, "Account not found.");
    const f = filtersFrom(app, req) catch |err| return fail(res, "parse filters", err);
    const oq = cardQuery(req) catch |err| return fail(res, "parse query", err);
    renderCardFragment(app, res, id, f, oq);
}

/// Card `id` as an outerHTML fragment (404 flash if the account is gone). The OOB
/// header total is omitted when the account filter excludes this card.
pub fn renderCardFragment(app: App, res: *httpz.Response, id: i32, f: Filters, oq: []const u8) void {
    const p = app.p orelse return noDatabase(res);
    cardFragment(app, p, res, id, f, oq) catch |err| fail(res, "render card", err);
}

fn cardFragment(app: App, p: *pg.Pool, res: *httpz.Response, id: i32, f: Filters, oq: []const u8) !void {
    const a = try Account.get_by_id(p, res.arena, id) orelse
        return render.flash(res, .not_found, "Account not found.");
    const c = try view.buildCard(p, res.arena, a, f, oq);
    const show_total = f.account == null or f.account == id;
    const total = if (show_total) try view.buildTotal(p, res.arena, f) else view.offline_total;
    try render.send(app, res, "card_fragment", false, .{ .card = c, .total = total, .show_total = show_total });
}

/// GET /ui/cards/:id/ops[?cursor=<date>_<id>] : the whole `<tbody>` (no cursor) or
/// only the next rows (cursor), each ending with a "Load more" row if more.
pub fn cardOps(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    const p = app.p orelse return noDatabase(res);
    const id = pathId(req) orelse return render.flash(res, .not_found, "Account not found.");
    const f = filtersFrom(app, req) catch |err| return fail(res, "parse filters", err);
    const oq = cardQuery(req) catch |err| return fail(res, "parse query", err);
    const query = req.query() catch |err| return fail(res, "parse query", err);
    const cursor: ?forms.OpCursor = if (query.get("cursor")) |s|
        forms.parseOpCursor(s) catch return render.flash(res, .bad_request, "Invalid cursor.")
    else
        null;
    cardOpsFragment(app, p, res, id, f, oq, cursor) catch |err| fail(res, "render card operations", err);
}

fn cardOpsFragment(app: App, p: *pg.Pool, res: *httpz.Response, id: i32, f: Filters, oq: []const u8, cursor: ?forms.OpCursor) !void {
    if (try Account.get_by_id(p, res.arena, id) == null) return render.flash(res, .not_found, "Account not found.");
    const c = try view.buildOps(p, res.arena, id, f.effective_day, oq, cursor);
    try render.send(app, res, "ops_fragment", false, .{
        .card = c,
        .tbody = cursor == null,
        .more = c.has_more,
        .none = c.no_ops,
    });
}

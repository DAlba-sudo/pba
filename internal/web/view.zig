//! Dashboard view models and their builders. Strings are preformatted so the
//! templates only print; every allocation goes to the request arena.
const std = @import("std");
const pg = @import("pg");
const types = @import("../types/root.zig");
const analysis = @import("../analysis/root.zig");
const time = @import("../time/root.zig");
const format = @import("format.zig");
const forms = @import("forms.zig");

const Account = types.Account;
const Operation = types.Operation;
const Filters = forms.Filters;

pub const ACCOUNT_PAGE = 10;
pub const OP_PAGE = 20;

pub const OpRow = struct {
    id: i32,
    title: []const u8,
    value: []const u8,
    cls: []const u8,
    date: []const u8,
    /// "None." when null/empty (with `comment_cls` "muted").
    comment: []const u8,
    comment_cls: []const u8,
    /// Drafts are listed (muted, marked) but left out of every total.
    draft: bool,
    /// `hx-vals` JSON of the toggle: the opposite state.
    toggle_vals: []const u8,
};

pub const CardView = struct {
    id: i32,
    name: []const u8 = "",
    balance: []const u8 = "",
    balance_cls: []const u8 = "",
    oq: []const u8 = "",
    ops: []const OpRow,
    has_more: bool,
    /// `<date>_<id>` of the last row; "" without more rows.
    next_cursor: []const u8,
    /// First page with no rows at all.
    no_ops: bool = false,
};

pub const AccountsPage = struct {
    cards: []const CardView,
    has_more: bool,
    /// Query string (filters + cursor) of the next page; "" without more cards.
    next_query: []const u8,
    /// Empty-state message; "" when `cards` is non-empty or for continuation pages.
    empty: []const u8,
};

pub const Total = struct { text: []const u8, cls: []const u8 };

pub const AccountOpt = struct { id: i32, name: []const u8, selected: bool };

pub const HeaderView = struct {
    account_label: []const u8,
    all_selected: bool,
    accounts: []const AccountOpt,
    /// Raw `date` filter ("" when unset) for the date input.
    date_value: []const u8,
    date_label: []const u8,
    q: []const u8,
};

pub const msg_no_db = "Database not connected.";

/// Header total = `/api/money/total?account_id&date` for the filters.
pub fn buildTotal(p: *pg.Pool, arena: std.mem.Allocator, f: Filters) !Total {
    const v = try analysis.Money.money(p, f.account, f.effective_date);
    return .{ .text = try format.money(arena, v, true), .cls = format.cls(v) };
}

/// Header without a database: no accounts, placeholder total.
pub fn offlineHeader(f: Filters) HeaderView {
    return .{
        .account_label = "All accounts",
        .all_selected = true,
        .accounts = &.{},
        .date_value = f.date orelse "",
        .date_label = f.effective_date,
        .q = f.q,
    };
}

pub const offline_total: Total = .{ .text = "n/a", .cls = "" };

/// Header menus; the account dropdown always lists every live account.
pub fn buildHeader(p: *pg.Pool, arena: std.mem.Allocator, f: Filters) !HeaderView {
    const all = try Account.search(p, arena, .{});
    const opts = try arena.alloc(AccountOpt, all.len);
    var h = offlineHeader(f);
    for (all, opts) |a, *o| {
        o.* = .{ .id = a.id, .name = a.name, .selected = f.account == a.id };
        if (o.selected) {
            h.account_label = a.name;
            h.all_selected = false;
        }
    }
    h.accounts = opts;
    return h;
}

/// One page of a card's operations up to the effective date, matching `oq`.
pub fn buildOps(p: *pg.Pool, arena: std.mem.Allocator, account_id: i32, effective_day: i32, oq: []const u8, cursor: ?forms.OpCursor) !CardView {
    const ops = try Operation.search(p, arena, .{
        .account_id = account_id,
        .date_max = effective_day,
        .text = oq,
        .cursor = if (cursor) |c| Operation.Cursor{ .date = c.date, .id = c.id } else null,
        .limit = OP_PAGE + 1,
    });
    const shown = ops[0..@min(ops.len, OP_PAGE)];
    const rows = try arena.alloc(OpRow, shown.len);
    for (shown, rows) |op, *r| {
        var buf: [10]u8 = undefined;
        const comment = op.comment orelse "";
        r.* = .{
            .id = op.id,
            .title = op.title,
            .value = try format.money(arena, op.value, false),
            .cls = format.cls(op.value),
            .date = try arena.dupe(u8, time.formatPgDate(op.date, &buf)),
            .comment = if (comment.len == 0) "None." else comment,
            .comment_cls = if (comment.len == 0) "muted" else "",
            .draft = op.draft,
            .toggle_vals = if (op.draft) "{\"draft\":\"false\"}" else "{\"draft\":\"true\"}",
        };
    }
    const has_more = ops.len > OP_PAGE;
    return .{
        .id = account_id,
        .oq = oq,
        .ops = rows,
        .has_more = has_more,
        .next_cursor = if (has_more) try forms.formatOpCursor(arena, .{
            .date = shown[shown.len - 1].date,
            .id = shown[shown.len - 1].id,
        }) else "",
        .no_ops = cursor == null and rows.len == 0,
    };
}

/// Full card: name, balance as of the effective date, first page of operations.
pub fn buildCard(p: *pg.Pool, arena: std.mem.Allocator, a: Account, f: Filters, oq: []const u8) !CardView {
    var c = try buildOps(p, arena, a.id, f.effective_day, oq, null);
    const balance = try analysis.Money.money(p, a.id, f.effective_date);
    c.name = a.name;
    c.balance = try format.money(arena, balance, true);
    c.balance_cls = format.cls(balance);
    return c;
}

/// Cards for the filters: the selected account only, else accounts matching `q`
/// after `after_id` (keyset), ACCOUNT_PAGE at a time.
pub fn buildAccountsPage(p: *pg.Pool, arena: std.mem.Allocator, f: Filters, after_id: ?i32) !AccountsPage {
    var accts: []const Account = &.{};
    if (f.account) |id| {
        // A single card never paginates; a continuation request gets nothing.
        if (after_id == null) {
            if (try Account.get_by_id(p, arena, id)) |a| {
                if (std.ascii.indexOfIgnoreCase(a.name, f.q) != null) accts = try arena.dupe(Account, &.{a});
            }
        }
    } else {
        accts = try Account.search(p, arena, .{ .name = f.q, .after_id = after_id, .limit = ACCOUNT_PAGE + 1 });
    }

    const has_more = accts.len > ACCOUNT_PAGE;
    const shown = accts[0..@min(accts.len, ACCOUNT_PAGE)];
    const cards = try arena.alloc(CardView, shown.len);
    for (shown, cards) |a, *c| c.* = try buildCard(p, arena, a, f, "");

    var next_query: []const u8 = "";
    if (has_more) {
        const fq = try f.toQuery(arena);
        next_query = try std.fmt.allocPrint(arena, "{s}{s}cursor={d}", .{
            fq, if (fq.len > 0) "&" else "", shown[shown.len - 1].id,
        });
    }
    const empty: []const u8 = if (cards.len > 0 or after_id != null)
        ""
    else if (f.account != null or f.q.len > 0) "No accounts match." else "No accounts.";
    return .{ .cards = cards, .has_more = has_more, .next_query = next_query, .empty = empty };
}

// This function returns the sum of money in some set of accounts,
// given a maximum date. Draft operations are excluded.
//
// Query Parameter Order:
//  - operation_sum:
//      - account_id
//      - date
pub fn money(p: *pg.Pool, account_id: ?i32, date: ?[]const u8) !f64 {
    const operation_sum =
        \\ SELECT COALESCE(SUM(value), 0) AS "Total" FROM operation WHERE (deleted_at IS NULL) AND NOT draft
        \\  AND account_id IN (SELECT id FROM account WHERE deleted_at IS NULL)
        \\  AND ($1 ::int IS NULL OR account_id = $1)
        \\  AND (($2 ::int IS NULL AND date <= (CURRENT_DATE - DATE '2000-01-01')) OR date <= $2);
    ;

    const account_initial_balance_sum =
        \\ SELECT COALESCE(SUM(initial_balance), 0) AS "Total" FROM account WHERE (deleted_at IS NULL)
        \\  AND ($1 ::int IS NULL OR id = $1);
    ;

    const pg_date: ?i32 = if (date) |d|
        try time.parseHtmlDateToPgDate(d)
    else
        null;

    var starting_money: f64 = 0.00;
    var operation_money: f64 = 0.00;

    var starting_money_row = try p.rowOpts(account_initial_balance_sum, .{account_id}, .{ .column_names = true });
    if (starting_money_row) |r| {
        defer starting_money_row.?.deinit() catch {};

        const total: f64 = r.get(f64, 0) catch |err| blk: {
            std.log.err("failed to deserialize total calculation from query (err: {s})", .{@errorName(err)});
            break :blk 0.0;
        };

        starting_money = total;
    }

    var operation_money_row = try p.rowOpts(operation_sum, .{ account_id, pg_date }, .{ .column_names = true });
    if (operation_money_row) |r| {
        defer operation_money_row.?.deinit() catch {};

        const total: f64 = r.get(f64, 0) catch |err| blk: {
            std.log.err("failed to deserialize total calculation from query (err: {s})", .{@errorName(err)});
            break :blk 0.0;
        };

        operation_money = total;
    }

    return starting_money + operation_money;
}

/// `balance` excludes drafts; `with_drafts` counts every live draft as final.
pub const SeriesPoint = struct { day: i32, balance: f64, with_drafts: f64 };

// Longest span `series` answers, in days.
pub const max_series_days: i32 = 3660;

// Daily running balance for every day in [from, to] (days since 2000-01-01).
// The first point already includes all earlier operations and the initial
// balances. Deleted operations are excluded; drafts count only in `with_drafts`.
pub fn series(p: *pg.Pool, arena: Allocator, account_id: ?i32, from: i32, to: i32) ![]SeriesPoint {
    if (to < from or to - from >= max_series_days) return error.InvalidRange;

    const query =
        \\ WITH ops AS (
        \\   SELECT date, value, draft FROM operation
        \\    WHERE deleted_at IS NULL AND date <= $3 ::int
        \\      AND account_id IN (SELECT id FROM account WHERE deleted_at IS NULL)
        \\      AND ($1 ::int IS NULL OR account_id = $1)
        \\ ), base AS (
        \\   SELECT (SELECT COALESCE(SUM(initial_balance), 0) FROM account
        \\            WHERE deleted_at IS NULL AND ($1 ::int IS NULL OR id = $1)) AS initial,
        \\          COALESCE(SUM(value) FILTER (WHERE NOT draft), 0) AS final,
        \\          COALESCE(SUM(value), 0) AS all_ops
        \\     FROM ops WHERE date < $2 ::int
        \\ ), per_day AS (
        \\   SELECT date, COALESCE(SUM(value) FILTER (WHERE NOT draft), 0) AS final, SUM(value) AS all_ops
        \\     FROM ops WHERE date >= $2 ::int
        \\    GROUP BY date
        \\ )
        \\ SELECT d.day ::int,
        \\        (base.initial + base.final + COALESCE(SUM(per_day.final) OVER w, 0)) ::float8,
        \\        (base.initial + base.all_ops + COALESCE(SUM(per_day.all_ops) OVER w, 0)) ::float8
        \\   FROM generate_series($2 ::int, $3 ::int) AS d(day)
        \\   CROSS JOIN base
        \\   LEFT JOIN per_day ON per_day.date = d.day
        \\ WINDOW w AS (ORDER BY d.day)
        \\  ORDER BY d.day;
    ;

    var rows = try p.query(query, .{ account_id, from, to });
    defer rows.deinit();

    var out: std.ArrayList(SeriesPoint) = .empty;
    while (try rows.next()) |row| {
        try out.append(arena, .{ .day = try row.get(i32, 0), .balance = try row.get(f64, 1), .with_drafts = try row.get(f64, 2) });
    }
    return out.items;
}

/// `balance[i]` is the non-draft balance on day `from + i`, as `SeriesPoint.balance`.
pub const AccountSeries = struct { id: i32, name: []const u8, balance: []f64 };
pub const Breakdown = struct { accounts: []AccountSeries, truncated: bool };

// Most accounts `seriesByAccount` returns; more would make an unreadable graph.
pub const max_breakdown_accounts: i32 = 12;

// Per-account split of `series(p, arena, null, from, to).balance` for the first
// `max_breakdown_accounts` live accounts by id. `truncated` is set when more
// live accounts exist; the accounts then no longer sum to the total.
pub fn seriesByAccount(p: *pg.Pool, arena: Allocator, from: i32, to: i32) !Breakdown {
    if (to < from or to - from >= max_series_days) return error.InvalidRange;

    const query =
        \\ WITH acc AS (
        \\   SELECT id, name, COALESCE(initial_balance, 0) AS initial FROM account
        \\    WHERE deleted_at IS NULL ORDER BY id LIMIT $3
        \\ ), ops AS (
        \\   SELECT account_id, date, value FROM operation
        \\    WHERE deleted_at IS NULL AND NOT draft AND date <= $2 ::int
        \\      AND account_id IN (SELECT id FROM acc)
        \\ ), base AS (
        \\   SELECT acc.id, acc.initial + COALESCE(SUM(ops.value), 0) AS start
        \\     FROM acc LEFT JOIN ops ON ops.account_id = acc.id AND ops.date < $1 ::int
        \\    GROUP BY acc.id, acc.initial
        \\ ), per_day AS (
        \\   SELECT account_id, date, SUM(value) AS v FROM ops
        \\    WHERE date >= $1 ::int GROUP BY account_id, date
        \\ )
        \\ SELECT acc.id, acc.name, d.day ::int,
        \\        (base.start + COALESCE(SUM(per_day.v) OVER w, 0)) ::float8,
        \\        (SELECT COUNT(*) FROM account WHERE deleted_at IS NULL) > $3 AS truncated
        \\   FROM acc
        \\   JOIN base ON base.id = acc.id
        \\   CROSS JOIN generate_series($1 ::int, $2 ::int) AS d(day)
        \\   LEFT JOIN per_day ON per_day.account_id = acc.id AND per_day.date = d.day
        \\ WINDOW w AS (PARTITION BY acc.id ORDER BY d.day)
        \\  ORDER BY acc.id, d.day;
    ;

    var rows = try p.query(query, .{ from, to, max_breakdown_accounts });
    defer rows.deinit();

    const days: usize = @intCast(to - from + 1);
    var out: std.ArrayList(AccountSeries) = .empty;
    var truncated = false;
    while (try rows.next()) |row| {
        const id = try row.get(i32, 0);
        if (out.items.len == 0 or out.items[out.items.len - 1].id != id) {
            // Row memory is reused by the next row, so the name is copied.
            const name = try arena.dupe(u8, try row.get([]const u8, 1));
            try out.append(arena, .{ .id = id, .name = name, .balance = try arena.alloc(f64, days) });
            truncated = try row.get(bool, 4);
        }
        const day = try row.get(i32, 2);
        out.items[out.items.len - 1].balance[@intCast(day - from)] = try row.get(f64, 3);
    }
    return .{ .accounts = out.items, .truncated = truncated };
}

// Imports
const pg = @import("pg");
const types = @import("../types/root.zig");
const std = @import("std");
const time = @import("../time/root.zig");
const Allocator = std.mem.Allocator;

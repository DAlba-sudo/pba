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

pub const SeriesPoint = struct { day: i32, balance: f64 };

// Longest span `series` answers, in days.
pub const max_series_days: i32 = 3660;

// Daily running balance for every day in [from, to] (days since 2000-01-01).
// The first point already includes all earlier operations and the initial
// balances. Draft and deleted operations are excluded.
pub fn series(p: *pg.Pool, arena: Allocator, account_id: ?i32, from: i32, to: i32) ![]SeriesPoint {
    if (to < from or to - from >= max_series_days) return error.InvalidRange;

    const query =
        \\ WITH base AS (
        \\   SELECT (SELECT COALESCE(SUM(initial_balance), 0) FROM account
        \\            WHERE deleted_at IS NULL AND ($1 ::int IS NULL OR id = $1))
        \\        + (SELECT COALESCE(SUM(value), 0) FROM operation
        \\            WHERE deleted_at IS NULL AND NOT draft AND date < $2 ::int
        \\              AND account_id IN (SELECT id FROM account WHERE deleted_at IS NULL)
        \\              AND ($1 ::int IS NULL OR account_id = $1)) AS amount
        \\ ), per_day AS (
        \\   SELECT date, SUM(value) AS amount FROM operation
        \\    WHERE deleted_at IS NULL AND NOT draft AND date >= $2 ::int AND date <= $3 ::int
        \\      AND account_id IN (SELECT id FROM account WHERE deleted_at IS NULL)
        \\      AND ($1 ::int IS NULL OR account_id = $1)
        \\    GROUP BY date
        \\ )
        \\ SELECT d.day ::int, ((SELECT amount FROM base) + COALESCE(SUM(per_day.amount) OVER (ORDER BY d.day), 0)) ::float8
        \\   FROM generate_series($2 ::int, $3 ::int) AS d(day)
        \\   LEFT JOIN per_day ON per_day.date = d.day
        \\  ORDER BY d.day;
    ;

    var rows = try p.query(query, .{ account_id, from, to });
    defer rows.deinit();

    var out: std.ArrayList(SeriesPoint) = .empty;
    while (try rows.next()) |row| {
        try out.append(arena, .{ .day = try row.get(i32, 0), .balance = try row.get(f64, 1) });
    }
    return out.items;
}

// Imports
const pg = @import("pg");
const types = @import("../types/root.zig");
const std = @import("std");
const time = @import("../time/root.zig");
const Allocator = std.mem.Allocator;

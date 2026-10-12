// This function returns the sum of money in some set of accounts,
// given a maximum date.
//
// Query Parameter Order:
//  - operation_sum:
//      - account_id
//      - date
pub fn money(p: *pg.Pool, account_id: ?i32, date: ?[]const u8) !f64 {
    const operation_sum =
        \\ SELECT COALESCE(SUM(value), 0) AS "Total" FROM operation WHERE (deleted_at IS NULL)
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

// Imports
const pg = @import("pg");
const types = @import("../types/root.zig");
const std = @import("std");
const time = @import("../time/root.zig");
const Allocator = std.mem.Allocator;

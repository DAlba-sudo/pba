// Given a date, an account, this function pulls the operations
// that have happened on the account and calculates the total money in that account
// on that hypothetical date.
pub fn total_money_as_of(p: *pg.Pool, a: Allocator, date: i64, account_id: i32) !f64 {
    const _account = try types.Account.get_by_id(p, a, account_id);
    if (_account) |account| {
        const operations = try types.Operation.get_by_account(p, a, account_id);
        defer a.free(operations);

        var sum = account.initial_balance.?;
        for (operations) |operation| {
            if (operation.date <= date) {
                sum += operation.value;
            }
        }

        return sum;
    }

    return error.NoAccountFound;
}

const types = @import("../types/root.zig");
const pg = @import("pg");
const std = @import("std");
const Allocator = std.mem.Allocator;

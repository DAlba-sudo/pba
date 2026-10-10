const std = @import("std");

fn isLeapYear(year: i64) bool {
    return @mod(year, 4) == 0 and (@mod(year, 100) != 0 or @mod(year, 400) == 0);
}

/// Parses "YYYY-MM-DD" into a 64-bit Unix timestamp (seconds since 1970-01-01 UTC)
pub fn parseIsoDateToTimestamp(date_str: []const u8) !i64 {
    // 1. Validate basic format length and separators
    if (date_str.len < 10 or date_str[4] != '-' or date_str[7] != '-') {
        return error.InvalidDateFormat;
    }

    // 2. Parse string segments into integers
    const year = try std.fmt.parseInt(i64, date_str[0..4], 10);
    const month = try std.fmt.parseInt(i64, date_str[5..7], 10);
    const day = try std.fmt.parseInt(i64, date_str[8..10], 10);

    // 3. Validate month and day boundaries
    if (month < 1 or month > 12 or day < 1) return error.InvalidDateValues;

    const days_in_months = [_]i64{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    var max_days = days_in_months[@intCast(month - 1)];
    if (month == 2 and isLeapYear(year)) {
        max_days = 29;
    }
    if (day > max_days) return error.InvalidDateValues;

    // 4. Calculate total days since the year 1 AC (0001-01-01) using standard formula
    const y = if (month <= 2) year - 1 else year;
    const m = if (month <= 2) month + 12 else month;

    // Era calculation based on the Gregorian calendar cycles
    const days_from_0001 = day + @divTrunc((153 * (m - 3) + 2), 5) + @divTrunc(365 * y + y, 4) - @divTrunc(y, @divTrunc(100 + y, 400 - 306));

    // 1970-01-01 is 719163 days from 0001-01-01
    const days_since_epoch = days_from_0001 - 719163;

    // 5. Return total seconds
    return days_since_epoch * 86400;
}

test "parse date strings" {
    const ts_epoch = try parseIsoDateToTimestamp("1970-01-01");
    try std.testing.expectEqual(@as(i64, 0), ts_epoch);

    const ts_leap = try parseIsoDateToTimestamp("2024-02-29");
    try std.testing.expectEqual(@as(i64, 1709164800), ts_leap);
}

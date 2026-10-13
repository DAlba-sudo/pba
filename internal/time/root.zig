const std = @import("std");

fn isLeapYear(year: i64) bool {
    return @mod(year, 4) == 0 and (@mod(year, 100) != 0 or @mod(year, 400) == 0);
}

/// Days between the Unix epoch (1970-01-01) and the PostgreSQL epoch (2000-01-01).
const pg_epoch_offset_days: i64 = 10957;

/// Parses an HTML `<input type="date">` value ("YYYY-MM-DD") into a PostgreSQL
/// DATE integer: the number of days since 2000-01-01 (negative before).
pub fn parseHtmlDateToPgDate(date_str: []const u8) !i32 {
    if (date_str.len != 10 or date_str[4] != '-' or date_str[7] != '-') {
        return error.InvalidDateFormat;
    }

    const year = try std.fmt.parseInt(i64, date_str[0..4], 10);
    const month = try std.fmt.parseInt(i64, date_str[5..7], 10);
    const day = try std.fmt.parseInt(i64, date_str[8..10], 10);

    if (month < 1 or month > 12 or day < 1 or day > daysInMonth(year, month)) return error.InvalidDateValues;
    return fromCivil(year, month, day);
}

/// Number of days in `month` (1-12) of `year`.
pub fn daysInMonth(year: i64, month: i64) i64 {
    const days_in_months = [_]i64{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    if (month == 2 and isLeapYear(year)) return 29;
    return days_in_months[@intCast(month - 1)];
}

/// A proleptic Gregorian calendar date.
pub const Civil = struct { year: i64, month: i64, day: i64 };

/// Valid calendar date to days since 2000-01-01 (Howard Hinnant's days_from_civil).
pub fn fromCivil(year: i64, month: i64, day: i64) i32 {
    // March-based years.
    const y = if (month <= 2) year - 1 else year;
    const era = @divFloor(y, 400);
    const yoe = y - era * 400;
    const mp = @mod(month + 9, 12);
    const doy = @divFloor(153 * mp + 2, 5) + day - 1;
    const doe = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy;
    const unix_days = era * 146097 + doe - 719468;
    return @intCast(unix_days - pg_epoch_offset_days);
}

/// Days since 2000-01-01 to a calendar date (Hinnant's civil_from_days).
pub fn toCivil(days: i32) Civil {
    const z: i64 = @as(i64, days) + pg_epoch_offset_days + 719468;
    const era = @divFloor(z, 146097);
    const doe = z - era * 146097;
    const yoe = @divFloor(doe - @divFloor(doe, 1460) + @divFloor(doe, 36524) - @divFloor(doe, 146096), 365);
    const doy = doe - (365 * yoe + @divFloor(yoe, 4) - @divFloor(yoe, 100));
    const mp = @divFloor(5 * doy + 2, 153);
    const d = doy - @divFloor(153 * mp + 2, 5) + 1;
    const m = if (mp < 10) mp + 3 else mp - 9;
    return .{ .year = yoe + era * 400 + @as(i64, if (m <= 2) 1 else 0), .month = m, .day = d };
}

/// Day of week of days since 2000-01-01: 0 = Monday ... 6 = Sunday.
pub fn weekday(days: i32) u3 {
    // 2000-01-01 was a Saturday.
    return @intCast(@mod(@as(i64, days) + 5, 7));
}

/// Formats days since 2000-01-01 as "YYYY-MM-DD". Valid for years 0000-9999.
pub fn formatPgDate(days: i32, buf: *[10]u8) []const u8 {
    const c = toCivil(days);
    return std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}-{d:0>2}", .{
        @as(u64, @intCast(c.year)), @as(u64, @intCast(c.month)), @as(u64, @intCast(c.day)),
    }) catch unreachable;
}

/// Today's date (UTC) as days since 2000-01-01.
pub fn todayPgDate(io: std.Io) i32 {
    const secs = std.Io.Clock.real.now(io).toSeconds();
    return @intCast(@divFloor(secs, 86400) - pg_epoch_offset_days);
}

pub const recurrence = @import("recurrence.zig");

test "html date to postgres date" {
    try std.testing.expectEqual(@as(i32, 0), try parseHtmlDateToPgDate("2000-01-01"));
    try std.testing.expectEqual(@as(i32, 1), try parseHtmlDateToPgDate("2000-01-02"));
    try std.testing.expectEqual(@as(i32, -1), try parseHtmlDateToPgDate("1999-12-31"));
    try std.testing.expectEqual(@as(i32, 59), try parseHtmlDateToPgDate("2000-02-29"));
    // SELECT DATE '2024-02-29' - DATE '2000-01-01'  => 8825
    try std.testing.expectEqual(@as(i32, 8825), try parseHtmlDateToPgDate("2024-02-29"));
    try std.testing.expectError(error.InvalidDateValues, parseHtmlDateToPgDate("2023-02-29"));
    try std.testing.expectError(error.InvalidDateFormat, parseHtmlDateToPgDate("2023/02/28"));
}

test "formatPgDate roundtrip" {
    var buf: [10]u8 = undefined;
    try std.testing.expectEqualStrings("2000-01-01", formatPgDate(0, &buf));
    try std.testing.expectEqualStrings("1999-12-31", formatPgDate(-1, &buf));
    try std.testing.expectEqualStrings("2024-02-29", formatPgDate(8825, &buf));
    var d: i32 = -36500;
    while (d < 80000) : (d += 1) {
        try std.testing.expectEqual(d, try parseHtmlDateToPgDate(formatPgDate(d, &buf)));
    }
}

test "weekday" {
    try std.testing.expectEqual(@as(u3, 5), weekday(0)); // 2000-01-01 Sat
    try std.testing.expectEqual(@as(u3, 0), weekday(try parseHtmlDateToPgDate("2026-10-12"))); // Mon
    try std.testing.expectEqual(@as(u3, 4), weekday(-1)); // 1999-12-31 Fri
}

test {
    _ = recurrence;
}

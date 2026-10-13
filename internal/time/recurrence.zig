//! Recurring operation dates (pure; no DB access). Shared by the API and the UI.
const std = @import("std");
const time = @import("root.zig");

/// Most occurrences a single recurring request may create.
pub const max_occurrences = 366;

/// Set of weekdays, bit 0 = Monday ... bit 6 = Sunday.
pub const Weekdays = struct {
    bits: u7 = 0,

    pub const names = [7][]const u8{ "mon", "tue", "wed", "thu", "fri", "sat", "sun" };

    /// From per-day flags (e.g. UI checkboxes), Monday first.
    pub fn fromFlags(flags: [7]bool) Weekdays {
        var w: Weekdays = .{};
        for (flags, 0..) |f, i| {
            if (f) w.bits |= @as(u7, 1) << @intCast(i);
        }
        return w;
    }

    /// Comma-separated `names` ("mon,thu"; blanks around items ignored).
    /// "" is the empty set; null if any item is unknown.
    pub fn parse(csv: []const u8) ?Weekdays {
        var w: Weekdays = .{};
        var it = std.mem.tokenizeScalar(u8, csv, ',');
        while (it.next()) |raw| {
            const name = std.mem.trim(u8, raw, " \t");
            if (name.len == 0) continue;
            for (names, 0..) |n, i| {
                if (std.ascii.eqlIgnoreCase(n, name)) {
                    w.bits |= @as(u7, 1) << @intCast(i);
                    break;
                }
            } else return null;
        }
        return w;
    }

    pub fn has(self: Weekdays, day: u3) bool {
        return self.bits & (@as(u7, 1) << day) != 0;
    }
};

pub const Rule = union(enum) {
    weekly: Weekdays,
    /// On the start's day of month, clamped to shorter months.
    monthly,
};

/// Days in [start, until] matching `rule`, ascending, written into `out`.
/// Empty when `until < start`; error.TooManyOccurrences past `max_occurrences`.
pub fn generate(start: i32, until: i32, rule: Rule, out: *[max_occurrences]i32) error{TooManyOccurrences}![]i32 {
    var n: usize = 0;
    switch (rule) {
        .weekly => |w| {
            if (w.bits == 0) return out[0..0];
            var d = start;
            while (d <= until) : (d += 1) {
                if (!w.has(time.weekday(d))) continue;
                if (n == max_occurrences) return error.TooManyOccurrences;
                out[n] = d;
                n += 1;
            }
        },
        .monthly => {
            const s = time.toCivil(start);
            var k: i64 = 0;
            while (true) : (k += 1) {
                const months = s.month - 1 + k;
                const y = s.year + @divFloor(months, 12);
                const m = @mod(months, 12) + 1;
                const d = time.fromCivil(y, m, @min(s.day, time.daysInMonth(y, m)));
                if (d > until) break;
                if (n == max_occurrences) return error.TooManyOccurrences;
                out[n] = d;
                n += 1;
            }
        },
    }
    return out[0..n];
}

/// Outcome of `validate`. `days` is meaningful only when `ok()`.
pub const Validated = struct {
    days: []const i32 = &.{},
    err_repeat: ?[]const u8 = null,
    err_until: ?[]const u8 = null,
    err_weekdays: ?[]const u8 = null,

    pub fn ok(self: Validated) bool {
        return self.err_repeat == null and self.err_until == null and self.err_weekdays == null;
    }

    pub const FieldError = struct { field: []const u8, msg: []const u8 };

    /// First error in field order (repeat, until, weekdays), for single-message APIs.
    pub fn firstError(self: Validated) ?FieldError {
        if (self.err_repeat) |m| return .{ .field = "repeat", .msg = m };
        if (self.err_until) |m| return .{ .field = "until", .msg = m };
        if (self.err_weekdays) |m| return .{ .field = "weekdays", .msg = m };
        return null;
    }
};

pub const msg_repeat = "Choose weekly or monthly.";
pub const msg_until = "Enter an end date as YYYY-MM-DD.";
pub const msg_until_before = "Must be on or after the date.";
pub const msg_weekdays = "Choose at least one weekday.";
pub const msg_none = "No dates match before the end date.";
pub const msg_too_many = std.fmt.comptimePrint("At most {d} occurrences.", .{max_occurrences});

/// Validates a series starting on `start`: `repeat` is "weekly" or "monthly",
/// `until` a required "YYYY-MM-DD" on or after `start`, and `weekdays`
/// non-empty when weekly (null = unparseable, see `Weekdays.parse`). On
/// success `days` (allocated in `allocator`) holds 1..max_occurrences dates.
pub fn validate(
    allocator: std.mem.Allocator,
    start: i32,
    repeat: []const u8,
    until: []const u8,
    weekdays: ?Weekdays,
) error{OutOfMemory}!Validated {
    var v: Validated = .{};
    var rule: Rule = .monthly;
    if (std.mem.eql(u8, repeat, "weekly")) {
        const w = weekdays orelse Weekdays{};
        if (w.bits == 0) v.err_weekdays = msg_weekdays;
        rule = .{ .weekly = w };
    } else if (!std.mem.eql(u8, repeat, "monthly")) {
        v.err_repeat = msg_repeat;
    }

    const end = parseDate(until);
    if (end == null) {
        v.err_until = msg_until;
    } else if (end.? < start) {
        v.err_until = msg_until_before;
    }
    if (!v.ok()) return v;

    var buf: [max_occurrences]i32 = undefined;
    const days = generate(start, end.?, rule, &buf) catch {
        v.err_until = msg_too_many;
        return v;
    };
    if (days.len == 0) {
        v.err_until = msg_none;
        return v;
    }
    v.days = try allocator.dupe(i32, days);
    return v;
}

/// Strict "YYYY-MM-DD" (digits only) to days since 2000-01-01.
fn parseDate(s: []const u8) ?i32 {
    if (s.len != 10) return null;
    for (s, 0..) |c, i| {
        if (i != 4 and i != 7 and !std.ascii.isDigit(c)) return null;
    }
    return time.parseHtmlDateToPgDate(s) catch null;
}

const testing = std.testing;

fn date(s: []const u8) i32 {
    return parseDate(s).?;
}

fn expectDays(expected: []const []const u8, start: []const u8, until: []const u8, rule: Rule) !void {
    var buf: [max_occurrences]i32 = undefined;
    const got = try generate(date(start), date(until), rule, &buf);
    try testing.expectEqual(expected.len, got.len);
    for (expected, got) |e, g| try testing.expectEqual(date(e), g);
}

test "monthly clamps short months" {
    // Non-leap and leap February; the original day returns afterwards.
    try expectDays(&.{ "2026-01-31", "2026-02-28", "2026-03-31", "2026-04-30", "2026-05-31" }, "2026-01-31", "2026-05-31", .monthly);
    try expectDays(&.{ "2024-01-30", "2024-02-29", "2024-03-30" }, "2024-01-30", "2024-03-30", .monthly);
    // Year rollover.
    try expectDays(&.{ "2026-12-31", "2027-01-31" }, "2026-12-31", "2027-02-27", .monthly);
}

test "until is a bound, not an occurrence" {
    try expectDays(&.{ "2026-01-15", "2026-02-15", "2026-03-15" }, "2026-01-15", "2026-04-10", .monthly);
    try expectDays(&.{ "2026-01-15", "2026-02-15" }, "2026-01-15", "2026-02-15", .monthly);
    const mon_thu = Weekdays.parse("mon,thu").?;
    // 2026-10-25 is a Sunday; 2026-10-22 a Thursday.
    try expectDays(&.{ "2026-10-12", "2026-10-15", "2026-10-19", "2026-10-22" }, "2026-10-12", "2026-10-25", .{ .weekly = mon_thu });
    try expectDays(&.{ "2026-10-12", "2026-10-15", "2026-10-19", "2026-10-22" }, "2026-10-12", "2026-10-22", .{ .weekly = mon_thu });
}

test "weekly selects weekdays only" {
    // 2026-10-13 is a Tuesday, so the start itself is skipped.
    try expectDays(&.{ "2026-10-18", "2026-10-25" }, "2026-10-13", "2026-10-31", .{ .weekly = Weekdays.fromFlags(.{ false, false, false, false, false, false, true }) });
}

test "start equals until, until before start" {
    try expectDays(&.{"2026-10-12"}, "2026-10-12", "2026-10-12", .monthly);
    try expectDays(&.{}, "2026-10-12", "2026-10-12", .{ .weekly = Weekdays.parse("tue").? });
    try expectDays(&.{}, "2026-10-12", "2026-10-11", .monthly);
}

test "366 cap" {
    var buf: [max_occurrences]i32 = undefined;
    const all = Weekdays.parse("mon,tue,wed,thu,fri,sat,sun").?;
    try testing.expectEqual(@as(usize, 366), (try generate(0, 365, .{ .weekly = all }, &buf)).len);
    try testing.expectError(error.TooManyOccurrences, generate(0, 366, .{ .weekly = all }, &buf));
    // 2000-01 .. 2030-06 is 366 months.
    try testing.expectEqual(@as(usize, 366), (try generate(0, date("2030-06-01"), .monthly, &buf)).len);
    try testing.expectError(error.TooManyOccurrences, generate(0, date("2030-07-01"), .monthly, &buf));
}

test "Weekdays.parse" {
    try testing.expectEqual(@as(u7, 0b1001001), Weekdays.parse(" Mon,thu ,sun,").?.bits);
    try testing.expectEqual(@as(u7, 0), Weekdays.parse("").?.bits);
    try testing.expectEqual(null, Weekdays.parse("mon,funday"));
}

test "validate" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const start = date("2026-10-12");

    const ok = try validate(a, start, "weekly", "2026-10-25", Weekdays.parse("mon,thu"));
    try testing.expect(ok.ok());
    try testing.expectEqual(@as(usize, 4), ok.days.len);

    const cases = [_]struct { repeat: []const u8, until: []const u8, wd: ?Weekdays, field: []const u8, msg: []const u8 }{
        .{ .repeat = "daily", .until = "2026-11-01", .wd = null, .field = "repeat", .msg = msg_repeat },
        .{ .repeat = "", .until = "2026-11-01", .wd = null, .field = "repeat", .msg = msg_repeat },
        .{ .repeat = "monthly", .until = "", .wd = null, .field = "until", .msg = msg_until },
        .{ .repeat = "monthly", .until = "2026-02-30", .wd = null, .field = "until", .msg = msg_until },
        .{ .repeat = "monthly", .until = "+026-11-01", .wd = null, .field = "until", .msg = msg_until },
        .{ .repeat = "monthly", .until = "2026-10-11", .wd = null, .field = "until", .msg = msg_until_before },
        .{ .repeat = "weekly", .until = "2026-11-01", .wd = null, .field = "weekdays", .msg = msg_weekdays },
        .{ .repeat = "weekly", .until = "2026-11-01", .wd = Weekdays{}, .field = "weekdays", .msg = msg_weekdays },
        .{ .repeat = "weekly", .until = "2026-10-12", .wd = Weekdays.parse("tue"), .field = "until", .msg = msg_none },
        .{ .repeat = "monthly", .until = "2057-10-12", .wd = null, .field = "until", .msg = msg_too_many },
    };
    for (cases) |c| {
        const v = try validate(a, start, c.repeat, c.until, c.wd);
        const e = v.firstError().?;
        try testing.expectEqualStrings(c.field, e.field);
        try testing.expectEqualStrings(c.msg, e.msg);
    }
}

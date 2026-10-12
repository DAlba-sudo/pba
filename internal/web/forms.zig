//! Query/form parsing and validation for the HTMX pages (pure; no DB access).
const std = @import("std");
const httpz = @import("httpz");
const time = @import("../time/root.zig");
const Operation = @import("../types/root.zig").Operation;
const recurrence = time.recurrence;

pub const StringKeyValue = httpz.key_value.StringKeyValue;

const max_amount = 1e12;
const max_name = 100;
const max_title = 200;
const max_comment = 500;
const space = " \t\r\n";

/// Parses a signed decimal amount ("-12.4", "5", "1e3") rounded to cents.
/// Rejects blank, non-numeric (incl. "nan"/"inf"/hex) and |x| > 1e12.
pub fn parseAmount(s: []const u8) !f64 {
    const t = std.mem.trim(u8, s, space);
    if (t.len == 0) return error.InvalidAmount;
    for (t) |c| {
        if (std.mem.indexOfScalar(u8, "0123456789+-.eE", c) == null) return error.InvalidAmount;
    }
    const v = std.fmt.parseFloat(f64, t) catch return error.InvalidAmount;
    if (!std.math.isFinite(v) or @abs(v) > max_amount) return error.InvalidAmount;
    return @round(v * 100) / 100;
}

/// Strict "-?[0-9]+" parse (std.fmt.parseInt also accepts '+' and '_').
fn parseInt32(s: []const u8) ?i32 {
    const digits = if (s.len > 0 and s[0] == '-') s[1..] else s;
    if (digits.len == 0 or digits.len > 10) return null;
    for (digits) |c| if (!std.ascii.isDigit(c)) return null;
    return std.fmt.parseInt(i32, s, 10) catch null;
}

/// Positive database id ("12"), else null.
pub fn parseId(s: []const u8) ?i32 {
    const v = parseInt32(s) orelse return null;
    return if (v > 0) v else null;
}

/// "YYYY-MM-DD" (years 0000-9999) to days since 2000-01-01, else null.
pub fn parseDate(s: []const u8) ?i32 {
    if (s.len != 10) return null;
    for (s, 0..) |c, i| {
        if (i != 4 and i != 7 and !std.ascii.isDigit(c)) return null;
    }
    return time.parseHtmlDateToPgDate(s) catch null;
}

fn formatDate(arena: std.mem.Allocator, day: i32) ![]const u8 {
    var buf: [10]u8 = undefined;
    return arena.dupe(u8, time.formatPgDate(day, &buf));
}

/// Global dashboard filters (`account`, `date`, `q`); invalid values are ignored.
pub const Filters = struct {
    /// Selected account id; null = all.
    account: ?i32 = null,
    /// Validated "YYYY-MM-DD" from the query; null when absent or invalid.
    date: ?[]const u8 = null,
    /// Account-name search, trimmed.
    q: []const u8 = "",
    /// `date` if set, else today ("YYYY-MM-DD").
    effective_date: []const u8,
    /// `effective_date` as days since 2000-01-01.
    effective_day: i32,

    pub fn fromRequest(req: *httpz.Request, today: i32) !Filters {
        return fromMap(req.arena, try req.query(), today);
    }

    /// Slices borrow from `map`; `effective_date` may be allocated in `arena`.
    pub fn fromMap(arena: std.mem.Allocator, map: *const StringKeyValue, today: i32) !Filters {
        var f: Filters = .{ .effective_date = "", .effective_day = today };
        if (map.get("account")) |a| f.account = parseId(a);
        if (map.get("date")) |d| {
            if (parseDate(d)) |day| {
                f.date = d;
                f.effective_day = day;
            }
        }
        if (map.get("q")) |q| f.q = std.mem.trim(u8, q, space);
        f.effective_date = f.date orelse try formatDate(arena, today);
        return f;
    }

    /// Percent-encoded "account=..&date=..&q=.." with unset fields omitted (may be "").
    pub fn toQuery(self: Filters, arena: std.mem.Allocator) ![]const u8 {
        var aw: std.Io.Writer.Allocating = .init(arena);
        const w = &aw.writer;
        var first = true;
        if (self.account) |a| {
            var buf: [11]u8 = undefined;
            try writeParam(w, &first, "account", std.fmt.bufPrint(&buf, "{d}", .{a}) catch unreachable);
        }
        if (self.date) |d| try writeParam(w, &first, "date", d);
        if (self.q.len > 0) try writeParam(w, &first, "q", self.q);
        return aw.written();
    }
};

fn writeParam(w: *std.Io.Writer, first: *bool, name: []const u8, value: []const u8) !void {
    if (!first.*) try w.writeByte('&');
    first.* = false;
    try w.print("{s}=", .{name});
    for (value) |c| {
        if (std.ascii.isAlphanumeric(c) or std.mem.indexOfScalar(u8, "-._~", c) != null) {
            try w.writeByte(c);
        } else {
            try w.print("%{X:0>2}", .{c});
        }
    }
}

/// Keyset cursor of the last shown operation row, serialized as "<date>_<id>".
pub const OpCursor = struct { date: i32, id: i32 };

pub fn parseOpCursor(s: []const u8) !OpCursor {
    const sep = std.mem.indexOfScalar(u8, s, '_') orelse return error.InvalidCursor;
    return .{
        .date = parseInt32(s[0..sep]) orelse return error.InvalidCursor,
        .id = parseId(s[sep + 1 ..]) orelse return error.InvalidCursor,
    };
}

pub fn formatOpCursor(arena: std.mem.Allocator, c: OpCursor) ![]const u8 {
    return std.fmt.allocPrint(arena, "{d}_{d}", .{ c.date, c.id });
}

/// Trimmed raw form inputs, echoed into a re-rendered form.
pub const Input = struct {
    name: []const u8 = "",
    initial_balance: []const u8 = "",
    account_id: []const u8 = "",
    title: []const u8 = "",
    amount: []const u8 = "",
    date: []const u8 = "",
    comment: []const u8 = "",
    draft: []const u8 = "",
    repeat: []const u8 = "",
    until: []const u8 = "",
};

/// Validation outcome. Parsed values are meaningful only when `ok()`;
/// validated `name`/`title` are `input.name`/`input.title`.
pub const Result = struct {
    input: Input = .{},
    initial_balance: f64 = 0,
    account_id: i32 = 0,
    amount: f64 = 0,
    date: i32 = 0,
    /// null when blank.
    comment: ?[]const u8 = null,
    draft: bool = false,
    /// Checked weekday boxes (`weekday_mon`..`weekday_sun`), Monday first.
    weekdays: [7]bool = @splat(false),
    /// Series dates when `repeat` is weekly or monthly; empty for a single operation.
    days: []const i32 = &.{},

    err_name: ?[]const u8 = null,
    err_initial_balance: ?[]const u8 = null,
    err_account_id: ?[]const u8 = null,
    err_title: ?[]const u8 = null,
    err_amount: ?[]const u8 = null,
    err_date: ?[]const u8 = null,
    err_comment: ?[]const u8 = null,
    err_draft: ?[]const u8 = null,
    err_repeat: ?[]const u8 = null,
    err_until: ?[]const u8 = null,
    err_weekdays: ?[]const u8 = null,
    /// Not set by validation; for handler-level errors shown on the form.
    err_general: ?[]const u8 = null,

    pub fn ok(self: Result) bool {
        inline for (std.meta.fields(Result)) |f| {
            if (comptime std.mem.startsWith(u8, f.name, "err_")) {
                if (@field(self, f.name) != null) return false;
            }
        }
        return true;
    }
};

const msg_required = "Required.";
const msg_amount = "Enter an amount like -12.34.";

fn field(map: *const StringKeyValue, name: []const u8) []const u8 {
    return std.mem.trim(u8, map.get(name) orelse "", space);
}

/// Error for text that is not valid UTF-8 or longer than `max` code points.
fn textError(s: []const u8, comptime max: usize) ?[]const u8 {
    const n = std.unicode.utf8CountCodepoints(s) catch return "Invalid text.";
    return if (n > max) std.fmt.comptimePrint("At most {d} characters.", .{max}) else null;
}

/// Account form: `name` required (<= 100), `initial_balance` blank -> 0.
pub fn validateAccount(map: *const StringKeyValue) Result {
    var r: Result = .{ .input = .{
        .name = field(map, "name"),
        .initial_balance = field(map, "initial_balance"),
    } };
    r.err_name = if (r.input.name.len == 0) msg_required else textError(r.input.name, max_name);
    if (r.input.initial_balance.len > 0) {
        r.initial_balance = parseAmount(r.input.initial_balance) catch blk: {
            r.err_initial_balance = msg_amount;
            break :blk 0;
        };
    }
    return r;
}

/// Weekday checkbox names, Monday first.
pub const weekday_keys = blk: {
    var keys: [7][]const u8 = undefined;
    for (recurrence.Weekdays.names, &keys) |n, *k| k.* = "weekday_" ++ n;
    break :blk keys;
};

/// Operation form. `account_id` is only parsed; its existence is checked by the handler.
/// Blank `date` -> `today`; blank `comment` -> null; `draft` is "true" or absent.
/// `repeat` blank or "none" is a single operation; otherwise the series is
/// validated by `time.recurrence.validate` and its dates (in `arena`) land in `days`.
pub fn validateOperation(arena: std.mem.Allocator, map: *const StringKeyValue, today: i32) !Result {
    var r: Result = .{ .input = .{
        .account_id = field(map, "account_id"),
        .title = field(map, "title"),
        .amount = field(map, "amount"),
        .date = field(map, "date"),
        .comment = field(map, "comment"),
        .draft = field(map, "draft"),
        .repeat = field(map, "repeat"),
        .until = field(map, "until"),
    } };
    if (parseId(r.input.account_id)) |id| r.account_id = id else r.err_account_id = "Invalid account.";
    r.err_title = if (r.input.title.len == 0) msg_required else textError(r.input.title, max_title);
    if (r.input.amount.len == 0) {
        r.err_amount = msg_required;
    } else {
        r.amount = parseAmount(r.input.amount) catch blk: {
            r.err_amount = msg_amount;
            break :blk 0;
        };
    }
    if (r.input.date.len == 0) {
        r.date = today;
    } else if (parseDate(r.input.date)) |d| {
        r.date = d;
    } else {
        r.err_date = "Enter a date as YYYY-MM-DD.";
    }
    if (r.input.comment.len > 0) {
        r.err_comment = textError(r.input.comment, max_comment);
        r.comment = r.input.comment;
    }
    if (r.input.draft.len > 0) {
        r.draft = Operation.parseDraft(r.input.draft) orelse blk: {
            r.err_draft = "Invalid draft flag.";
            break :blk false;
        };
    }
    for (weekday_keys, &r.weekdays) |k, *w| w.* = field(map, k).len > 0;

    const repeat = r.input.repeat;
    // The series needs a valid start date; a bad `date` is already reported.
    if (repeat.len > 0 and !std.mem.eql(u8, repeat, "none") and r.err_date == null) {
        const v = try recurrence.validate(arena, r.date, repeat, r.input.until, recurrence.Weekdays.fromFlags(r.weekdays));
        r.err_repeat = v.err_repeat;
        r.err_until = v.err_until;
        r.err_weekdays = v.err_weekdays;
        r.days = v.days;
    }
    return r;
}

const testing = std.testing;

fn testMap(pairs: []const [2][]const u8) !StringKeyValue {
    var kv = try StringKeyValue.init(testing.allocator, 16);
    for (pairs) |p| kv.add(p[0], p[1]);
    return kv;
}

test "parseAmount" {
    try testing.expectEqual(@as(f64, -12.4), try parseAmount(" -12.4 "));
    try testing.expectEqual(@as(f64, 12.35), try parseAmount("12.346"));
    for ([_][]const u8{ "abc", "nan", "inf", "", "1e13", "0x10", "1_0" }) |s| {
        try testing.expectError(error.InvalidAmount, parseAmount(s));
    }
}

test "Filters" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var bad = try testMap(&.{ .{ "account", "zz" }, .{ "date", "garbage" }, .{ "q", "  " } });
    defer bad.deinit(testing.allocator);
    const f0 = try Filters.fromMap(a, &bad, 8825);
    try testing.expectEqual(null, f0.account);
    try testing.expectEqual(null, f0.date);
    try testing.expectEqualStrings("2024-02-29", f0.effective_date);
    try testing.expectEqualStrings("", try f0.toQuery(a));

    var good = try testMap(&.{ .{ "account", "2" }, .{ "date", "2026-10-02" }, .{ "q", " a b&c " } });
    defer good.deinit(testing.allocator);
    const f1 = try Filters.fromMap(a, &good, 0);
    try testing.expectEqual(@as(?i32, 2), f1.account);
    try testing.expectEqual(parseDate("2026-10-02").?, f1.effective_day);
    try testing.expectEqualStrings("2026-10-02", f1.effective_date);
    try testing.expectEqualStrings("account=2&date=2026-10-02&q=a%20b%26c", try f1.toQuery(a));
}

test "OpCursor" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const c: OpCursor = .{ .date = -3, .id = 42 };
    try testing.expectEqual(c, try parseOpCursor(try formatOpCursor(arena.allocator(), c)));
    for ([_][]const u8{ "", "1", "_1", "1_", "1_0", "1_2_3", "+1_2", "a_1" }) |s| {
        try testing.expectError(error.InvalidCursor, parseOpCursor(s));
    }
}

test "validate forms" {
    var acc = try testMap(&.{ .{ "name", " " }, .{ "initial_balance", "x" } });
    defer acc.deinit(testing.allocator);
    const ra = validateAccount(&acc);
    try testing.expect(!ra.ok());
    try testing.expectEqualStrings(msg_required, ra.err_name.?);
    try testing.expectEqualStrings(msg_amount, ra.err_initial_balance.?);

    var op = try testMap(&.{
        .{ "account_id", "1" }, .{ "title", " Coffee " }, .{ "amount", "-12.43" },
        .{ "date", "" },        .{ "comment", " " },
    });
    defer op.deinit(testing.allocator);
    const ro = try validateOperation(testing.allocator, &op, 7);
    try testing.expect(ro.ok());
    try testing.expectEqualStrings("Coffee", ro.input.title);
    try testing.expectEqual(@as(f64, -12.43), ro.amount);
    try testing.expectEqual(@as(i32, 7), ro.date);
    try testing.expectEqual(null, ro.comment);
    try testing.expect(!ro.draft);
    try testing.expectEqual(0, ro.days.len);

    var bad = try testMap(&.{ .{ "account_id", "x" }, .{ "date", "2023-02-29" } });
    defer bad.deinit(testing.allocator);
    const rb = try validateOperation(testing.allocator, &bad, 0);
    try testing.expect(rb.err_account_id != null and rb.err_title != null and rb.err_amount != null and rb.err_date != null);
}

test "validate operation draft and recurrence" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const base = [_][2][]const u8{ .{ "account_id", "1" }, .{ "title", "Rent" }, .{ "amount", "-5" }, .{ "date", "2026-10-12" } };

    // Weekly mon,thu with draft: 10-12, 10-15, 10-19, 10-22.
    var wk = try testMap(&(base ++ .{
        .{ "draft", "true" },     .{ "repeat", "weekly" },  .{ "until", "2026-10-25" },
        .{ "weekday_mon", "on" }, .{ "weekday_thu", "on" },
    }));
    defer wk.deinit(testing.allocator);
    const rw = try validateOperation(a, &wk, 0);
    try testing.expect(rw.ok() and rw.draft);
    try testing.expectEqualSlices(i32, &.{ parseDate("2026-10-12").?, parseDate("2026-10-15").?, parseDate("2026-10-19").?, parseDate("2026-10-22").? }, rw.days);

    // "none" ignores the series fields.
    var none = try testMap(&(base ++ .{ .{ "repeat", "none" }, .{ "until", "junk" } }));
    defer none.deinit(testing.allocator);
    const rn = try validateOperation(a, &none, 0);
    try testing.expect(rn.ok() and rn.days.len == 0);

    // Field errors: bad draft, unknown repeat, missing until.
    var bad = try testMap(&(base ++ .{ .{ "draft", "on" }, .{ "repeat", "daily" } }));
    defer bad.deinit(testing.allocator);
    const rb = try validateOperation(a, &bad, 0);
    try testing.expect(rb.err_draft != null);
    try testing.expectEqualStrings(recurrence.msg_repeat, rb.err_repeat.?);
    try testing.expectEqualStrings(recurrence.msg_until, rb.err_until.?);

    // Weekly without boxes; until before date.
    var wk0 = try testMap(&(base ++ .{ .{ "repeat", "weekly" }, .{ "until", "2026-10-01" } }));
    defer wk0.deinit(testing.allocator);
    const r0 = try validateOperation(a, &wk0, 0);
    try testing.expectEqualStrings(recurrence.msg_weekdays, r0.err_weekdays.?);
    try testing.expectEqualStrings(recurrence.msg_until_before, r0.err_until.?);
}

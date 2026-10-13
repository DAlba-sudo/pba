//! GET /export/operations.csv : every live account and its live operations
//! (drafts included) as one RFC 4180 CSV, ignoring the dashboard filters.
const std = @import("std");
const httpz = @import("httpz");
const pg = @import("pg");
const App = @import("../routes/root.zig").App;
const time = @import("../time/root.zig");

pub const Errors = error{OperationExportFailure};

/// One account joined with one of its operations. The operation fields are
/// null for an account without live operations.
pub const Row = struct {
    account_id: i32,
    account_name: []const u8,
    account_initial_balance: ?f64,
    operation_id: ?i32,
    date: ?i32,
    title: ?[]const u8,
    amount: ?f64,
    draft: ?bool,
    comment: ?[]const u8,
};

pub const header = "account_id,account_name,account_initial_balance,operation_id,date,title,amount,draft,comment\r\n";

/// All live accounts with their live operations, grouped by account then by
/// date. Rows are copied into `allocator`.
pub fn fetchRows(p: *pg.Pool, allocator: std.mem.Allocator) Errors![]Row {
    // The operation filter sits in the ON clause so empty accounts keep their row.
    const query =
        \\ SELECT a.id AS account_id, a.name AS account_name, a.initial_balance AS account_initial_balance,
        \\  o.id AS operation_id, o.date, o.title, o.value AS amount, o.draft, o.comment
        \\ FROM account a LEFT JOIN operation o ON o.account_id = a.id AND o.deleted_at IS NULL
        \\ WHERE a.deleted_at IS NULL
        \\ ORDER BY a.name, a.id, o.date, o.id
    ;

    const rows = p.queryOpts(query, .{}, .{ .column_names = true }) catch |err| {
        std.log.err("failed to export the operations (err: {s})", .{@errorName(err)});
        return Errors.OperationExportFailure;
    };
    defer rows.deinit();

    var list: std.ArrayList(Row) = .empty;
    var mapper = rows.mapper(Row, .{ .dupe = true, .allocator = allocator });
    while (mapper.next() catch |err| {
        std.log.err("failed to map the row result to an export row (err: {s})", .{@errorName(err)});
        return Errors.OperationExportFailure;
    }) |r| {
        list.append(allocator, r) catch return Errors.OperationExportFailure;
    }
    return list.toOwnedSlice(allocator) catch Errors.OperationExportFailure;
}

/// Writes one field. Text fields (`harden`) that a spreadsheet would read as a
/// formula get a leading `'`. The field is quoted iff it contains `,` `"` CR
/// or LF, or has leading or trailing whitespace; inner quotes are doubled.
pub fn writeField(w: *std.Io.Writer, s: []const u8, harden: bool) std.Io.Writer.Error!void {
    const prefix = harden and s.len > 0 and std.mem.indexOfScalar(u8, "=+-@\t\r", s[0]) != null;
    const quote = std.mem.indexOfAny(u8, s, ",\"\r\n") != null or
        (s.len > 0 and (std.ascii.isWhitespace(s[s.len - 1]) or (!prefix and std.ascii.isWhitespace(s[0]))));
    if (quote) try w.writeByte('"');
    if (prefix) try w.writeByte('\'');
    for (s) |c| {
        if (c == '"') try w.writeByte('"');
        try w.writeByte(c);
    }
    if (quote) try w.writeByte('"');
}

/// Writes `r` as one CSV record, `\r\n` terminated, in `header` column order.
pub fn writeRow(w: *std.Io.Writer, r: Row) std.Io.Writer.Error!void {
    try w.print("{d},", .{r.account_id});
    try writeField(w, r.account_name, true);
    try w.writeByte(',');
    if (r.account_initial_balance) |b| try w.print("{d}", .{b});
    try w.writeByte(',');
    if (r.operation_id) |id| try w.print("{d}", .{id});
    try w.writeByte(',');
    if (r.date) |d| {
        var buf: [10]u8 = undefined;
        try w.writeAll(time.formatPgDate(d, &buf));
    }
    try w.writeByte(',');
    if (r.title) |t| try writeField(w, t, true);
    try w.writeByte(',');
    if (r.amount) |v| try w.print("{d}", .{v});
    try w.writeByte(',');
    if (r.draft) |d| try w.writeAll(if (d) "true" else "false");
    try w.writeByte(',');
    if (r.comment) |c| try writeField(w, c, true);
    try w.writeAll("\r\n");
}

pub fn operationsCsv(app: App, _: *httpz.Request, res: *httpz.Response) !void {
    const p = app.p orelse {
        res.setStatus(.service_unavailable);
        res.body = "Database unavailable.\n";
        return;
    };
    // Build the whole body first so a failure never yields a partial file.
    const body = buildCsv(p, res.arena) catch |err| {
        std.log.err("failed to build the operations export (err: {s})", .{@errorName(err)});
        res.setStatus(.internal_server_error);
        res.body = "Export failed, please try again.\n";
        return;
    };

    var date_buf: [10]u8 = undefined;
    const today = time.formatPgDate(time.todayPgDate(app.io), &date_buf);
    res.content_type = .CSV;
    res.header("Content-Disposition", try std.fmt.allocPrint(res.arena, "attachment; filename=\"pba-operations-{s}.csv\"", .{today}));
    res.header("Cache-Control", "no-store");
    res.body = body;
}

fn buildCsv(p: *pg.Pool, arena: std.mem.Allocator) ![]const u8 {
    const rows = try fetchRows(p, arena);
    var aw: std.Io.Writer.Allocating = .init(arena);
    try aw.writer.writeAll(header);
    for (rows) |r| try writeRow(&aw.writer, r);
    return aw.written();
}

fn expectField(expected: []const u8, s: []const u8, harden: bool) !void {
    var buf: [64]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try writeField(&w, s, harden);
    try std.testing.expectEqualStrings(expected, w.buffered());
}

test "writeField quoting" {
    try expectField("plain text", "plain text", true);
    try expectField("\"a,b \"\"c\"\"\nd\"", "a,b \"c\"\nd", true);
    try expectField("\" lead\"", " lead", true);
    try expectField("\"trail \"", "trail ", true);
    try expectField("", "", true);
}

test "writeField formula hardening on text only" {
    try expectField("'=SUM(A1)", "=SUM(A1)", true);
    try expectField("'@x", "@x", true);
    try expectField("'-x", "-x", true);
    try expectField("'+x", "+x", true);
    try expectField("\"'\rx\"", "\rx", true);
    try expectField("-x", "-x", false);
}

test "writeRow" {
    var buf: [256]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try writeRow(&w, .{
        .account_id = 1,
        .account_name = "Main",
        .account_initial_balance = null,
        .operation_id = 7,
        .date = 8825,
        .title = "Rent",
        .amount = -12.5,
        .draft = true,
        .comment = null,
    });
    try writeRow(&w, .{
        .account_id = 2,
        .account_name = "Empty",
        .account_initial_balance = 100,
        .operation_id = null,
        .date = null,
        .title = null,
        .amount = null,
        .draft = null,
        .comment = null,
    });
    try std.testing.expectEqualStrings(
        "1,Main,,7,2024-02-29,Rent,-12.5,true,\r\n" ++
            "2,Empty,100,,,,,,\r\n",
        w.buffered(),
    );
}

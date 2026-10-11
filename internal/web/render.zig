//! Template rendering and error-flash responses for the HTMX pages.
const std = @import("std");
const httpz = @import("httpz");
const zmpl = @import("zmpl");
const App = @import("../routes/root.zig").App;

/// True for htmx requests that want a fragment; history restores get the full page.
pub fn isFragment(req: *const httpz.Request) bool {
    const hx = req.header("hx-request") orelse return false;
    const restore = req.header("hx-history-restore-request") orelse "";
    return std.mem.eql(u8, hx, "true") and !std.mem.eql(u8, restore, "true");
}

/// Renders template `name` (path under html/ without extension), binding every field
/// of struct `ctx` to `$.<field>`. `layout` wraps the output in html/layout.zmpl.
/// The result is allocated in `arena`.
pub fn renderAlloc(io: std.Io, arena: std.mem.Allocator, name: []const u8, layout: bool, ctx: anytype) ![]const u8 {
    const tmpl = zmpl.find(name) orelse return error.TemplateNotFound;
    var data = zmpl.Data.init(io, arena);
    defer data.deinit();
    var root = try data.root(.object);
    inline for (std.meta.fields(@TypeOf(ctx))) |f| {
        try root.put(f.name, @field(ctx, f.name));
    }
    const out = try tmpl.render(io, &data, null, null, &.{}, .{
        .layout = if (layout) zmpl.find("layout") else null,
    });
    return arena.dupe(u8, out); // `out` is freed with `data`
}

/// Renders into `res` as text/html. Status is left to the caller (default 200).
/// On error nothing is written, so the caller can still answer with `flash`.
pub fn send(app: App, res: *httpz.Response, name: []const u8, layout: bool, ctx: anytype) !void {
    const out = try renderAlloc(app.io, res.arena, name, layout, ctx);
    res.content_type = .HTML;
    res.body = out;
}

/// Error fragment retargeted into `#flash` (htmx swaps it per the layout's responseHandling).
pub fn flash(res: *httpz.Response, status: std.http.Status, msg: []const u8) void {
    res.setStatus(status);
    res.content_type = .HTML;
    res.header("HX-Retarget", "#flash");
    res.header("HX-Reswap", "innerHTML");
    res.body = flashBody(res.arena, msg) catch "<div class=\"flash error\">Error.</div>";
}

fn flashBody(arena: std.mem.Allocator, msg: []const u8) ![]const u8 {
    var aw: std.Io.Writer.Allocating = .init(arena);
    const w = &aw.writer;
    try w.writeAll("<div class=\"flash error\">");
    for (msg) |c| switch (c) {
        '&' => try w.writeAll("&amp;"),
        '<' => try w.writeAll("&lt;"),
        '>' => try w.writeAll("&gt;"),
        '"' => try w.writeAll("&quot;"),
        '\'' => try w.writeAll("&#39;"),
        else => try w.writeByte(c),
    };
    try w.writeAll("</div>");
    return aw.written();
}

const testing = std.testing;

test "renderAlloc binds ctx fields, escapes, wraps layout" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const Row = struct { title: []const u8, n: i32 };
    const rows = [_]Row{ .{ .title = "a", .n = 1 }, .{ .title = "<b>", .n = -2 } };
    const ctx = .{ .name = "x&y", .count = @as(i32, 3), .flag = true, .rows = @as([]const Row, &rows) };

    const frag = try renderAlloc(testing.io, arena.allocator(), "test_render", false, ctx);
    try testing.expectEqualStrings("<p>x&amp;y 3</p>\n<b>on</b>\n<i>a=1</i>\n<i>&lt;b&gt;=-2</i>\n", frag);

    const page = try renderAlloc(testing.io, arena.allocator(), "test_render", true, ctx);
    try testing.expect(std.mem.startsWith(u8, page, "<!doctype html>"));
    try testing.expect(std.mem.indexOf(u8, page, "<p>x&amp;y 3</p>") != null);
    try testing.expect(std.mem.indexOf(u8, page, "<div id=\"drawer-body\"></div>") != null);
    try testing.expect(std.mem.indexOf(u8, page, "\"historyCacheSize\":0") != null);
}

test "isFragment and flash" {
    var ht = httpz.testing.init(.{});
    defer ht.deinit();
    try testing.expect(!isFragment(ht.req));
    ht.header("HX-Request", "true");
    try testing.expect(isFragment(ht.req));
    ht.header("HX-History-Restore-Request", "true");
    try testing.expect(!isFragment(ht.req));

    flash(ht.res, .service_unavailable, "db <down>");
    try ht.expectStatus(503);
    try ht.expectHeader("HX-Retarget", "#flash");
    try ht.expectHeader("HX-Reswap", "innerHTML");
    try ht.expectBody("<div class=\"flash error\">db &lt;down&gt;</div>");
}

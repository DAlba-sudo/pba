//! Template rendering helpers (WP3 replaces this WP0 smoke test).
const std = @import("std");
const zmpl = @import("zmpl");

test "render hello template" {
    var data = zmpl.Data.init(std.testing.io, std.testing.allocator);
    defer data.deinit();
    var root = try data.root(.object);
    try root.put("name", "<b>");
    const out = try zmpl.find("hello").?.render(std.testing.io, &data, null, null, &.{}, .{});
    try std.testing.expectEqualStrings("<p>hello &lt;b&gt;</p>\n", out);
}

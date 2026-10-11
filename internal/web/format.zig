//! Display formatting for money values.
const std = @import("std");

/// Values outside this range (or non-finite) display as zero.
const max_display = 1e12;

/// Rounds to whole cents, half away from zero.
fn cents(v: f64) i64 {
    if (!std.math.isFinite(v) or @abs(v) > max_display) return 0;
    return @intFromFloat(@round(v * 100));
}

/// Formats `v` as "-$12.33" (dollar) or "-12.33"; never "-0.00".
pub fn money(arena: std.mem.Allocator, v: f64, dollar: bool) ![]const u8 {
    const c = cents(v);
    const abs = @abs(c);
    return std.fmt.allocPrint(arena, "{s}{s}{d}.{d:0>2}", .{
        if (c < 0) "-" else "",
        if (dollar) "$" else "",
        abs / 100,
        abs % 100,
    });
}

/// CSS class for a money value: "neg" when it displays negative, else "pos".
pub fn cls(v: f64) []const u8 {
    return if (cents(v) < 0) "neg" else "pos";
}

test "money" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const cases = [_]struct { v: f64, dollar: bool, want: []const u8 }{
        .{ .v = 0, .dollar = true, .want = "$0.00" },
        .{ .v = -0.004, .dollar = false, .want = "0.00" },
        .{ .v = 12.335, .dollar = false, .want = "12.34" },
        .{ .v = -12.33, .dollar = true, .want = "-$12.33" },
        .{ .v = 1e13, .dollar = false, .want = "0.00" },
        .{ .v = std.math.nan(f64), .dollar = false, .want = "0.00" },
    };
    for (cases) |c| try std.testing.expectEqualStrings(c.want, try money(a, c.v, c.dollar));
    try std.testing.expectEqualStrings("neg", cls(-0.01));
    try std.testing.expectEqualStrings("pos", cls(-0.004));
}

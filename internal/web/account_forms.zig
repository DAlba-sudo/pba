//! Stub (owner: WP6): handlers answer 501 until implemented.
const httpz = @import("httpz");
const App = @import("../routes/root.zig").App;

pub fn accountNew(_: App, _: *httpz.Request, res: *httpz.Response) !void {
    res.setStatus(.not_implemented);
}

pub fn accountCreate(_: App, _: *httpz.Request, res: *httpz.Response) !void {
    res.setStatus(.not_implemented);
}

pub fn modalClose(_: App, _: *httpz.Request, res: *httpz.Response) !void {
    res.setStatus(.not_implemented);
}

//! Stub (owner: WP4/WP5): handlers answer 501 until implemented.
const httpz = @import("httpz");
const App = @import("../routes/root.zig").App;

pub fn index(_: App, _: *httpz.Request, res: *httpz.Response) !void {
    res.setStatus(.not_implemented);
}

pub fn accountsPage(_: App, _: *httpz.Request, res: *httpz.Response) !void {
    res.setStatus(.not_implemented);
}

pub fn card(_: App, _: *httpz.Request, res: *httpz.Response) !void {
    res.setStatus(.not_implemented);
}

pub fn cardOps(_: App, _: *httpz.Request, res: *httpz.Response) !void {
    res.setStatus(.not_implemented);
}

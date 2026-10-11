//! Stub (owner: WP3): handlers answer 501 until implemented.
const httpz = @import("httpz");
const App = @import("../routes/root.zig").App;

pub fn htmxJs(_: App, _: *httpz.Request, res: *httpz.Response) !void {
    res.setStatus(.not_implemented);
}

pub fn appCss(_: App, _: *httpz.Request, res: *httpz.Response) !void {
    res.setStatus(.not_implemented);
}

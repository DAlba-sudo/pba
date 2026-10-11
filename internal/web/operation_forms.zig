//! Stub (owner: WP7): handlers answer 501 until implemented.
const httpz = @import("httpz");
const App = @import("../routes/root.zig").App;

pub fn operationNew(_: App, _: *httpz.Request, res: *httpz.Response) !void {
    res.setStatus(.not_implemented);
}

pub fn operationCreate(_: App, _: *httpz.Request, res: *httpz.Response) !void {
    res.setStatus(.not_implemented);
}

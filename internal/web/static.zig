//! Embedded static assets (fixed routes; no filesystem access).
const httpz = @import("httpz");
const web_static = @import("web_static");
const App = @import("../routes/root.zig").App;

pub const htmx_path = "/static/htmx-2.0.10.min.js";
pub const css_path = "/static/app.css";
pub const uplot_js_path = "/static/uPlot-1.6.31.iife.min.js";
pub const uplot_css_path = "/static/uPlot-1.6.31.min.css";
pub const graph_js_path = "/static/graph.js";

pub fn htmxJs(_: App, _: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JS;
    // The version is in the path, so the file never changes under this URL.
    res.header("Cache-Control", "public, max-age=31536000, immutable");
    res.body = web_static.htmx;
}

pub fn appCss(_: App, _: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .CSS;
    res.header("Cache-Control", "no-cache");
    res.body = web_static.css;
}

pub fn uplotJs(_: App, _: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JS;
    res.header("Cache-Control", "public, max-age=31536000, immutable");
    res.body = web_static.uplot_js;
}

pub fn uplotCss(_: App, _: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .CSS;
    res.header("Cache-Control", "public, max-age=31536000, immutable");
    res.body = web_static.uplot_css;
}

pub fn graphJs(_: App, _: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .JS;
    res.header("Cache-Control", "no-cache");
    res.body = web_static.graph_js;
}

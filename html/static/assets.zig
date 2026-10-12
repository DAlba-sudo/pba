//! Static assets embedded into the binary (served by internal/web/static.zig).
pub const htmx = @embedFile("htmx-2.0.10.min.js");
pub const css = @embedFile("app.css");
pub const uplot_js = @embedFile("uPlot-1.6.31.iife.min.js");
pub const uplot_css = @embedFile("uPlot-1.6.31.min.css");
pub const graph_js = @embedFile("graph.js");

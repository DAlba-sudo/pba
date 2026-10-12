//! Static assets embedded into the binary (served by internal/web/static.zig).
pub const htmx = @embedFile("htmx-2.0.10.min.js");
pub const css = @embedFile("app.css");

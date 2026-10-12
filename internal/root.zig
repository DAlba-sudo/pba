pub const types = @import("types/root.zig");
pub const routes = @import("routes/root.zig");
pub const VERSION = "0.0.0";
pub const Analysis = @import("analysis/root.zig");
pub const web = @import("web/root.zig");

test {
    _ = @import("time/root.zig");
    _ = @import("types/operation.zig");
    _ = @import("web/format.zig");
    _ = @import("web/forms.zig");
    _ = @import("web/render.zig");
}

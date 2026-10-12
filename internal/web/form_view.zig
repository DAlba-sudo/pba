//! View model shared by the account and operation forms (html/account_form.zmpl,
//! html/operation_form.zmpl). Every field is a preformatted string; "" = unset,
//! so templates test errors with `@if ($.err_x)`.
const std = @import("std");
const httpz = @import("httpz");
const forms = @import("forms.zig");
const render = @import("render.zig");
const App = @import("../routes/root.zig").App;

pub const FormView = struct {
    // Echoed input values.
    account_id: []const u8 = "",
    account_name: []const u8 = "",
    name: []const u8 = "",
    initial_balance: []const u8 = "",
    title: []const u8 = "",
    amount: []const u8 = "",
    date: []const u8 = "",
    comment: []const u8 = "",

    // Per-field error messages.
    err_name: []const u8 = "",
    err_initial_balance: []const u8 = "",
    err_account_id: []const u8 = "",
    err_title: []const u8 = "",
    err_amount: []const u8 = "",
    err_date: []const u8 = "",
    err_comment: []const u8 = "",
    err_general: []const u8 = "",

    /// Echoes the trimmed inputs and copies the errors of a validation result.
    pub fn fromResult(r: forms.Result) FormView {
        var v: FormView = .{};
        inline for (std.meta.fields(forms.Input)) |f| {
            @field(v, f.name) = @field(r.input, f.name);
        }
        inline for (std.meta.fields(forms.Result)) |f| {
            if (comptime std.mem.startsWith(u8, f.name, "err_")) {
                @field(v, f.name) = @field(r, f.name) orelse "";
            }
        }
        return v;
    }

    /// Renders form template `name` as a drawer fragment with `status`;
    /// a render failure becomes a 500 flash.
    pub fn send(self: FormView, app: App, res: *httpz.Response, name: []const u8, status: std.http.Status) void {
        render.send(app, res, name, false, self) catch |err| {
            std.log.err("failed to render {s} (err: {s})", .{ name, @errorName(err) });
            return render.flash(res, .internal_server_error, "Could not render form.");
        };
        res.setStatus(status);
    }
};

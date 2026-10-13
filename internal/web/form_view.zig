//! View model shared by the account and operation forms (html/account_form.zmpl,
//! html/operation_form.zmpl). Every field is a preformatted string; "" = unset,
//! so templates test errors with `@if ($.err_x)`.
const std = @import("std");
const httpz = @import("httpz");
const forms = @import("forms.zig");
const render = @import("render.zig");
const App = @import("../routes/root.zig").App;

/// A select option or checkbox: `name` is its value or field name; `attr` is
/// "selected"/"checked" or "".
pub const Opt = struct { name: []const u8, label: []const u8, attr: []const u8 };

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
    draft: []const u8 = "",
    repeat: []const u8 = "",
    until: []const u8 = "",
    /// Operation form only (see `operation`): "checked" or "".
    draft_attr: []const u8 = "",
    repeat_opts: []const Opt = &.{},
    weekday_opts: []const Opt = &.{},

    // Per-field error messages.
    err_name: []const u8 = "",
    err_initial_balance: []const u8 = "",
    err_account_id: []const u8 = "",
    err_title: []const u8 = "",
    err_amount: []const u8 = "",
    err_date: []const u8 = "",
    err_comment: []const u8 = "",
    err_draft: []const u8 = "",
    err_repeat: []const u8 = "",
    err_until: []const u8 = "",
    err_weekdays: []const u8 = "",
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

    /// `fromResult` plus the operation form's checkbox and select state;
    /// options are allocated in `arena`.
    pub fn operation(arena: std.mem.Allocator, r: forms.Result) !FormView {
        var v = fromResult(r);
        v.draft_attr = if (r.draft) "checked" else "";
        // Blank or unknown input selects "none".
        const repeat = r.input.repeat;
        const selected = if (std.mem.eql(u8, repeat, "weekly") or std.mem.eql(u8, repeat, "monthly")) repeat else "none";
        const repeats = [_][2][]const u8{ .{ "none", "Never" }, .{ "weekly", "Weekly" }, .{ "monthly", "Monthly" } };
        const ro = try arena.alloc(Opt, repeats.len);
        for (repeats, ro) |o, *x| {
            x.* = .{ .name = o[0], .label = o[1], .attr = if (std.mem.eql(u8, o[0], selected)) "selected" else "" };
        }
        const labels = [7][]const u8{ "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" };
        const wo = try arena.alloc(Opt, labels.len);
        for (forms.weekday_keys, labels, r.weekdays, wo) |k, l, on, *x| {
            x.* = .{ .name = k, .label = l, .attr = if (on) "checked" else "" };
        }
        v.repeat_opts = ro;
        v.weekday_opts = wo;
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

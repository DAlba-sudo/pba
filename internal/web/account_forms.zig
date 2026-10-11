//! Account create form (drawer) and the shared drawer-close endpoint.
const httpz = @import("httpz");
const App = @import("../routes/root.zig").App;
const Account = @import("../types/root.zig").Account;
const forms = @import("forms.zig");
const render = @import("render.zig");
const FormView = @import("form_view.zig").FormView;

const template = "account_form";

/// GET /ui/accounts/new: empty form fragment for `#drawer-body`.
pub fn accountNew(app: App, _: *httpz.Request, res: *httpz.Response) !void {
    if (app.p == null) return render.flash(res, .service_unavailable, "Database not connected.");
    (FormView{}).send(app, res, template, .ok);
}

/// POST /ui/accounts: 200 empty + `HX-Trigger: pba:accounts-changed` (closes the drawer),
/// or 422 with the re-rendered form.
pub fn accountCreate(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    const p = app.p orelse return render.flash(res, .service_unavailable, "Database not connected.");
    const map = req.formData() catch return render.flash(res, .bad_request, "Invalid form data.");
    const r = forms.validateAccount(map);
    if (!r.ok()) return FormView.fromResult(r).send(app, res, template, .unprocessable_entity);

    _ = Account.create(p, res.arena, r.input.name, r.initial_balance) catch
        return render.flash(res, .internal_server_error, "Could not save the account.");
    res.header("HX-Trigger", "pba:accounts-changed");
}

/// GET /ui/modal/close: empty body, which empties `#drawer-body` and hides the drawer.
pub fn modalClose(_: App, _: *httpz.Request, _: *httpz.Response) !void {}

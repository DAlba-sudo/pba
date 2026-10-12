//! Operation create form (drawer).
const std = @import("std");
const httpz = @import("httpz");
const App = @import("../routes/root.zig").App;
const types = @import("../types/root.zig");
const time = @import("../time/root.zig");
const forms = @import("forms.zig");
const render = @import("render.zig");
const FormView = @import("form_view.zig").FormView;

const template = "operation_form";

/// GET /ui/operations/new?account_id=N: form for an existing account, date preset to today (UTC).
pub fn operationNew(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    const p = app.p orelse return render.flash(res, .service_unavailable, "Database not connected.");
    const q = req.query() catch return render.flash(res, .bad_request, "Invalid query.");
    const raw = q.get("account_id") orelse "";
    const id = forms.parseId(raw) orelse return render.flash(res, .bad_request, "Invalid account.");
    const account = types.Account.get_by_id(p, res.arena, id) catch
        return render.flash(res, .internal_server_error, "Could not load the account.");
    const acc = account orelse return render.flash(res, .not_found, "Account not found.");

    var buf: [10]u8 = undefined;
    const view: FormView = .{
        .account_id = raw,
        .account_name = acc.name,
        .date = time.formatPgDate(time.todayPgDate(app.io), &buf),
    };
    view.send(app, res, template, .ok);
}

/// POST /ui/operations: 200 empty + `HX-Trigger: {"pba:operation-saved":{"account_id":N}}`,
/// or 422 with the re-rendered form (also for unknown or deleted accounts).
pub fn operationCreate(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    const p = app.p orelse return render.flash(res, .service_unavailable, "Database not connected.");
    const map = req.formData() catch return render.flash(res, .bad_request, "Invalid form data.");
    var r = forms.validateOperation(map, time.todayPgDate(app.io));

    var account_name: []const u8 = "";
    if (r.err_account_id == null) {
        const account = types.Account.get_by_id(p, res.arena, r.account_id) catch
            return render.flash(res, .internal_server_error, "Could not load the account.");
        if (account) |a| account_name = a.name else r.err_account_id = "Account not found.";
    }
    if (!r.ok()) {
        var view = FormView.fromResult(r);
        view.account_name = account_name;
        return view.send(app, res, template, .unprocessable_entity);
    }

    // Built from the integer only, so no JSON escaping is needed.
    const trigger = std.fmt.allocPrint(res.arena, "{{\"pba:operation-saved\":{{\"account_id\":{d}}}}}", .{r.account_id}) catch
        return render.flash(res, .internal_server_error, "Could not save the operation.");
    _ = types.Operation.create(p, res.arena, r.amount, r.date, r.input.title, r.comment, r.account_id) catch
        return render.flash(res, .internal_server_error, "Could not save the operation.");
    res.header("HX-Trigger", trigger);
}

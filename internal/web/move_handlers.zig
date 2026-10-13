//! Moving operations between accounts from a card's bulk bar.
const std = @import("std");
const httpz = @import("httpz");
const App = @import("../routes/root.zig").App;
const types = @import("../types/root.zig");
const forms = @import("forms.zig");
const render = @import("render.zig");
const cards = @import("handlers_cards.zig");
const bulkForm = @import("delete_handlers.zig").bulkForm;

/// POST /ui/cards/:id/operations/move (form `sel`=<operation id>, repeated,
/// `to`=<live account id other than :id>, filters, `oq`): moves the selected
/// operations of that account and re-renders its card. The target card
/// reloads itself on `pba:operation-saved`. Ids from other accounts are ignored.
pub fn operationsMove(app: App, req: *httpz.Request, res: *httpz.Response) !void {
    const p = app.p orelse return cards.noDatabase(res);
    const b = bulkForm(app, req, res) orelse return;
    const to = forms.parseId(b.map.get("to") orelse "") orelse return invalidTarget(res);
    if (to == b.account_id) return invalidTarget(res);
    const target = types.Account.get_by_id(p, res.arena, to) catch |err| return cards.fail(res, "get account", err);
    if (target == null) return invalidTarget(res);

    const moved = types.Operation.move_many(p, b.account_id, to, b.ids) catch |err| return cards.fail(res, "move operations", err);
    if (moved > 0) {
        // Built from the integer only, so no JSON escaping is needed.
        const trigger = std.fmt.allocPrint(res.arena, "{{\"pba:operation-saved\":{{\"account_id\":{d}}}}}", .{to}) catch |err|
            return cards.fail(res, "build trigger", err);
        res.header("HX-Trigger", trigger);
    }
    cards.renderCardFragment(app, res, b.account_id, b.f, b.oq);
}

fn invalidTarget(res: *httpz.Response) void {
    render.flash(res, .bad_request, "Invalid target account.");
}

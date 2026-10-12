@args c: ZmplValue, more: bool, none: bool
@zig {
  const ops = c.get("ops").?;
}
@if (none)
<tr><td colspan="5" class="muted">No operations.</td></tr>
@end
@for (ops) |op| {
<tr><td>{{op.title}}</td><td class="num {{op.cls}}">{{op.value}}</td><td>{{op.date}}</td><td class="{{op.comment_cls}}">{{op.comment}}</td><td class="actions"><button type="button" class="btn-del" aria-label="Delete" hx-delete="/ui/operations/{{op.id}}" hx-confirm="Delete {{op.title}}?" hx-include="#filters, #card-{{c.id}} [name=oq]" hx-target="#card-{{c.id}}" hx-swap="outerHTML" hx-push-url="false">&times;</button></td></tr>
}
@if (more)
<tr class="more-row"><td colspan="5"><button type="button" hx-get="/ui/cards/{{c.id}}/ops?cursor={{c.next_cursor}}" hx-include="#filters, #card-{{c.id}} [name=oq]" hx-target="closest tr" hx-swap="outerHTML" hx-push-url="false" hx-disabled-elt="this">Load more</button></td></tr>
@end

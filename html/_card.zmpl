@args c: ZmplValue
<article class="card" id="card-{{c.id}}" hx-get="/ui/cards/{{c.id}}" hx-trigger="pba:operation-saved[detail.account_id=={{c.id}}] from:body" hx-include="#filters, #card-{{c.id}} [name=oq]" hx-target="this" hx-swap="outerHTML">
<div class="card-head">
<h2>{{c.name}}</h2>
<input class="card-search" name="oq" type="search" value="{{c.oq}}" placeholder="Search" aria-label="Search operations" hx-get="/ui/cards/{{c.id}}/ops" hx-trigger="input changed delay:300ms, search" hx-include="#filters" hx-target="#ops-{{c.id}}" hx-swap="outerHTML" hx-sync="this:replace" hx-push-url="false">
<button type="button" class="btn-add" aria-label="Add operation" hx-get="/ui/operations/new?account_id={{c.id}}" hx-target="#drawer-body" hx-swap="innerHTML" hx-push-url="false">+</button>
<span class="balance {{c.balance_cls}}">{{c.balance}}</span>
<button type="button" class="btn-del" aria-label="Delete account" hx-delete="/ui/accounts/{{c.id}}" hx-confirm="Delete account {{c.name}}?" hx-include="#filters" hx-target="#cards" hx-swap="innerHTML" hx-push-url="false">&times;</button>
</div>
<div class="bulk-bar"><span>Delete the checked operations?</span><button type="button" class="btn-bulk-del" hx-post="/ui/cards/{{c.id}}/operations/delete" hx-confirm="Delete the selected operations?" hx-include="#filters, #card-{{c.id}} [name=oq], #card-{{c.id}} [name=sel]:checked" hx-target="#card-{{c.id}}" hx-swap="outerHTML" hx-push-url="false" hx-disabled-elt="this">Delete selected</button></div>
<table class="ops">
<thead><tr><th class="sel"><input type="checkbox" aria-label="Select all operations" onchange="this.closest('table').querySelectorAll('input[name=sel]').forEach(function(b){b.checked=this.checked}.bind(this))"></th><th>Title</th><th>Value</th><th>Date</th><th>Comment</th><th></th></tr></thead>
<tbody id="ops-{{c.id}}">
@partial ops_rows(c, c.has_more, c.no_ops)
</tbody>
</table>
</article>

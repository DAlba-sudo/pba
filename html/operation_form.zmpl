<form hx-post="/ui/operations" hx-target="#drawer-body" hx-swap="innerHTML" hx-push-url="false" hx-disabled-elt="find button[type=submit]">
<h2>New operation</h2>
<input type="hidden" name="account_id" value="{{$.account_id}}">
<p class="muted">Account: {{$.account_name}}</p>
@if ($.err_account_id)
<p class="field-error">{{$.err_account_id}}</p>
@end
@if ($.err_general)
<p class="field-error">{{$.err_general}}</p>
@end
<div class="field">
<label for="op-title">Title</label>
<input id="op-title" name="title" type="text" autofocus value="{{$.title}}">
@if ($.err_title)
<p class="field-error">{{$.err_title}}</p>
@end
</div>
<div class="field">
<label for="op-amount">Amount</label>
<input id="op-amount" name="amount" type="text" inputmode="decimal" placeholder="-12.34" value="{{$.amount}}">
<p class="muted">Signed: negative = expense, positive = income.</p>
@if ($.err_amount)
<p class="field-error">{{$.err_amount}}</p>
@end
</div>
<div class="field">
<label for="op-date">Date</label>
<input id="op-date" name="date" type="date" value="{{$.date}}">
@if ($.err_date)
<p class="field-error">{{$.err_date}}</p>
@end
</div>
<div class="field">
<label for="op-comment">Comment</label>
<input id="op-comment" name="comment" type="text" value="{{$.comment}}">
@if ($.err_comment)
<p class="field-error">{{$.err_comment}}</p>
@end
</div>
<div class="actions">
<button type="button" hx-get="/ui/modal/close" hx-target="#drawer-body" hx-swap="innerHTML" hx-push-url="false">Cancel</button>
<button type="submit">Save</button>
</div>
</form>

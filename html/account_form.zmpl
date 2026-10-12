<form hx-post="/ui/accounts" hx-target="#drawer-body" hx-swap="innerHTML" hx-push-url="false" hx-disabled-elt="find button[type=submit]">
<h2>New account</h2>
@if ($.err_general)
<p class="field-error">{{$.err_general}}</p>
@end
<div class="field">
<label for="account-name">Name</label>
<input id="account-name" name="name" type="text" autofocus value="{{$.name}}">
@if ($.err_name)
<p class="field-error">{{$.err_name}}</p>
@end
</div>
<div class="field">
<label for="account-initial-balance">Initial balance</label>
<input id="account-initial-balance" name="initial_balance" type="text" inputmode="decimal" placeholder="0.00" value="{{$.initial_balance}}">
@if ($.err_initial_balance)
<p class="field-error">{{$.err_initial_balance}}</p>
@end
</div>
<div class="actions">
<button type="button" hx-get="/ui/modal/close" hx-target="#drawer-body" hx-swap="innerHTML" hx-push-url="false">Cancel</button>
<button type="submit">Save</button>
</div>
</form>

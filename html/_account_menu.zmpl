@args h: ZmplValue, oob: bool
@if (oob)
<details id="account-menu" class="menu" hx-swap-oob="true">
@else
<details id="account-menu" class="menu">
@end
<summary>{{h.account_label}}</summary>
<div class="menu-list">
@zig {
  const all_selected = try h.chainRefT(bool, "all_selected");
  const accounts = h.get("accounts").?;
}
<label><input type="radio" name="account" value="all"
@if (all_selected)
checked
@end
>All</label>
@for (accounts) |a| {
@zig {
  const selected = try a.chainRefT(bool, "selected");
}
<label><input type="radio" name="account" value="{{a.id}}"
@if (selected)
checked
@end
>{{a.name}}</label>
}
<button type="button" hx-get="/ui/accounts/new" hx-target="#drawer-body" hx-swap="innerHTML" hx-push-url="false">Create</button>
</div>
</details>

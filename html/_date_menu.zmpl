@args h: ZmplValue, oob: bool
@if (oob)
<details id="date-menu" class="menu" hx-swap-oob="true">
@else
<details id="date-menu" class="menu">
@end
<summary>{{h.date_label}}</summary>
<div class="menu-list">
<input type="date" name="date" value="{{h.date_value}}" aria-label="Date">
<button type="button" hx-get="/" hx-vals='{"date":""}' hx-include="#filters" hx-target="#cards" hx-swap="innerHTML" hx-push-url="true">Clear</button>
</div>
</details>

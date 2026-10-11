@args page: ZmplValue, more: bool, show_empty: bool
@zig {
  const cards = page.get("cards").?;
}
@if (show_empty)
<p class="empty">{{page.empty}}</p>
@end
@for (cards) |c| {
@partial card(c)
}
@if (more)
<div class="sentinel" hx-get="/ui/accounts/page?{{page.next_query}}" hx-trigger="revealed" hx-target="this" hx-swap="outerHTML" hx-push-url="false" hx-sync="#filters:abort">Loading...</div>
@end

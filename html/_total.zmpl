@args t: ZmplValue, oob: bool
@if (oob)
<span id="total" class="badge {{t.cls}}" hx-swap-oob="true">{{t.text}}</span>
@else
<span id="total" class="badge {{t.cls}}">{{t.text}}</span>
@end

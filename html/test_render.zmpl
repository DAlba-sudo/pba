<p>{{$.name}} {{$.count}}</p>
@if ($.flag)
<b>on</b>
@end
@for ($.rows) |row| {
<i>{{row.title}}={{row.n}}</i>
}

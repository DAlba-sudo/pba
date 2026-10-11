@if ($.tbody)
<tbody id="ops-{{$.card.id}}">
@end
@partial ops_rows($.card, $.more, $.none)
@if ($.tbody)
</tbody>
@end

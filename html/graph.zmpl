<link rel="stylesheet" href="/static/uPlot-1.6.31.min.css">
<div class="page">
<header class="topbar">
<h1>balance over time</h1>
<a href="/">Dashboard</a>
</header>
<form id="graph-form" class="graph-form">
<label>From <input type="date" name="from" value="{{$.from}}" required></label>
<label>To <input type="date" name="to" value="{{$.to}}" required></label>
<label>Min $ <input type="number" name="ymin" step="any" placeholder="auto"></label>
<label>Max $ <input type="number" name="ymax" step="any" placeholder="auto"></label>
<label>Account <select name="account_id">
<option value=""
@if ($.all_selected)
selected
@end
>All</option>
@for ($.accounts) |a| {
<option value="{{a.id}}">{{a.name}}</option>
}
</select></label>
<button type="submit">Plot</button>
</form>
<p id="graph-error" class="graph-error" role="alert" hidden></p>
<div id="graph" class="graph"></div>
</div>
<script src="/static/uPlot-1.6.31.iife.min.js"></script>
<script src="/static/graph.js"></script>

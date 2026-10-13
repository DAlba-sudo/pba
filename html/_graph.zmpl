@args g: ZmplValue
<section class="graph-panel" aria-label="Balance over time">
<form id="graph-form" class="graph-form">
<label>From <input type="date" name="from" value="{{g.from}}" required></label>
<p class="graph-to">To <output id="graph-to">{{g.to}}</output></p>
<label>Min $ <input type="number" name="ymin" step="any" placeholder="auto"></label>
<label>Max $ <input type="number" name="ymax" step="any" placeholder="auto"></label>
<label class="graph-check"><input type="checkbox" name="by_account"> By account</label>
<button type="submit">Plot</button>
</form>
<p id="graph-error" class="graph-error" role="alert" hidden></p>
<p id="graph-note" class="graph-note" hidden>Showing first 12 accounts.</p>
<div id="graph" class="graph"></div>
</section>

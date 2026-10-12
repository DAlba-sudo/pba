@args g: ZmplValue
<section class="graph-panel" aria-label="Balance over time">
<form id="graph-form" class="graph-form">
<label>From <input type="date" name="from" value="{{g.from}}" required></label>
<label>To <input type="date" name="to" value="{{g.to}}" required></label>
<label>Min $ <input type="number" name="ymin" step="any" placeholder="auto"></label>
<label>Max $ <input type="number" name="ymax" step="any" placeholder="auto"></label>
<button type="submit">Plot</button>
</form>
<p id="graph-error" class="graph-error" role="alert" hidden></p>
<div id="graph" class="graph"></div>
</section>

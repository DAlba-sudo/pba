// Balance-over-time chart: reads the bounds from #graph-form, fetches
// /api/money/series and draws it with uPlot.
(function () {
  var form = document.getElementById("graph-form");
  var host = document.getElementById("graph");
  var errEl = document.getElementById("graph-error");
  var plot = null;

  function num(v) {
    if (v === "") return null;
    var n = parseFloat(v);
    return isFinite(n) ? n : null;
  }

  function fail(msg) {
    errEl.textContent = msg;
    errEl.hidden = !msg;
  }

  function draw(points, xMin, xMax, yMin, yMax) {
    var xs = points.map(function (p) { return p[0]; });
    var ys = points.map(function (p) { return p[1]; });
    if (plot) plot.destroy();
    plot = new uPlot({
      width: host.clientWidth,
      height: 400,
      scales: {
        x: { time: true, range: function () { return [xMin, xMax]; } },
        y: {
          range: function (_u, lo, hi) {
            if (lo === hi) { lo -= 1; hi += 1; }
            var pad = (hi - lo) * 0.05;
            return [yMin !== null ? yMin : lo - pad, yMax !== null ? yMax : hi + pad];
          },
        },
      },
      axes: [
        { stroke: "#9aa0aa", grid: { stroke: "#2e333d" } },
        {
          stroke: "#9aa0aa",
          grid: { stroke: "#2e333d" },
          size: 80,
          values: function (_u, vals) { return vals.map(function (v) { return "$" + v.toLocaleString(); }); },
        },
      ],
      series: [
        {},
        { label: "Balance", stroke: "#5b9cff", width: 2, points: { show: false }, paths: uPlot.paths.stepped({ align: 1 }),
          value: function (_u, v) { return v === null ? "--" : "$" + v.toFixed(2); } },
      ],
    }, [xs, ys], host);
  }

  function load() {
    var d = new FormData(form);
    var from = d.get("from"), to = d.get("to");
    var q = new URLSearchParams({ from: from, to: to });
    if (d.get("account_id")) q.set("account_id", d.get("account_id"));
    fail("");
    fetch("/api/money/series?" + q)
      .then(function (r) { return r.json().then(function (j) { return { ok: r.ok, j: j }; }); })
      .then(function (r) {
        if (!r.ok) return fail(r.j.err || "Request failed.");
        var xMin = Date.parse(from + "T00:00:00Z") / 1000;
        var xMax = Date.parse(to + "T00:00:00Z") / 1000;
        var yMin = num(d.get("ymin")), yMax = num(d.get("ymax"));
        if (yMin !== null && yMax !== null && yMin >= yMax) return fail("Min $ must be below Max $.");
        draw(r.j.points, xMin, xMax, yMin, yMax);
      })
      .catch(function () { fail("Could not load the data."); });
  }

  form.addEventListener("submit", function (e) { e.preventDefault(); load(); });
  window.addEventListener("resize", function () {
    if (plot) plot.setSize({ width: host.clientWidth, height: 400 });
  });
  load();
})();

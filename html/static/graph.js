// Balance-over-time chart on the dashboard: reads From and the money bounds
// from #graph-form, the end date and account from the dashboard filters,
// fetches /api/money/series, draws it with uPlot and redraws whenever the
// dashboard data or the global date changes.
(function () {
  // Back/forward swaps the page body in again and htmx re-runs this script;
  // the document listeners below must be installed only once.
  if (window.pbaGraphReload) return window.pbaGraphReload();
  var plot = null;
  var DAY = 86400000;
  // Per-account lines: readable on the dark grid and distinct from the total's blues.
  var PALETTE = ["#f59e0b", "#2dd4bf", "#f472b6", "#facc15", "#c084fc", "#f87171", "#a3e635", "#d1d5db"];

  function $(id) { return document.getElementById(id); }
  function iso(ms) { return new Date(ms).toISOString().slice(0, 10); }

  function num(v) {
    if (v === "") return null;
    var n = parseFloat(v);
    return isFinite(n) ? n : null;
  }

  function money(_u, v) { return v === null ? "--" : "$" + v.toFixed(2); }

  // The header's global date; empty means today (UTC), as Filters.effective_date.
  function globalDate() {
    var el = document.querySelector('#filters input[name="date"]');
    return (el && el.value) || iso(Date.now());
  }

  function fail(msg) {
    var el = $("graph-error");
    el.textContent = msg;
    el.hidden = !msg;
  }

  function line(label, stroke, extra) {
    var s = { label: label, stroke: stroke, width: 2, points: { show: false },
      paths: uPlot.paths.stepped({ align: 1 }), value: money };
    for (var k in extra) s[k] = extra[k];
    return s;
  }

  function draw(host, j, xMin, xMax, yMin, yMax) {
    var points = j.points, withDrafts = j.with_drafts;
    var xs = points.map(function (p) { return p[0]; });
    var ys = points.map(function (p) { return p[1]; });
    var series = [{}], data = [xs];
    (j.accounts || []).forEach(function (a, i) {
      series.push(line(a.name, PALETTE[i % PALETTE.length], { width: 1.5 }));
      data.push(a.balance);
    });
    // Drawn first so the balance line stays on top; omitted when drafts change nothing.
    if (withDrafts.some(function (v, i) { return v !== ys[i]; })) {
      series.push(line("With drafts", "#9ec2ff", { dash: [4, 4] }));
      data.push(withDrafts);
    }
    series.push(line("Balance", "#5b9cff", { width: 2.5 }));
    data.push(ys);
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
      series: series,
    }, data, host);
  }

  function load() {
    var form = $("graph-form"), host = $("graph");
    if (!form || !host) return;
    var to = globalDate();
    $("graph-to").textContent = to;
    // A global date before From would be an empty range: keep a 90-day window.
    if (form.elements.from.value > to) form.elements.from.value = iso(Date.parse(to) - 90 * DAY);
    var d = new FormData(form);
    var from = d.get("from");
    var q = new URLSearchParams({ from: from, to: to });
    var acct = document.querySelector('#filters input[name="account"]:checked');
    var single = !!acct && acct.value !== "all";
    // A breakdown of one account is moot: the box is disabled and ignored.
    form.elements.by_account.disabled = single;
    if (single) q.set("account_id", acct.value);
    else if (form.elements.by_account.checked) q.set("by_account", "1");
    fail("");
    $("graph-note").hidden = true;
    fetch("/api/money/series?" + q)
      .then(function (r) { return r.json().then(function (j) { return { ok: r.ok, j: j }; }); })
      .then(function (r) {
        if (!r.ok) return fail(r.j.err || "Request failed.");
        var xMin = Date.parse(from + "T00:00:00Z") / 1000;
        var xMax = Date.parse(to + "T00:00:00Z") / 1000;
        var yMin = num(d.get("ymin")), yMax = num(d.get("ymax"));
        if (yMin !== null && yMax !== null && yMin >= yMax) return fail("Min $ must be below Max $.");
        $("graph-note").hidden = !r.j.truncated;
        draw(host, r.j, xMin, xMax, yMin, yMax);
      })
      .catch(function () { fail("Could not load the data."); });
  }

  var timer = null;
  function reload() {
    clearTimeout(timer);
    timer = setTimeout(load, 100);
  }
  window.pbaGraphReload = reload;

  function inGraphForm(e) { return e.target.closest && e.target.closest("#graph-form"); }
  document.addEventListener("submit", function (e) {
    if (inGraphForm(e)) { e.preventDefault(); load(); }
  });
  document.addEventListener("change", function (e) { if (inGraphForm(e)) reload(); });
  // Operations/accounts added, deleted or toggled (any non-GET htmx request),
  // and filter or global date changes (GETs from inside #filters) change the
  // balances or the range. The date menu's Clear button is matched by
  // #date-menu: by now its OOB swap has detached it from #filters.
  document.addEventListener("htmx:afterRequest", function (e) {
    var cfg = e.detail.requestConfig || {};
    if (!e.detail.successful) return;
    var elt = cfg.elt;
    if ((cfg.verb || "get") !== "get" || (elt && elt.closest && elt.closest("#filters, #date-menu"))) reload();
  });
  document.addEventListener("htmx:historyRestore", reload);
  window.addEventListener("resize", function () {
    var host = $("graph");
    if (plot && host) plot.setSize({ width: host.clientWidth, height: 400 });
  });
  load();
})();

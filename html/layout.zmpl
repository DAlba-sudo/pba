<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="htmx-config" content='{"includeIndicatorStyles":false,"historyCacheSize":0,"responseHandling":[{"code":"204","swap":false},{"code":"[23]..","swap":true},{"code":"[45]..","swap":true,"error":true}]}'>
<title>personal budget app</title>
<link rel="stylesheet" href="/static/app.css">
<script src="/static/htmx-2.0.10.min.js"></script>
</head>
<body>
<div id="flash" role="status" aria-live="polite"></div>
{{zmpl.content}}
<aside id="drawer" role="dialog" aria-modal="true">
<div id="drawer-backdrop" hx-get="/ui/modal/close" hx-trigger="click, keyup[key=='Escape' && document.getElementById('drawer-body').hasChildNodes()] from:body" hx-target="#drawer-body" hx-swap="innerHTML" hx-push-url="false"></div>
<div class="drawer-panel"><div id="drawer-body"></div></div>
</aside>
</body>
</html>

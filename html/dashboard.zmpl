<div class="page">
<form id="filters" hx-get="/" hx-target="#cards" hx-swap="innerHTML" hx-push-url="true" hx-sync="this:replace" hx-disinherit="*" hx-trigger="change[target.name!='q'], input[target.name=='q'] delay:300ms, submit, pba:accounts-changed from:body">
<header class="topbar">
<h1>personal budget app</h1>
@partial total($.total, false)
@partial date_menu($.header, false)
@partial account_menu($.header, false)
<a class="menu-link" href="/graph">Graph</a>
</header>
<input class="search-full" type="search" name="q" value="{{$.header.q}}" placeholder="Search accounts" aria-label="Search accounts">
</form>
<main id="cards" class="cards">
@partial cards_list($.page, $.more, $.show_empty)
</main>
</div>

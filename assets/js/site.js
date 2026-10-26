/* Fraud Board: board/brief switching, Edition calendar, keyword dropdown. */
(function () {
  'use strict';

  /* ------------------------------------------------------------ board <-> regional brief
     Every day page holds the board and all regional briefs. The address decides which
     one shows:  /2026/10/25/           -> board
                 /2026/10/25/#us        -> United States brief
                 /2026/10/25/#us/<id>   -> that brief, scrolled to one item
     Without JavaScript everything is simply shown, one section after another. */
  var views = Array.prototype.slice.call(document.querySelectorAll('[data-view]'));
  var baseTitle = document.title;

  function currentHash() {
    try { return decodeURIComponent(location.hash.replace(/^#/, '')); } catch (e) { return ''; }
  }

  function route(isFirst) {
    if (!views.length) return;
    var parts = currentHash().split('/');
    var regionId = parts[0];
    var itemId = parts[1];
    var target = 'board';
    for (var i = 0; i < views.length; i++) {
      if (regionId && regionId !== 'board' && views[i].getAttribute('data-view') === regionId) target = regionId;
    }
    var active = null;
    views.forEach(function (v) {
      var on = v.getAttribute('data-view') === target;
      v.classList.toggle('is-active', on);
      if (on) active = v;
    });

    var heading = active && active.querySelector('h1');
    document.title = target === 'board' || !heading ? baseTitle : heading.textContent + ' · ' + baseTitle;

    var item = itemId ? document.getElementById('inc-' + regionId + '-' + itemId) : null;
    if (item && target !== 'board') {
      item.scrollIntoView({ block: 'start' });
      item.classList.remove('flash');
      void item.offsetWidth; // restart the highlight
      item.classList.add('flash');
    } else if (!isFirst || target !== 'board') {
      window.scrollTo(0, 0);
    }
    // Move keyboard / screen-reader focus to the new view's heading
    if (!isFirst && heading) {
      try { heading.focus({ preventScroll: !!item }); } catch (e) { heading.focus(); }
    }
  }

  if (views.length) {
    window.addEventListener('hashchange', function () { route(false); });
    route(true);
  }

  /* ------------------------------------------------------------ keyword dropdown */
  var kw = document.querySelector('[data-keyword-select]');
  if (kw) {
    kw.addEventListener('change', function () {
      if (kw.value) window.location.href = kw.value;
    });
  }

  /* ------------------------------------------------------------ Edition calendar */
  var toggle = document.getElementById('cal-toggle');
  var panel = document.getElementById('calendar');
  var dataEl = document.getElementById('edition-data');
  if (!toggle || !panel || !dataEl) return;

  var editions = [];
  try { editions = JSON.parse(dataEl.textContent || '[]') || []; } catch (e) { editions = []; }
  var byDate = {};
  editions.forEach(function (e) { byDate[e.d] = e; });

  var MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July',
                'August', 'September', 'October', 'November', 'December'];
  var DAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

  function parse(iso) { var p = iso.split('-'); return { y: +p[0], m: +p[1] - 1, d: +p[2] }; }
  function pad(n) { return (n < 10 ? '0' : '') + n; }
  function iso(y, m, d) { return y + '-' + pad(m + 1) + '-' + pad(d); }
  function monthIndex(y, m) { return y * 12 + m; }

  var current = toggle.getAttribute('data-current') || '';
  var first = editions.length ? parse(editions[0].d) : null;
  var last = editions.length ? parse(editions[editions.length - 1].d) : null;
  var start = current ? parse(current) : last;
  var view = start ? { y: start.y, m: start.m } : null;

  function el(tag, attrs, text) {
    var n = document.createElement(tag);
    if (attrs) Object.keys(attrs).forEach(function (k) { n.setAttribute(k, attrs[k]); });
    if (text != null) n.textContent = text;
    return n;
  }

  function render() {
    panel.textContent = '';
    if (!view) {
      panel.appendChild(el('p', { 'class': 'cal-note' }, 'No editions have been published yet.'));
      return;
    }
    var head = el('div', { 'class': 'cal-head' });
    var prev = el('button', { type: 'button', 'class': 'cal-nav', 'aria-label': 'Previous month' }, '‹');
    var next = el('button', { type: 'button', 'class': 'cal-nav', 'aria-label': 'Next month' }, '›');
    var title = el('div', { 'class': 'cal-month', 'aria-live': 'polite' }, MONTHS[view.m] + ' ' + view.y);
    var idx = monthIndex(view.y, view.m);
    prev.disabled = idx <= monthIndex(first.y, first.m);
    next.disabled = idx >= monthIndex(last.y, last.m);
    prev.addEventListener('click', function () { shift(-1); });
    next.addEventListener('click', function () { shift(1); });
    head.appendChild(prev); head.appendChild(title); head.appendChild(next);
    panel.appendChild(head);

    var table = el('table', { 'class': 'cal-grid' });
    var thead = el('thead'); var hr = el('tr');
    DAYS.forEach(function (d) { var th = el('th', { scope: 'col', abbr: d }, d.charAt(0)); hr.appendChild(th); });
    thead.appendChild(hr); table.appendChild(thead);

    var tbody = el('tbody');
    var firstDow = new Date(view.y, view.m, 1).getDay();
    var daysIn = new Date(view.y, view.m + 1, 0).getDate();
    var row = el('tr');
    for (var b = 0; b < firstDow; b++) row.appendChild(el('td'));
    for (var day = 1; day <= daysIn; day++) {
      var key = iso(view.y, view.m, day);
      var e = byDate[key];
      var td = el('td');
      var label = DAYS[new Date(view.y, view.m, day).getDay()] + ', ' + MONTHS[view.m] + ' ' + day + ', ' + view.y;
      if (e) {
        var a = el('a', {
          'class': 'cal-day l' + (e.l || 1),
          href: e.u,
          title: e.n + (e.n === 1 ? ' story' : ' stories') + ' · ' + e.s + (e.s === 1 ? ' source' : ' sources'),
          'aria-label': label + ': ' + e.n + (e.n === 1 ? ' story' : ' stories')
        }, String(day));
        if (key === current) a.setAttribute('aria-current', 'date');
        td.appendChild(a);
      } else {
        var s = el('span', { 'class': 'cal-day', title: 'No briefing' }, String(day));
        s.appendChild(el('span', { 'class': 'visually-hidden' }, ' (no briefing)'));
        td.appendChild(s);
      }
      row.appendChild(td);
      if ((firstDow + day) % 7 === 0) { tbody.appendChild(row); row = el('tr'); }
    }
    if (row.children.length) {
      while (row.children.length < 7) row.appendChild(el('td'));
      tbody.appendChild(row);
    }
    table.appendChild(tbody);
    panel.appendChild(table);

    var legend = el('div', { 'class': 'cal-legend', 'aria-hidden': 'true' });
    legend.appendChild(el('span', null, 'Fewer'));
    for (var l = 1; l <= 4; l++) legend.appendChild(el('i', { 'class': 'l' + l }));
    legend.appendChild(el('span', null, 'More'));
    panel.appendChild(legend);
    panel.appendChild(el('p', { 'class': 'cal-note' }, 'Shade shows how many stories that day’s briefing covers.'));
  }

  function shift(delta) {
    var i = monthIndex(view.y, view.m) + delta;
    view = { y: Math.floor(i / 12), m: i % 12 };
    render();
    var btn = panel.querySelectorAll('.cal-nav')[delta < 0 ? 0 : 1];
    if (btn && !btn.disabled) btn.focus();
    else { var any = panel.querySelector('.cal-nav:not(:disabled)'); if (any) any.focus(); }
  }

  function open() {
    if (start) view = { y: start.y, m: start.m };
    render();
    panel.hidden = false;
    toggle.setAttribute('aria-expanded', 'true');
    var focusTarget = panel.querySelector('[aria-current="date"]') || panel.querySelector('a.cal-day') || panel.querySelector('.cal-nav');
    if (focusTarget) focusTarget.focus();
  }

  function close(returnFocus) {
    if (panel.hidden) return;
    panel.hidden = true;
    toggle.setAttribute('aria-expanded', 'false');
    if (returnFocus) toggle.focus();
  }

  toggle.addEventListener('click', function () {
    if (panel.hidden) open(); else close(true);
  });
  panel.addEventListener('keydown', function (ev) {
    if (ev.key === 'Escape') { ev.preventDefault(); close(true); }
  });
  toggle.addEventListener('keydown', function (ev) {
    if (ev.key === 'Escape') close(false);
  });
  document.addEventListener('click', function (ev) {
    if (!panel.hidden && !panel.contains(ev.target) && !toggle.contains(ev.target)) close(false);
  });
})();

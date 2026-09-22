/* Pick options on a mockup page and build a prompt the owner pastes back to the agent.

   The server never sees any of this, and that is the design rather than a first step. An
   endpoint that fed picks into an agent's context would be reachable by anyone who can reach
   port 8765, which the dashboard opens on every interface over plain HTTP. Routing the answer
   through the owner's own prompt keeps it in the channel that is already trusted, and costs
   one paste.

   Drop this file beside a mockup set and load it with <script src="picks.js" defer>. It works
   from the dashboard and from a file:// clone alike, because mockup sets are committed to the
   spec repo and have to render there too.

     <section data-pick-group="music-warm" data-pick-label="Music: the warm half">
       <article data-pick-option="with-the-wind"><h3>With the wind</h3>...</article>
       <article data-pick-option="sun-and-moon"><h3>Sun and moon</h3>...</article>
     </section>

   data-pick-label  optional override. A group otherwise takes its first heading that is not
                    inside an option; an option takes its own first heading, then its text.
   data-pick-multi  on a group, allows more than one option.
   data-pick-note   "off" on a group drops its note box.

   Ids are [a-z0-9][a-z0-9_-]{0,63}, unique per page for groups and per group for options.
   Anything else is reported to the console and the group is skipped, because a mockup with a
   duplicate id produces a prompt that names the same choice twice.
*/
(function () {
  'use strict';

  var ID = /^[a-z0-9][a-z0-9_-]{0,63}$/;
  var NOTE_MAX = 280;
  var STORE = 'sdd-picks:' + location.pathname;

  var groups, bar;
  // defer is what the skill tells an author to write, but a script tag in the head without it
  // would otherwise find no body and fail silently, which is the worst way for this to break.
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
  else start();

  function start() {
    groups = collect();
    if (!groups.length) return;
    style();
    bar = buildBar();
    groups.forEach(render);
    restore();
    update();
  }

  // ---- the page ------------------------------------------------------------------------

  function collect() {
    var seen = {}, out = [];
    each(document.querySelectorAll('[data-pick-group]'), function (el) {
      var id = el.getAttribute('data-pick-group');
      if (!ID.test(id)) return warn('group id is not [a-z0-9][a-z0-9_-]{0,63}: ' + id);
      if (seen[id]) return warn('duplicate group id, skipping the second: ' + id);
      seen[id] = true;

      var opts = [], ids = {};
      each(el.querySelectorAll('[data-pick-option]'), function (o) {
        if (o.closest('[data-pick-group]') !== el) return;  // belongs to a nested group
        var oid = o.getAttribute('data-pick-option');
        if (!ID.test(oid)) return warn('option id is not [a-z0-9][a-z0-9_-]{0,63}: ' + oid);
        if (ids[oid]) return warn('duplicate option id in group ' + id + ': ' + oid);
        ids[oid] = true;
        // Read the label before any button is appended, or it lands in the text.
        opts.push({ id: oid, el: o, label: label(o, oid) });
      });
      if (!opts.length) return warn('group with no options: ' + id);

      out.push({
        id: id, el: el, options: opts,
        label: el.getAttribute('data-pick-label') || heading(el) || id,
        multi: el.hasAttribute('data-pick-multi'),
        note: el.getAttribute('data-pick-note') !== 'off',
        picked: [], noteText: ''
      });
    });
    return out;
  }

  function label(o, fallback) {
    return o.getAttribute('data-pick-label') || firstHeading(o) || text(o) || fallback;
  }

  function heading(group) {
    var found = null;
    each(group.querySelectorAll('h1,h2,h3,h4,h5,h6'), function (h) {
      if (!found && !h.closest('[data-pick-option]')) found = clean(h.textContent);
    });
    return found;
  }

  function firstHeading(el) {
    var h = el.querySelector('h1,h2,h3,h4,h5,h6');
    return h ? clean(h.textContent) : null;
  }

  function text(el) {
    var t = clean(el.textContent);
    return t.length > 80 ? t.slice(0, 79) + '…' : t;
  }

  function clean(s) { return (s || '').replace(/\s+/g, ' ').trim(); }
  function warn(m) { if (window.console) console.warn('picks.js: ' + m); }
  function each(list, fn) { Array.prototype.forEach.call(list, fn); }

  function el(tag, cls, txt) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (txt != null) n.textContent = txt;
    return n;
  }

  // ---- controls ------------------------------------------------------------------------

  function render(g) {
    g.el.classList.add('sdd-pick-group');
    g.options.forEach(function (o) {
      o.el.classList.add('sdd-pickable');
      o.btn = el('button', 'sdd-pick-btn', 'Pick');
      o.btn.type = 'button';
      o.btn.addEventListener('click', function () { toggle(g, o); });
      o.el.appendChild(o.btn);
    });
    if (!g.note) return;
    var wrap = el('div', 'sdd-pick-note');
    g.noteEl = el('textarea');
    g.noteEl.maxLength = NOTE_MAX;
    g.noteEl.rows = 1;
    g.noteEl.placeholder = 'note on this choice (optional)';
    g.noteEl.addEventListener('input', function () {
      g.noteText = g.noteEl.value;
      g.noteEl.style.height = 'auto';
      g.noteEl.style.height = Math.min(g.noteEl.scrollHeight, 144) + 'px';
      update();
    });
    wrap.appendChild(g.noteEl);
    g.el.appendChild(wrap);
  }

  function toggle(g, o) {
    var at = g.picked.indexOf(o.id);
    if (at >= 0) g.picked.splice(at, 1);
    else if (g.multi) g.picked.push(o.id);
    else g.picked = [o.id];
    update();
  }

  function buildBar() {
    var b = el('div', 'sdd-picks-bar');
    b.setAttribute('role', 'region');
    b.setAttribute('aria-label', 'Your picks');
    var sum = el('div', 'sdd-picks-summary');
    var ta = el('textarea', 'sdd-picks-text');
    ta.readOnly = true;
    ta.rows = 5;
    ta.setAttribute('aria-label', 'The prompt to paste back to the agent');
    var row = el('div', 'sdd-picks-actions');
    var copy = el('button', 'sdd-picks-copy', 'Copy');
    var clear = el('button', 'sdd-picks-clear', 'Clear');
    copy.type = clear.type = 'button';
    var hint = el('span', 'sdd-picks-hint', '');
    copy.addEventListener('click', function () { doCopy(ta, copy); });
    clear.addEventListener('click', function () { doClear(clear); });
    row.appendChild(copy); row.appendChild(clear); row.appendChild(hint);
    b.appendChild(sum); b.appendChild(ta); b.appendChild(row);
    document.body.appendChild(b);
    return { root: b, summary: sum, text: ta, copy: copy, clear: clear, hint: hint };
  }

  // ---- the prompt ----------------------------------------------------------------------

  function pageRef() {
    var p = decodeURIComponent(location.pathname);
    if (p.indexOf('/view/') === 0) return p.slice(6);
    var parts = p.split('/').filter(Boolean);
    return parts.slice(-2).join('/') || p;
  }

  function prompt() {
    var title = clean(document.title);
    var lines = ['Picks from ' + pageRef() + (title ? ' (' + title + ')' : ''), ''];
    var empty = [];
    groups.forEach(function (g) {
      if (!g.picked.length) { empty.push(g.label); return; }
      lines.push(g.label);
      g.picked.forEach(function (id) {
        var o = byId(g, id);
        lines.push('  -> ' + o.label + '   [' + id + ']');
      });
      var n = clean(g.noteText).slice(0, NOTE_MAX);
      if (n) lines.push('     note: ' + n);
      lines.push('');
    });
    if (empty.length) {
      lines.push('Not picked yet:');
      empty.forEach(function (l) { lines.push('  ' + l); });
    }
    return lines.join('\n').replace(/\n+$/, '') + '\n';
  }

  function byId(g, id) {
    for (var i = 0; i < g.options.length; i++) if (g.options[i].id === id) return g.options[i];
    return { label: id };
  }

  function update() {
    groups.forEach(function (g) {
      g.options.forEach(function (o) {
        var on = g.picked.indexOf(o.id) >= 0;
        o.el.setAttribute('data-picked', on ? 'true' : 'false');
        o.btn.textContent = on ? 'Picked' : 'Pick';
        o.btn.setAttribute('aria-pressed', on ? 'true' : 'false');
      });
    });
    var done = groups.filter(function (g) { return g.picked.length; });
    bar.root.setAttribute('data-empty', done.length ? 'false' : 'true');
    // Measured rather than fixed: the bar is one line until something is picked, and a page
    // that reserves room for the tall version has a hole in it the whole time it is read.
    document.body.style.paddingBottom = (bar.root.offsetHeight + 24) + 'px';
    bar.summary.textContent = done.length
      ? done.length + ' of ' + groups.length + ' picked: ' + done.map(function (g) {
          return g.picked.map(function (id) { return byId(g, id).label; }).join(' + ');
        }).join('; ')
      : 'Pick an option to build a prompt to paste back.';
    bar.text.value = done.length ? prompt() : '';
    save();
  }

  // ---- copy, clear, memory -------------------------------------------------------------

  /* navigator.clipboard needs a secure context, and the dashboard is plain http on a LAN
     address, which is not one. Only localhost would be. So the deprecated execCommand path
     is the one that actually runs in the setup this exists for, and the textarea stays
     selectable behind both. */
  function doCopy(ta, btn) {
    if (!ta.value) return;
    var done = function () { flash(btn, 'Copied'); };
    var fall = function () { flash(btn, legacy(ta) ? 'Copied' : 'Select and copy'); };
    if (navigator.clipboard && navigator.clipboard.writeText) {
      try { navigator.clipboard.writeText(ta.value).then(done, fall); return; } catch (e) { /* fall */ }
    }
    fall();
  }

  function legacy(ta) {
    try {
      ta.focus();
      ta.setSelectionRange(0, ta.value.length);
      return document.execCommand('copy');
    } catch (e) { return false; }
  }

  function flash(btn, msg) {
    var was = btn.textContent;
    btn.textContent = msg;
    setTimeout(function () { btn.textContent = was; }, 1600);
  }

  // Two clicks rather than a confirm(): a modal blocks the page, and losing six picks to one
  // stray click is worth a second of friction.
  function doClear(btn) {
    if (btn.getAttribute('data-arm') === 'yes') {
      groups.forEach(function (g) {
        g.picked = []; g.noteText = '';
        if (g.noteEl) { g.noteEl.value = ''; g.noteEl.style.height = 'auto'; }
      });
      disarm(btn);
      update();
      return;
    }
    btn.setAttribute('data-arm', 'yes');
    btn.textContent = 'Clear, sure?';
    btn._t = setTimeout(function () { disarm(btn); }, 3000);
  }

  function disarm(btn) {
    clearTimeout(btn._t);
    btn.removeAttribute('data-arm');
    btn.textContent = 'Clear';
  }

  /* The live-reload helper reloads the page whenever the agent republishes anything, so
     without this a half-finished review is thrown away mid-read. Storage throws in a private
     window, so every access is guarded and the page is correct without it. */
  function save() {
    var state = {};
    groups.forEach(function (g) {
      if (g.picked.length || clean(g.noteText)) state[g.id] = { p: g.picked, n: g.noteText };
    });
    try {
      if (Object.keys(state).length) localStorage.setItem(STORE, JSON.stringify(state));
      else localStorage.removeItem(STORE);
    } catch (e) { /* nothing to do */ }
  }

  function restore() {
    var state;
    try { state = JSON.parse(localStorage.getItem(STORE) || '{}'); } catch (e) { return; }
    if (!state || typeof state !== 'object') return;
    groups.forEach(function (g) {
      var s = state[g.id];
      if (!s) return;
      // Ids the page no longer offers are dropped: a mockup is edited between reads.
      g.picked = (s.p || []).filter(function (id) { return byId(g, id).el; });
      if (!g.multi) g.picked = g.picked.slice(0, 1);
      g.noteText = typeof s.n === 'string' ? s.n.slice(0, NOTE_MAX) : '';
      if (g.noteEl) g.noteEl.value = g.noteText;
    });
  }

  // ---- styles --------------------------------------------------------------------------

  /* The page's own background decides the fallback palette, not prefers-color-scheme. A mockup
     that sets no background renders on the UA's white even where the OS prefers dark, and a
     control strip that went dark underneath it would be the only dark thing on the page. Inside
     the dashboard frame none of this is reached: every colour below reads the frame's token
     first and only falls back when it is absent. */
  function dark() {
    var p = bgOf(document.body) || bgOf(document.documentElement);
    if (!p) return false;
    return (0.2126 * p[0] + 0.7152 * p[1] + 0.0722 * p[2]) / 255 < 0.5;
  }

  function bgOf(node) {
    var m = String((window.getComputedStyle(node) || {}).backgroundColor).match(/rgba?\(([^)]+)\)/);
    if (!m) return null;
    var p = m[1].split(',').map(parseFloat);
    return (p.length > 3 && p[3] === 0) ? null : p;   // fully transparent is "not set"
  }

  function style() {
    var css = [
      ':root{--sdd-p-accent:#c0501a;--sdd-p-accent-bg:rgba(192,80,26,.10);--sdd-p-fg:#1f2022;',
      '--sdd-p-muted:#625e58;--sdd-p-bar:#fbfaf8;--sdd-p-surface:#fff;--sdd-p-border:#d7d3cc}',
      ':root.sdd-picks-dark{--sdd-p-accent:#f07a3a;',
      '--sdd-p-accent-bg:rgba(240,122,58,.12);--sdd-p-fg:#e9e6e1;--sdd-p-muted:#9d9892;',
      '--sdd-p-bar:#1b1c1f;--sdd-p-surface:#1e2023;--sdd-p-border:#33363b}',
      // min-height keeps the button clear of the row above and below when an option is a bare
      // one-line element, which the minimal markup in the skill is.
      '.sdd-pickable{position:relative;padding-right:6.75rem;min-height:2.9rem;',
      'padding-top:.35rem;padding-bottom:.35rem}',
      '.sdd-pickable[data-picked=true]{background:var(--ember-bg,var(--sdd-p-accent-bg));',
      'box-shadow:inset 3px 0 0 var(--ember,var(--sdd-p-accent))}',
      '.sdd-pick-btn{position:absolute;right:.9rem;top:50%;transform:translateY(-50%);',
      'font:inherit;font-size:.85em;padding:.35em 1.1em;border-radius:999px;cursor:pointer;',
      'background:transparent;color:var(--fg,var(--sdd-p-fg));',
      'border:1px solid var(--border,var(--sdd-p-border))}',
      '.sdd-pick-btn:hover{border-color:var(--ember,var(--sdd-p-accent))}',
      '.sdd-pickable[data-picked=true] .sdd-pick-btn{background:var(--ember,var(--sdd-p-accent));',
      'border-color:var(--ember,var(--sdd-p-accent));color:var(--bg,#fff);font-weight:600}',
      '.sdd-pick-note{padding:.4rem .9rem .8rem}',
      '.sdd-pick-note textarea{width:100%;min-height:2.2em;max-height:9rem;resize:vertical;',
      'box-sizing:border-box;overflow-wrap:anywhere;font:inherit;font-size:.9em;',
      'padding:.45em .6em;border-radius:6px;overflow:auto;',
      'color:var(--fg,var(--sdd-p-fg));background:var(--surface,var(--sdd-p-surface));',
      'border:1px solid var(--border,var(--sdd-p-border))}',
      '.sdd-picks-bar{position:fixed;left:0;right:0;bottom:0;z-index:40;padding:.7rem 1rem;',
      'box-sizing:border-box;',
      'display:flex;flex-direction:column;gap:.5rem;max-height:52vh;overflow:auto;',
      'background:var(--bar,var(--sdd-p-bar));color:var(--fg,var(--sdd-p-fg));',
      'border-top:1px solid var(--border,var(--sdd-p-border));',
      'font:14px/1.5 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}',
      '.sdd-picks-bar[data-empty=true] .sdd-picks-text,',
      '.sdd-picks-bar[data-empty=true] .sdd-picks-actions{display:none}',
      '.sdd-picks-summary{color:var(--muted,var(--sdd-p-muted))}',
      '.sdd-picks-bar[data-empty=false] .sdd-picks-summary{color:var(--fg,var(--sdd-p-fg))}',
      '.sdd-picks-text{width:100%;resize:vertical;box-sizing:border-box;overflow-wrap:anywhere;',
      'font:12px/1.45 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;',
      'padding:.5em .6em;border-radius:6px;',
      'color:var(--fg,var(--sdd-p-fg));background:var(--surface,var(--sdd-p-surface));',
      'border:1px solid var(--border,var(--sdd-p-border))}',
      '.sdd-picks-actions{display:flex;gap:.5rem;align-items:center}',
      '.sdd-picks-actions button{font:inherit;padding:.4em 1.1em;border-radius:6px;',
      'cursor:pointer;color:var(--fg,var(--sdd-p-fg));',
      'background:var(--surface,var(--sdd-p-surface));',
      'border:1px solid var(--border,var(--sdd-p-border))}',
      '.sdd-picks-copy{font-weight:600}',
      '.sdd-picks-actions button[data-arm=yes]{border-color:var(--bad,#b1281f);',
      'color:var(--bad,#b1281f)}',
      '@media(max-width:600px){.sdd-pickable{padding-right:.9rem;padding-bottom:3rem}',
      '.sdd-pick-btn{top:auto;bottom:.8rem;right:.9rem;transform:none}}'
    ].join('');
    var s = el('style');
    s.appendChild(document.createTextNode(css));
    document.head.appendChild(s);
    if (dark()) document.documentElement.classList.add('sdd-picks-dark');
  }
})();

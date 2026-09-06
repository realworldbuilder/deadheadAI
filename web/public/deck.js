/* The tape deck. One <audio> pair that outlives page loads: in-site links are
   fetched and swapped into #main, so the tape keeps rolling while you read.
   Pages stay plain HTML; the deck finds its buttons by data- attributes:
   a[data-spin=id] (spin a tape), a.pl[data-spin][data-from=i] (play from a
   tune), [data-from][data-to] (just the run), a[data-mix=id] (a mix tape).
   Saved state only ever cues; nothing autoplays. */
(function () {
  var KEY = 'nethead.deck.v1', D = document, $ = function (s, r) { return (r || D).querySelector(s); };
  var deck = $('#deck'); if (!deck) return;
  var el = function (n) { return $('[data-deck="' + n + '"]', deck); };
  var ui = { play: el('toggle'), link: el('link'), sub: el('sub'), pos: el('pos'), dur: el('dur'), seek: el('seek'), msg: el('msg'), sleep: el('sleep') };
  var A = [mk(), mk()], on = 0, S = null, seeking = false, lastSave = 0, sleepT = null, sleepEnd = false;
  function mk() { var a = new Audio(); a.preload = 'auto'; a.addEventListener('ended', ended); a.addEventListener('timeupdate', tick); a.addEventListener('loadedmetadata', meta); a.addEventListener('play', playing); a.addEventListener('pause', playing); a.addEventListener('error', function () { if (this === A[on]) msg("archive.org didn't answer. Hit play to try again."); }); return a; }
  function cur() { return S && S.q.tracks[S.i]; }
  function url(i) { return S.q.tracks[i].url; }
  function fmt(s) { if (!(s > 0)) return '--:--'; s = Math.round(s); var h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), x = s % 60; return (h ? h + ':' + (m < 10 ? '0' : '') : '') + m + ':' + (x < 10 ? '0' : '') + x; }
  function msg(t) { ui.msg.textContent = t || ''; }
  function save(force) { if (!S) return; var now = Date.now(); if (!force && now - lastSave < 5000) return; lastSave = now; S.pos = A[on].currentTime > 3 ? A[on].currentTime : 0; try { localStorage.setItem(KEY, JSON.stringify(S)); } catch (e) {} }
  function load() { try { return JSON.parse(localStorage.getItem(KEY)); } catch (e) { return null; } }

  function spin(src, from, to) {
    msg('Cueing up the tape…');
    fetch(src, { headers: { accept: 'application/json' } }).then(function (r) { return r.ok ? r.json() : Promise.reject(r); }).then(function (j) {
      var tracks = j.tracks.slice(from || 0, to != null ? to + 1 : undefined);
      if (!tracks.length) return msg('No streamable tracks on this tape.');
      S = { q: { src: src, page: j.page, tracks: tracks }, i: 0, pos: 0 };
      deck.hidden = false; cue(0, true);
    }).catch(function () { msg("archive.org didn't answer. Try another tape."); });
  }
  function cue(i, autoplay) {
    S.i = i; var a = A[on]; a.src = url(i); a.load(); now(); prep(i + 1); save(true); msg('');
    if (autoplay) go(a);
  }
  function go(a) { var p = a.play(); if (p && p.catch) p.catch(function (e) { msg(e && e.name === 'NotAllowedError' ? 'Hit play.' : "archive.org didn't answer. Hit play to try again."); }); }
  function prep(j) { var b = A[1 - on]; if (S.q.tracks[j]) { b.src = url(j); b.load(); } else b.removeAttribute('src'); }
  function ended(e) {
    if (e.target !== A[on]) return;
    if (sleepEnd) { sleepEnd = false; ui.sleep.value = '0'; msg("Sleep timer. Tape's still cued up."); if (S.q.tracks[S.i + 1]) { S.i++; on = 1 - on; A[1 - on].removeAttribute('src'); now(); prep(S.i + 1); save(true); } return; }
    if (!S.q.tracks[S.i + 1]) { msg('End of the tape.'); S.i = 0; cue(0, false); return; }
    S.i++; on = 1 - on; go(A[on]); A[1 - on].removeAttribute('src'); now(); prep(S.i + 1); save(true);
  }
  function now() {
    var t = cur(); if (!t) return;
    ui.link.textContent = t.title; ui.link.href = t.page; ui.sub.textContent = t.pretty + (t.venue ? ' · ' + t.venue : '');
    ui.dur.textContent = fmt(t.seconds); ui.pos.textContent = '0:00'; ui.seek.value = 0; mark(); media(t); spinning(t);
  }
  function mark() {
    var t = cur(); D.querySelectorAll('[data-track][aria-current]').forEach(function (li) { li.removeAttribute('aria-current'); });
    if (!t) return; var host = D.querySelector('[data-spin="' + t.identifier + '"] [data-track="' + t.i + '"]');
    if (host) host.setAttribute('aria-current', 'true');
  }
  function meta() { if (this !== A[on]) return; ui.dur.textContent = fmt(this.duration || (cur() || {}).seconds); if (S && S.pos > 0 && this.currentTime < 1) { this.currentTime = S.pos; S.pos = 0; } }
  function tick() {
    if (this !== A[on] || seeking) return; var d = this.duration || (cur() || {}).seconds || 0;
    ui.pos.textContent = fmt(this.currentTime); if (d) ui.seek.value = Math.round(this.currentTime / d * 1000); save();
    if ('mediaSession' in navigator && d) try { navigator.mediaSession.setPositionState({ duration: d, position: Math.min(this.currentTime, d), playbackRate: 1 }); } catch (e) {}
  }
  function playing() { var p = A[on].paused; ui.play.textContent = p ? '▶' : '❚❚'; ui.play.setAttribute('aria-label', p ? 'Play' : 'Pause'); }
  function toggle() { var a = A[on]; if (!S) return; if (a.paused) { msg(''); if (!a.src) a.src = url(S.i); go(a); } else { a.pause(); save(true); } }
  function step(n) { if (!S) return; var i = S.i + n; if (n < 0 && A[on].currentTime > 3) { A[on].currentTime = 0; return; } if (i < 0 || !S.q.tracks[i]) return; var was = !A[on].paused; A[on].pause(); cue(i, was); }
  function skip(s) { var a = A[on]; if (!a.src) return; a.currentTime = Math.max(0, Math.min((a.duration || 1e9), a.currentTime + s)); }
  function eject() { A.forEach(function (a) { a.pause(); a.removeAttribute('src'); }); S = null; deck.hidden = true; try { localStorage.removeItem(KEY); } catch (e) {} mark(); spinning(null); }
  function media(t) {
    if (!('mediaSession' in navigator)) return;
    try {
      navigator.mediaSession.metadata = new MediaMetadata({ title: t.title, artist: 'Grateful Dead', album: t.pretty + (t.venue ? ' · ' + t.venue : ''), artwork: [{ src: '/icon.png', sizes: '480x480', type: 'image/png' }] });
      var h = { play: toggle, pause: toggle, previoustrack: function () { step(-1); }, nexttrack: function () { step(1); }, seekbackward: function () { skip(-15); }, seekforward: function () { skip(15); }, seekto: function (d) { if (d.seekTime != null) A[on].currentTime = d.seekTime; } };
      for (var k in h) try { navigator.mediaSession.setActionHandler(k, h[k]); } catch (e) {}
    } catch (e) {}
  }
  function spinning(t) {
    if (!D.body.dataset.head) return;
    var body = t ? { identifier: t.identifier, showId: t.date ? t.date : null, trackTitle: t.title } : { stopped: true };
    try { fetch('/deck/spin', { method: 'POST', keepalive: true, headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) }).catch(function () {}); } catch (e) {}
  }
  function sleep(v) {
    clearTimeout(sleepT); sleepEnd = false;
    if (v === 'end') { sleepEnd = true; return msg('Deck stops after this tune.'); }
    var m = parseInt(v, 10); if (!m) return msg('');
    msg('Deck stops in ' + m + ' min.');
    sleepT = setTimeout(function () {
      var a = A[on], canFade = true; try { a.volume = 0.5; canFade = a.volume !== 1; a.volume = 1; } catch (e) { canFade = false; }
      if (!canFade) { a.pause(); ui.sleep.value = '0'; return msg("Sleep timer. Tape's still cued up."); }
      var n = 6, f = setInterval(function () { a.volume = Math.max(0, n / 6); if (--n < 0) { clearInterval(f); a.pause(); a.volume = 1; ui.sleep.value = '0'; msg("Sleep timer. Tape's still cued up."); } }, 300);
    }, m * 60000);
  }

  /* Turbo: same-origin links and forms swap #main so the tape keeps playing. */
  function swappable(a) { return a && a.href && !a.hasAttribute('download') && !a.target && !a.hasAttribute('data-full') && a.origin === location.origin; }
  function visit(url, opts, push) {
    D.documentElement.setAttribute('data-loading', '');
    opts = opts || {}; opts.headers = Object.assign({ 'x-nethead-swap': '1' }, opts.headers || {}); opts.redirect = 'follow';
    return fetch(url, opts).then(function (r) {
      var type = r.headers.get('content-type') || '';
      if (r.status >= 500 || type.indexOf('text/html') < 0) throw r;
      return r.text().then(function (html) { swap(html, r.url, push); });
    }).catch(function () { if (opts.method === 'POST') throw 0; location.href = url; }).then(function () { D.documentElement.removeAttribute('data-loading'); }, function () { D.documentElement.removeAttribute('data-loading'); });
  }
  function swap(html, url, push) {
    var doc = new DOMParser().parseFromString(html, 'text/html');
    ['main', 'crumb'].forEach(function (id) { var a = D.getElementById(id), b = doc.getElementById(id); if (a && b) a.replaceWith(b); });
    var na = $('nav.bar'), nb = $('nav.bar', doc); if (na && nb) na.replaceWith(nb);
    D.title = doc.title; D.body.dataset.page = doc.body.dataset.page || '';
    if (push) history.pushState({ y: 0 }, '', url);
    var hash = url.indexOf('#') > -1 ? url.slice(url.indexOf('#')) : '';
    var target = hash && D.querySelector(hash); if (target) target.scrollIntoView(); else window.scrollTo(0, 0);
    var m = D.getElementById('main'); if (m) m.focus({ preventScroll: true });
    mark();
  }
  D.addEventListener('click', function (e) {
    if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
    var a = e.target.closest('a'); if (!a) return;
    if (a.hasAttribute('data-spin')) { e.preventDefault(); var f = a.getAttribute('data-from'), t = a.getAttribute('data-to'); return spin('/deck/tapes/' + encodeURIComponent(a.getAttribute('data-spin')), f ? +f : 0, t ? +t : null); }
    if (a.hasAttribute('data-mix')) { e.preventDefault(); return spin('/deck/mixtapes/' + encodeURIComponent(a.getAttribute('data-mix')), 0, null); }
    if (!swappable(a) || (a.getAttribute('href') || '').charAt(0) === '#') return;
    e.preventDefault(); visit(a.href, {}, true);
  });
  D.addEventListener('submit', function (e) {
    var f = e.target; if (e.defaultPrevented || f.hasAttribute('data-full') || new URL(f.action, location.href).origin !== location.origin) return;
    e.preventDefault(); var fd = new FormData(f), m = (f.method || 'get').toUpperCase();
    if (m === 'GET') { var u = new URL(f.action, location.href); u.search = new URLSearchParams(fd).toString(); visit(u.href, {}, true); }
    else visit(f.action, { method: 'POST', body: new URLSearchParams(fd), headers: { 'content-type': 'application/x-www-form-urlencoded' } }, true).catch(function () { f.removeAttribute('data-x'); f.setAttribute('data-full', ''); f.submit(); });
  });
  window.addEventListener('popstate', function () { visit(location.href, {}, false); });
  history.scrollRestoration = 'manual';

  deck.addEventListener('click', function (e) {
    var b = e.target.closest('[data-deck]'); if (!b) return; var k = b.getAttribute('data-deck');
    if (k === 'toggle') toggle(); else if (k === 'prev') step(-1); else if (k === 'next') step(1); else if (k === 'back') skip(-15); else if (k === 'fwd') skip(15); else if (k === 'eject') eject();
  });
  ui.seek.addEventListener('input', function () { seeking = true; var d = A[on].duration || (cur() || {}).seconds || 0; ui.pos.textContent = fmt(this.value / 1000 * d); });
  ui.seek.addEventListener('change', function () { var d = A[on].duration || (cur() || {}).seconds || 0; if (d) A[on].currentTime = this.value / 1000 * d; seeking = false; });
  ui.sleep.addEventListener('change', function () { sleep(this.value); });
  D.addEventListener('keydown', function (e) {
    if (!S || e.target.closest('input,textarea,select,button,[contenteditable]')) return;
    if (e.key === ' ') { e.preventDefault(); toggle(); } else if (e.key === 'ArrowLeft') { e.shiftKey ? step(-1) : skip(-15); } else if (e.key === 'ArrowRight') { e.shiftKey ? step(1) : skip(15); }
  });
  window.addEventListener('pagehide', function () { save(true); });
  D.addEventListener('visibilitychange', function () { if (D.hidden) save(true); });

  var saved = load();
  if (saved && saved.q && saved.q.tracks && saved.q.tracks[saved.i]) {
    S = saved; deck.hidden = false; var a = A[on]; a.src = url(S.i); a.preload = 'metadata'; a.load(); now(); prep(S.i + 1);
    ui.play.setAttribute('aria-label', 'Resume'); msg("Tape's still cued up.");
  }
})();

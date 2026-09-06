/* Passkeys: the four ceremonies (get on the bus, sign in, add a passkey,
   get back on with the recovery code). Options come from the server as
   JSON; the browser does the rest. No bundler, so base64url by hand. */
(function () {
  var D = document;
  function b2a(s) { s = s.replace(/-/g, '+').replace(/_/g, '/'); while (s.length % 4) s += '='; var bin = atob(s), out = new Uint8Array(bin.length); for (var i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i); return out.buffer; }
  function a2b(buf) { var s = '', b = new Uint8Array(buf); for (var i = 0; i < b.length; i++) s += String.fromCharCode(b[i]); return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, ''); }
  function creation(o) { o = JSON.parse(JSON.stringify(o)); o.challenge = b2a(o.challenge); o.user.id = b2a(o.user.id); (o.excludeCredentials || []).forEach(function (c) { c.id = b2a(c.id); }); return o; }
  function request(o) { o = JSON.parse(JSON.stringify(o)); o.challenge = b2a(o.challenge); (o.allowCredentials || []).forEach(function (c) { c.id = b2a(c.id); }); return o; }
  function toJSON(cred) {
    if (cred.toJSON) return cred.toJSON();
    var r = cred.response, out = { id: cred.id, rawId: a2b(cred.rawId), type: cred.type, clientExtensionResults: cred.getClientExtensionResults ? cred.getClientExtensionResults() : {}, authenticatorAttachment: cred.authenticatorAttachment, response: { clientDataJSON: a2b(r.clientDataJSON) } };
    if (r.attestationObject) { out.response.attestationObject = a2b(r.attestationObject); out.response.transports = r.getTransports ? r.getTransports() : []; }
    else { out.response.authenticatorData = a2b(r.authenticatorData); out.response.signature = a2b(r.signature); if (r.userHandle) out.response.userHandle = a2b(r.userHandle); }
    return out;
  }
  function post(url, body) { return fetch(url, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) }).then(function (r) { return r.json().then(function (j) { if (!r.ok) throw new Error(j.error || 'Bummer.'); return j; }); }); }
  function fail(form, msg) { var host = form || D.querySelector('main'); var e = host.querySelector('[data-error]'); if (!e) { e = D.createElement('p'); e.className = 'err'; e.setAttribute('role', 'alert'); e.setAttribute('data-error', ''); host.prepend(e); } e.hidden = false; e.textContent = msg; e.scrollIntoView({ block: 'nearest' }); }
  function busy(b, on) { if (b) { b.disabled = on; b.textContent = on ? 'Waiting on your passkey…' : b.getAttribute('data-label') || b.textContent; } }
  var canDo = !!(window.PublicKeyCredential && navigator.credentials);
  if (!canDo) { D.querySelectorAll('[data-webauthn]').forEach(function (b) { b.disabled = true; }); fail(null, "This browser can't do passkeys. Safari 16 or newer, Chrome, or Firefox can. A security key works too."); return; }
  D.querySelectorAll('[data-webauthn]').forEach(function (b) { b.setAttribute('data-label', b.textContent); });

  function signup(form, btn) {
    var body = { node: form.node.value, name: form.name.value, first_show: form.first_show.value };
    busy(btn, true);
    post('/bus/options', body).then(function (j) {
      return navigator.credentials.create({ publicKey: creation(j.options) }).then(function (cred) {
        return post('/bus/verify', { ceremonyId: j.ceremonyId, credential: toJSON(cred) });
      });
    }).then(function (j) {
      form.hidden = true; var w = D.getElementById('welcome'); w.querySelector('[data-code]').textContent = j.recoveryCode; w.hidden = false; w.scrollIntoView();
      D.querySelector('h1').textContent = j.handle + ', welcome aboard.';
    }).catch(function (e) { busy(btn, false); fail(form, e.name === 'NotAllowedError' ? "That passkey didn't take. Try again." : e.message); });
  }
  function signin(form, btn) {
    var handle = form.handle.value.trim();
    busy(btn, true);
    post('/signin/options', { handle: handle }).then(function (j) {
      return navigator.credentials.get({ publicKey: request(j.options) }).then(function (cred) {
        return post('/signin/verify', { ceremonyId: j.ceremonyId, credential: toJSON(cred), next: form.next.value });
      });
    }).then(function (j) { location.href = j.next || '/me'; })
      .catch(function (e) { busy(btn, false); fail(form, e.name === 'NotAllowedError' ? "That passkey didn't take. Try again, or use your recovery code." : e.message); });
  }
  function add(btn) {
    busy(btn, true);
    post('/me/passkeys/options', {}).then(function (j) {
      return navigator.credentials.create({ publicKey: creation(j.options) }).then(function (cred) {
        return post('/me/passkeys/verify', { ceremonyId: j.ceremonyId, credential: toJSON(cred) });
      });
    }).then(function () { location.href = '/me/passkeys?ok=added'; })
      .catch(function (e) { busy(btn, false); fail(null, e.name === 'NotAllowedError' ? "That passkey didn't take. Try again." : e.message); });
  }
  function recover(btn) {
    var opts = JSON.parse(D.getElementById('ceremony-options').textContent);
    busy(btn, true);
    navigator.credentials.create({ publicKey: creation(opts) }).then(function (cred) {
      return post('/recover/verify', { ceremonyId: btn.getAttribute('data-ceremony'), credential: toJSON(cred) });
    }).then(function (j) {
      btn.closest('.btns').hidden = true; var w = D.getElementById('welcome'); w.querySelector('[data-code]').textContent = j.recoveryCode; w.hidden = false;
    }).catch(function (e) { busy(btn, false); fail(null, e.name === 'NotAllowedError' ? "That passkey didn't take. Reload and try again." : e.message); });
  }

  D.addEventListener('submit', function (e) {
    var f = e.target; if (f.id === 'bus') { e.preventDefault(); signup(f, f.querySelector('[data-webauthn]')); }
    else if (f.id === 'signin') { e.preventDefault(); signin(f, f.querySelector('[data-webauthn]')); }
  });
  D.addEventListener('click', function (e) {
    var b = e.target.closest('[data-webauthn]'); if (!b || b.type === 'submit') return;
    var k = b.getAttribute('data-webauthn'); if (k === 'add') add(b); else if (k === 'recover') recover(b);
  });
  // Conditional UI: let the browser offer the passkey in the handle box.
  var si = D.getElementById('signin');
  if (si && PublicKeyCredential.isConditionalMediationAvailable) {
    PublicKeyCredential.isConditionalMediationAvailable().then(function (ok) {
      if (!ok) return;
      post('/signin/options', {}).then(function (j) {
        return navigator.credentials.get({ publicKey: request(j.options), mediation: 'conditional' }).then(function (cred) {
          return post('/signin/verify', { ceremonyId: j.ceremonyId, credential: toJSON(cred), next: si.next.value });
        }).then(function (r) { location.href = r.next || '/me'; });
      }).catch(function () {});
    });
  }
})();

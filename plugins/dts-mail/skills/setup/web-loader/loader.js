// DTS Mail web loader. This site holds no app code: it asks its own mail server which web build matches the server's
// API version (GET <apiBaseUrl>/version → web.base) and starts that build from the public release channel. A server
// that updates itself therefore brings its web client along, and the two never drift apart.
// config.json: { "apiBaseUrl": "https://<function-app>.azurewebsites.net/api" } (written by /dts-mail:setup).
(function () {
  'use strict';
  var root = document.getElementById('root');
  var retryTimer = null;

  function show(title, detail, opts) {
    opts = opts || {};
    clearTimeout(retryTimer);
    var card = document.createElement('div');
    card.className = 'dts-boot-card';
    var img = document.createElement('img');
    img.src = '/icon.svg';
    img.alt = '';
    var h = document.createElement('h1');
    h.textContent = title;
    var p = document.createElement('p');
    p.textContent = detail;
    card.append(img, h, p);
    if (opts.retry) {
      var b = document.createElement('button');
      b.type = 'button';
      b.textContent = 'Try again';
      b.onclick = start;
      card.append(b);
    }
    var wrap = document.createElement('div');
    wrap.className = 'dts-boot';
    wrap.append(card, credit());
    root.replaceChildren(wrap);
    if (opts.autoRetrySeconds) retryTimer = setTimeout(start, opts.autoRetrySeconds * 1000);
  }

  // Shown on every loader screen; the app carries its own once it starts.
  function credit() {
    var a = document.createElement('a');
    a.className = 'dts-credit';
    a.href = 'https://chuckgiddens.com';
    a.target = '_blank';
    a.rel = 'noopener noreferrer';
    a.textContent = 'Powered by DTS LLS';
    return a;
  }

  function spinner() {
    var wrap = document.createElement('div');
    wrap.className = 'dts-boot';
    var s = document.createElement('div');
    s.className = 'dts-spinner';
    s.setAttribute('aria-label', 'Loading DTS Mail');
    wrap.append(s, credit());
    root.replaceChildren(wrap);
  }

  function getJson(url) {
    return fetch(url, { cache: 'no-store' }).then(function (r) {
      if (!r.ok) throw new Error('HTTP ' + r.status);
      return r.json();
    });
  }

  // The release URL comes from the site's own server; still, only load scripts over https (or plain http when this
  // page itself is served from localhost, for testing).
  function allowedBase(url) {
    try {
      var u = new URL(url);
      var local = location.hostname === 'localhost' || location.hostname === '127.0.0.1';
      return u.protocol === 'https:' || (local && u.protocol === 'http:');
    } catch (e) {
      return false;
    }
  }

  function inject(base, html) {
    var doc = new DOMParser().parseFromString(html, 'text/html');
    var abs = function (href) { return new URL(href, base).toString(); };
    doc.querySelectorAll('link[rel="stylesheet"], link[rel="modulepreload"]').forEach(function (el) {
      var link = document.createElement('link');
      link.rel = el.getAttribute('rel');
      link.href = abs(el.getAttribute('href'));
      link.crossOrigin = 'anonymous';
      document.head.append(link);
    });
    var scripts = doc.querySelectorAll('script[type="module"][src]');
    if (!scripts.length) throw new Error('the web build has no entry script');
    scripts.forEach(function (el) {
      var s = document.createElement('script');
      s.type = 'module';
      s.crossOrigin = 'anonymous';
      s.src = abs(el.getAttribute('src'));
      s.onerror = function () {
        show('DTS Mail could not start', "The app's files didn't load. Check your connection and try again.", { retry: true });
      };
      document.body.append(s);
    });
  }

  function start() {
    spinner();
    getJson('/config.json')
      .catch(function () { return null; })
      .then(function (config) {
        var api = config && typeof config.apiBaseUrl === 'string' ? config.apiBaseUrl.trim().replace(/\/+$/, '') : '';
        if (!/^https?:\/\//.test(api) || api.indexOf('<') >= 0) {
          show('This site isn’t set up yet', 'Its config.json doesn’t name a mail server. Run /dts-mail:manage in Claude Code to repair it.');
          return;
        }
        return getJson(api + '/version').then(
          function (v) {
            var base = v && v.web && typeof v.web.base === 'string' ? v.web.base : '';
            if (!base) {
              show('Your mail server is finishing an update', 'This page will try again in a minute.', { retry: true, autoRetrySeconds: 60 });
              return;
            }
            if (!allowedBase(base)) {
              show('DTS Mail could not start', 'The mail server named an app location this page won’t load from.', { retry: true });
              return;
            }
            if (base.slice(-1) !== '/') base += '/';
            // Read by @dts/core before the app starts: sign-in goes to this site's own server.
            window.__DTS_CONFIG__ = { apiBaseUrl: api };
            return fetch(base + 'index.html').then(function (r) {
              if (!r.ok) throw new Error('HTTP ' + r.status);
              return r.text();
            }).then(function (html) { inject(base, html); });
          },
          function () {
            show('Can’t reach your mail server', 'It may be starting up after a quiet spell, which takes a few seconds. If this keeps happening, check that your Azure subscription is active.', { retry: true, autoRetrySeconds: 20 });
          },
        );
      })
      .catch(function () {
        show('DTS Mail could not start', "The app's files didn't load. Check your connection and try again.", { retry: true });
      });
  }

  start();
})();

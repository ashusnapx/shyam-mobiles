// The same rules as the app (lib/core/links.dart): only a product slug, an offer id and a code get through.
// Served for /open?p=&o=&ref= and for /p/<slug> (firebase.json rewrites it here).
(function () {
  var q = new URLSearchParams(location.search);
  var path = location.pathname.match(/^\/p\/([a-z0-9-]{1,160})\/?$/);
  if (path && !q.get('p')) q.set('p', path[1]);
  var keep = { p: /^[a-z0-9-]{1,160}$/, o: /^[0-9a-f-]{36}$/, ref: /^[A-Z0-9]{6,10}$/ };
  var link = new URLSearchParams();
  Object.keys(keep).forEach(function (k) {
    var v = (q.get(k) || '').trim();
    if (k === 'ref') v = v.toUpperCase();
    if (keep[k].test(v)) link.set(k, v);
  });
  var query = link.toString();
  // Play hands `referrer` back to the app on its first launch, so a new install still lands on the page and code
  var play = 'https://play.google.com/store/apps/details?id=com.shyammobiles.app' +
    (query ? '&referrer=' + encodeURIComponent(query) : '');
  document.getElementById('play').href = play;
  document.getElementById('open').href = 'intent://open' + (query ? '?' + query : '') +
    '#Intent;scheme=shyammobiles;package=com.shyammobiles.app;S.browser_fallback_url=' +
    encodeURIComponent(play) + ';end';
  if (link.get('p')) document.getElementById('title').textContent = 'Open this product in the app';
  if (link.get('o')) document.getElementById('title').textContent = 'Open this offer in the app';
  if (link.get('ref')) {
    document.getElementById('code').textContent = link.get('ref');
    document.getElementById('code-note').hidden = false;
  }
})();

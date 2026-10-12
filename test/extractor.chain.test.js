'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const X = require('../js/extractor.js');

const fx = (n) => fs.readFileSync(path.join(__dirname, 'fixtures', n), 'utf8');
const HOME = fx('home-snippet.html');
const PLAYER = { visionos: fx('player-visionos.json'), ios: fx('player-ios.json'), android_vr: fx('player-android_vr.json') };
const LOGIN = JSON.stringify({ playabilityStatus: { status: 'LOGIN_REQUIRED', reason: 'Melde dich an' } });
const AGE = JSON.stringify({ playabilityStatus: { status: 'AGE_CHECK_REQUIRED', reason: '' } });

function fakeHost(routes, clock = { t: 1e12 }) {
  const calls = [];
  return {
    calls,
    clock,
    now: () => clock.t,
    log: () => {},
    fetch(req) {
      calls.push(req);
      for (const [match, reply] of routes) {
        if (match(req)) {
          const r = typeof reply === 'function' ? reply(req) : reply;
          return r instanceof Error ? Promise.reject(r) : Promise.resolve({ url: req.url, ...r });
        }
      }
      return Promise.resolve({ status: 404, body: '', url: req.url });
    },
  };
}
const isHome = (r) => r.url.startsWith('https://www.youtube.com/?');
const playerOf = (name) => (r) => r.url.includes('/youtubei/v1/player') && JSON.parse(r.body).context.client.clientName === name;
const isMaster = (r) => r.url.startsWith('https://manifest.googlevideo.com/');
const OK_ROUTES = () => [[isHome, { status: 200, body: HOME }], [playerOf('VISIONOS'), { status: 200, body: PLAYER.visionos }], [isMaster, { status: 200, body: '#EXTM3U\n' }]];

test('resolve: visionos mit Besucher-Kennung liefert geprüftes HLS', async () => {
  const h = fakeHost(OK_ROUTES());
  const s = await X.create(h).resolve('https://youtu.be/9bZkp7q19f0?t=3');
  assert.equal(s.kind, 'hls');
  assert.equal(s.client, 'visionos');
  assert.match(s.url, /^https:\/\/manifest\.googlevideo\.com\//);
  assert.match(s.userAgent, /Safari/);
  assert.equal(s.video.videoId, '9bZkp7q19f0');
  const req = h.calls.find(playerOf('VISIONOS'));
  const body = JSON.parse(req.body);
  assert.equal(req.method, 'POST');
  assert.equal(body.videoId, '9bZkp7q19f0');
  assert.match(body.context.client.visitorData, /^Cg/);
  assert.equal(req.headers['X-Goog-Visitor-Id'], body.context.client.visitorData);
  assert.equal(req.headers['X-YouTube-Client-Name'], '101');
  assert.match(h.calls.find(isHome).headers.Cookie, /SOCS=CAI/);
  assert.deepEqual(s.attempts.map((a) => [a.client, a.ok]), [['visionos', true]]);
});

test('resolve: Besucher-Kennung wird 6 h zwischengespeichert', async () => {
  const h = fakeHost(OK_ROUTES());
  const api = X.create(h);
  await api.resolve('9bZkp7q19f0');
  await api.resolve('9bZkp7q19f0');
  assert.equal(h.calls.filter(isHome).length, 1);
  h.clock.t += 6 * 3600 * 1000 + 1;
  await api.resolve('9bZkp7q19f0');
  assert.equal(h.calls.filter(isHome).length, 2);
});

test('resolve: LOGIN_REQUIRED → Kennung einmal neu holen, dann nächster Client', async () => {
  const h = fakeHost([[isHome, { status: 200, body: HOME }], [playerOf('VISIONOS'), { status: 200, body: LOGIN }],
    [playerOf('IOS'), { status: 200, body: PLAYER.ios }], [playerOf('ANDROID_VR'), { status: 200, body: PLAYER.android_vr }]]);
  const s = await X.create(h).resolve('9bZkp7q19f0');
  assert.equal(s.client, 'android_vr');
  assert.equal(s.kind, 'progressive');
  assert.equal(h.calls.filter(isHome).length, 2, 'genau ein Neuabruf der Kennung');
  assert.equal(h.calls.filter(playerOf('VISIONOS')).length, 2, 'visionos einmal wiederholt');
  assert.deepEqual(s.attempts.map((a) => a.client), ['visionos', 'visionos', 'ios', 'android_vr']);
});

test('resolve: alle scheitern → deutscher Sammelfehler, endlich viele Anfragen', async () => {
  const h = fakeHost([[isHome, { status: 200, body: HOME }], [(r) => r.url.includes('/player'), { status: 200, body: AGE }]]);
  await assert.rejects(X.create(h).resolve('9bZkp7q19f0'), (e) => e.code === 'ALL_CLIENTS_FAILED' && /altersbeschränkt/.test(e.message));
  assert.ok(h.calls.length <= 8, `${h.calls.length} Anfragen`);
});

test('resolve: Bot-Prüfung überall → Fehlertext nennt Anmeldung', async () => {
  const h = fakeHost([[isHome, { status: 200, body: HOME }], [(r) => r.url.includes('/player'), { status: 200, body: LOGIN }]]);
  await assert.rejects(X.create(h).resolve('9bZkp7q19f0'), (e) => /Anmeldung/.test(e.message));
  assert.equal(h.calls.filter(isHome).length, 2);
});

test('resolve: Netzfehler und kaputtes JSON führen zum nächsten Client', async () => {
  const h = fakeHost([[isHome, { status: 200, body: HOME }], [playerOf('VISIONOS'), new Error('offline')],
    [playerOf('IOS'), { status: 200, body: '<html>kein json' }], [playerOf('ANDROID_VR'), { status: 200, body: PLAYER.android_vr }]]);
  const s = await X.create(h).resolve('9bZkp7q19f0');
  assert.equal(s.client, 'android_vr');
  assert.equal(s.attempts[0].ok, false);
  assert.match(s.attempts[0].reason, /offline|Netz/);
});

test('resolve: Startseite nicht erreichbar → trotzdem Player-Anfragen', async () => {
  const h = fakeHost([[isHome, new Error('dns')], [playerOf('VISIONOS'), { status: 200, body: PLAYER.visionos }], [isMaster, { status: 200, body: '#EXTM3U\n' }]]);
  assert.equal((await X.create(h).resolve('9bZkp7q19f0')).client, 'visionos');
});

test('resolve: HLS-Master mit 403 zählt als Fehlschlag', async () => {
  const h = fakeHost([[isHome, { status: 200, body: HOME }], [playerOf('VISIONOS'), { status: 200, body: PLAYER.visionos }],
    [isMaster, { status: 403, body: '' }], [playerOf('IOS'), { status: 200, body: PLAYER.ios }], [playerOf('ANDROID_VR'), { status: 200, body: PLAYER.android_vr }]]);
  const s = await X.create(h).resolve('9bZkp7q19f0');
  assert.equal(s.client, 'android_vr');
  assert.match(s.attempts[0].reason, /403/);
});

test('resolve: exclude überspringt Clients', async () => {
  const h = fakeHost([[isHome, { status: 200, body: HOME }], [playerOf('IOS'), { status: 200, body: PLAYER.ios }], [playerOf('ANDROID_VR'), { status: 200, body: PLAYER.android_vr }]]);
  const s = await X.create(h).resolve('9bZkp7q19f0', { exclude: ['visionos'] });
  assert.equal(h.calls.filter(playerOf('VISIONOS')).length, 0);
  assert.equal(s.client, 'android_vr');
});

test('resolve: Einwilligungsseite ohne VISITOR_DATA → läuft ohne Kennung weiter', async () => {
  const h = fakeHost([[isHome, { status: 200, body: '<html>consent.youtube.com</html>' }], [playerOf('VISIONOS'), { status: 200, body: PLAYER.visionos }], [isMaster, { status: 200, body: '#EXTM3U\n' }]]);
  const s = await X.create(h).resolve('9bZkp7q19f0');
  assert.equal(s.client, 'visionos');
  const req = h.calls.find(playerOf('VISIONOS'));
  assert.equal(JSON.parse(req.body).context.client.visitorData, undefined);
  assert.equal(req.headers['X-Goog-Visitor-Id'], undefined);
});

test('resolve: ungültige Eingabe → INVALID_INPUT ohne Anfrage', async () => {
  const h = fakeHost([]);
  await assert.rejects(X.create(h).resolve('quatsch'), (e) => e.code === 'INVALID_INPUT');
  await assert.rejects(X.create(h).resolve(''), (e) => e.code === 'INVALID_INPUT');
  assert.equal(h.calls.length, 0);
});

test('search: leer → keine Anfrage; Umlaute im Body; Fortsetzung', async () => {
  const h = fakeHost([[isHome, { status: 200, body: HOME }], [(r) => r.url.includes('/youtubei/v1/search'), { status: 200, body: fx('search.json') }]]);
  const api = X.create(h);
  assert.deepEqual(await api.search('   '), { items: [], continuation: null });
  assert.deepEqual(await api.search(null), { items: [], continuation: null });
  assert.equal(h.calls.length, 0);
  const r = await api.search('  Grüße aus Köln ');
  const first = h.calls.find((c) => c.url.includes('/search'));
  const body = JSON.parse(first.body);
  assert.equal(body.query, 'Grüße aus Köln');
  assert.equal(body.params, 'EgIQAQ==');
  assert.equal(body.context.client.clientName, 'WEB');
  assert.match(body.context.client.clientVersion, /^2\.\d{8}/);
  assert.ok(r.items.length >= 15);
  await api.search('x', r.continuation);
  const last = JSON.parse(h.calls[h.calls.length - 1].body);
  assert.equal(last.continuation, r.continuation);
  assert.equal(last.query, undefined);
});

test('search: HTTP-Fehler → NETWORK', async () => {
  const h = fakeHost([[isHome, { status: 200, body: HOME }], [(r) => r.url.includes('/search'), { status: 500, body: '' }]]);
  await assert.rejects(X.create(h).search('test'), (e) => e.code === 'NETWORK' && /500/.test(e.message));
});

test('search: Netzfehler → NETWORK mit deutschem Text', async () => {
  const h = fakeHost([[isHome, { status: 200, body: HOME }], [(r) => r.url.includes('/search'), new Error('The Internet connection appears to be offline.')]]);
  await assert.rejects(X.create(h).search('test'), (e) => e.code === 'NETWORK' && /Netz/.test(e.message));
});

test('channelFeed und resolveChannel', async () => {
  const h = fakeHost([[(r) => r.url === 'https://www.youtube.com/feeds/videos.xml?channel_id=UC5NOEUbkLheQcaaRldYW5GA', { status: 200, body: fx('rss.xml') }],
    [(r) => r.url === 'https://www.youtube.com/@tagesschau', { status: 200, body: fx('channel-snippet.html') }]]);
  const api = X.create(h);
  assert.equal((await api.channelFeed('UC5NOEUbkLheQcaaRldYW5GA')).length, 15);
  await assert.rejects(api.channelFeed('kein-kanal'), (e) => e.code === 'INVALID_INPUT');
  assert.deepEqual(await api.resolveChannel('https://www.youtube.com/@tagesschau'), { channelId: 'UC5NOEUbkLheQcaaRldYW5GA', title: 'tagesschau' });
  assert.deepEqual(await api.resolveChannel('@tagesschau'), { channelId: 'UC5NOEUbkLheQcaaRldYW5GA', title: 'tagesschau' });
  assert.deepEqual(await api.resolveChannel('https://m.youtube.com/@tagesschau/videos'), { channelId: 'UC5NOEUbkLheQcaaRldYW5GA', title: 'tagesschau' });
  assert.equal((await api.resolveChannel('UC5NOEUbkLheQcaaRldYW5GA')).channelId, 'UC5NOEUbkLheQcaaRldYW5GA');
  assert.equal((await api.resolveChannel('https://www.youtube.com/channel/UC5NOEUbkLheQcaaRldYW5GA')).channelId, 'UC5NOEUbkLheQcaaRldYW5GA');
  await assert.rejects(api.resolveChannel('https://www.youtube.com/@gibtsnicht'), (e) => e.code === 'NOT_FOUND');
  await assert.rejects(api.resolveChannel('   '), (e) => e.code === 'INVALID_INPUT');
});

test('selfTest ist grün', () => {
  assert.equal(X.create({ fetch: () => Promise.reject(new Error('x')), log() {} }).selfTest(), true);
});

test('version ist ein Datum, damit Aktualisierungen vergleichbar sind', () => {
  assert.match(X.version, /^\d{4}\.\d{2}\.\d{2}(\.\d+)?$/);
  assert.equal(X.compareVersions('2026.10.12', '2026.10.13') < 0, true);
  assert.equal(X.compareVersions('2026.10.12.2', '2026.10.12') > 0, true);
  assert.equal(X.compareVersions('2026.10.12', '2026.10.12'), 0);
});

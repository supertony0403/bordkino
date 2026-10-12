'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const X = require('../js/extractor.js');

const fx = (n) => fs.readFileSync(path.join(__dirname, 'fixtures', n), 'utf8');

test('parseVideoId erkennt alle Linkformen', () => {
  const id = 'dQw4w9WgXcQ';
  for (const s of [id, `https://www.youtube.com/watch?v=${id}`, `https://youtu.be/${id}?t=42`,
    `https://m.youtube.com/watch?feature=share&v=${id}`, `https://www.youtube.com/shorts/${id}`,
    `https://www.youtube.com/live/${id}?si=abc`, `https://www.youtube.com/embed/${id}`,
    `https://music.youtube.com/watch?v=${id}&list=RD`, `  ${id}  `, `youtube.com/watch?v=${id}`]) {
    assert.equal(X.parseVideoId(s), id, s);
  }
  for (const s of ['', 'hallo welt', 'https://example.com/watch?v=dQw4w9WgXcQ', 'dQw4w9WgXc',
    'https://www.youtube.com/@tagesschau', null, undefined, 42]) {
    assert.equal(X.parseVideoId(s), null, String(s));
  }
});

test('parseHomeConfig liest Besucher-Kennung und Clientversion', () => {
  const c = X.parseHomeConfig(fx('home-snippet.html'));
  assert.match(c.visitorData, /^Cg/);
  assert.match(c.webClientVersion, /^2\.\d{8}\.\d{2}\.\d{2}$/);
  assert.deepEqual(X.parseHomeConfig('<html>consent</html>'), { visitorData: null, webClientVersion: null });
  assert.deepEqual(X.parseHomeConfig(null), { visitorData: null, webClientVersion: null });
});

test('parseSearch liefert Videos und Fortsetzung', () => {
  const r = X.parseSearch(JSON.parse(fx('search.json')));
  assert.ok(r.items.length >= 15, `nur ${r.items.length}`);
  const v = r.items[0];
  assert.match(v.videoId, /^[\w-]{11}$/);
  assert.ok(v.title.length > 0);
  assert.equal(v.channel, 'tagesschau');
  assert.match(v.channelId, /^UC[\w-]{22}$/);
  assert.match(v.durationText, /^\d+:\d\d$/);
  assert.ok(v.durationSeconds > 60);
  assert.match(v.thumbnail, /^https:\/\/i\.ytimg\.com\//);
  assert.equal(v.isLive, false);
  assert.equal(typeof r.continuation, 'string');
  assert.ok(r.continuation.length > 10);
  assert.equal(new Set(r.items.map((i) => i.videoId)).size, r.items.length, 'keine Dubletten');
  assert.deepEqual(X.parseSearch({}), { items: [], continuation: null });
  assert.deepEqual(X.parseSearch(null), { items: [], continuation: null });
});

test('parseSearch erkennt Livestreams', () => {
  const live = {
    contents: [{ videoRenderer: {
      videoId: 'abcdefghijk', title: { runs: [{ text: 'Live' }] },
      ownerText: { runs: [{ text: 'Sender', navigationEndpoint: { browseEndpoint: { browseId: 'UC1234567890123456789012' } } }] },
      thumbnail: { thumbnails: [{ url: 'https://i.ytimg.com/vi/abcdefghijk/hq.jpg' }] },
      badges: [{ metadataBadgeRenderer: { style: 'BADGE_STYLE_TYPE_LIVE_NOW', label: 'LIVE' } }],
    } }],
  };
  const [v] = X.parseSearch(live).items;
  assert.equal(v.isLive, true);
  assert.equal(v.durationSeconds, 0);
  assert.equal(v.durationText, 'LIVE');
});

test('parseFeed zerlegt Kanal-RSS mit Entities', () => {
  const items = X.parseFeed(fx('rss.xml'));
  assert.equal(items.length, 15);
  assert.match(items[0].videoId, /^[\w-]{11}$/);
  assert.equal(items[0].channel, 'tagesschau');
  assert.equal(items[0].channelId, 'UC5NOEUbkLheQcaaRldYW5GA');
  assert.match(items[0].thumbnail, /^https:\/\/i\d?\.ytimg\.com\//);
  assert.ok(!/&amp;|&quot;|&#39;|&lt;/.test(items.map((i) => i.title).join(' ')));
  assert.deepEqual(X.parseFeed('kaputt'), []);
  assert.deepEqual(X.parseFeed(null), []);
});

test('decodeEntities', () => {
  assert.equal(X.decodeEntities('A &amp; B &lt;3 &quot;x&quot; &#39;y&#39; &#228; &#x00FC;'), 'A & B <3 "x" \'y\' ä ü');
});

test('parseChannelPage findet ID und Titel', () => {
  assert.deepEqual(X.parseChannelPage(fx('channel-snippet.html')), { channelId: 'UC5NOEUbkLheQcaaRldYW5GA', title: 'tagesschau' });
  assert.equal(X.parseChannelPage('<html></html>'), null);
});

test('evaluatePlayer: visionos liefert HLS', () => {
  const r = X.evaluatePlayer(JSON.parse(fx('player-visionos.json')));
  assert.equal(r.ok, true);
  assert.equal(r.kind, 'hls');
  assert.match(r.url, /^https:\/\/manifest\.googlevideo\.com\//);
  assert.equal(r.video.videoId, '9bZkp7q19f0');
  assert.ok(r.video.durationSeconds > 200);
  assert.match(r.video.durationText, /^4:\d\d$/);
  assert.ok(r.video.title.length > 0);
  assert.match(r.video.channelId, /^UC/);
  assert.match(r.video.thumbnail, /^https:\/\//);
});

test('evaluatePlayer: ohne HLS, aber mit kombiniertem Format → progressive', () => {
  const r = X.evaluatePlayer(JSON.parse(fx('player-android_vr.json')));
  assert.equal(r.ok, true);
  assert.equal(r.kind, 'progressive');
  assert.match(r.url, /^https:\/\//);
});

test('evaluatePlayer: ohne nutzbare URL → NO_STREAM', () => {
  const r = X.evaluatePlayer(JSON.parse(fx('player-ios.json')));
  assert.equal(r.ok, false);
  assert.equal(r.code, 'NO_STREAM');
  assert.ok(r.reason.length > 0);
});

test('evaluatePlayer: Statuscodes werden zu deutschen Gründen', () => {
  const mk = (status, reason) => ({ playabilityStatus: { status, reason } });
  assert.equal(X.evaluatePlayer(mk('LOGIN_REQUIRED', 'Sign in to confirm')).code, 'LOGIN_REQUIRED');
  assert.match(X.evaluatePlayer(mk('LOGIN_REQUIRED', 'Melde dich an')).reason, /Anmeldung|Bot/);
  assert.match(X.evaluatePlayer(mk('AGE_CHECK_REQUIRED', '')).reason, /altersbeschränkt/);
  assert.match(X.evaluatePlayer(mk('LIVE_STREAM_OFFLINE', '')).reason, /Livestream/);
  assert.match(X.evaluatePlayer(mk('ERROR', 'Video nicht verfügbar')).reason, /nicht verfügbar/);
  assert.match(X.evaluatePlayer(mk('UNPLAYABLE', 'Privates Video')).reason, /Privates Video/);
  assert.equal(X.evaluatePlayer(null).ok, false);
  assert.equal(X.evaluatePlayer({}).ok, false);
});

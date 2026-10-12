/*
 * Bordkino extractor – YouTube logic shared by the iOS app (JavaScriptCore)
 * and the Node test suite.
 *
 * Constraints: plain ECMAScript only. No fetch/URL/setTimeout/console/TextEncoder.
 * All I/O goes through the injected `host`:
 *   host.fetch({url, method, headers, body}) -> Promise<{status, body, url}>
 *   host.log(text)
 *   host.now() -> epoch ms (optional, defaults to Date.now)
 */
var BordkinoExtractor = (function () {
  'use strict';

  var VERSION = '2026.10.12';

  // ---------------------------------------------------------------- helpers

  function isObject(v) {
    return v !== null && typeof v === 'object';
  }

  function textOf(t) {
    if (!isObject(t)) return '';
    if (typeof t.simpleText === 'string') return t.simpleText;
    if (Array.isArray(t.runs)) return t.runs.map(function (r) { return r.text || ''; }).join('');
    return '';
  }

  function decodeEntities(s) {
    if (typeof s !== 'string') return '';
    return s
      .replace(/&#x([0-9a-fA-F]+);/g, function (_, h) { return String.fromCodePoint(parseInt(h, 16)); })
      .replace(/&#(\d+);/g, function (_, d) { return String.fromCodePoint(parseInt(d, 10)); })
      .replace(/&quot;/g, '"')
      .replace(/&apos;/g, "'")
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&amp;/g, '&');
  }

  function parseDuration(text) {
    if (typeof text !== 'string' || !/^\d+(:\d{1,2}){0,2}$/.test(text)) return 0;
    return text.split(':').reduce(function (acc, part) { return acc * 60 + parseInt(part, 10); }, 0);
  }

  function formatDuration(seconds) {
    seconds = Math.max(0, Math.floor(seconds || 0));
    var h = Math.floor(seconds / 3600);
    var m = Math.floor((seconds % 3600) / 60);
    var s = seconds % 60;
    var ss = (s < 10 ? '0' : '') + s;
    if (h > 0) return h + ':' + (m < 10 ? '0' : '') + m + ':' + ss;
    return m + ':' + ss;
  }

  function lastThumbnail(thumb) {
    var list = isObject(thumb) && Array.isArray(thumb.thumbnails) ? thumb.thumbnails : [];
    if (!list.length) return '';
    var url = list[list.length - 1].url || '';
    if (url.indexOf('//') === 0) url = 'https:' + url;
    return url;
  }

  function makeVideo(fields) {
    return {
      videoId: fields.videoId,
      title: fields.title || '',
      channel: fields.channel || '',
      channelId: fields.channelId || '',
      durationText: fields.durationText || '',
      durationSeconds: fields.durationSeconds || 0,
      thumbnail: fields.thumbnail || ('https://i.ytimg.com/vi/' + fields.videoId + '/hqdefault.jpg'),
      isLive: !!fields.isLive,
      subtitle: fields.subtitle || '',
    };
  }

  // ------------------------------------------------------------- video ids

  var ID_RE = /^[A-Za-z0-9_-]{11}$/;
  var LINK_RE = /^(?:https?:\/\/)?(?:(?:www|m|music)\.)?(youtube\.com|youtu\.be)(\/[^?#]*)?(\?[^#]*)?/i;

  function parseVideoId(input) {
    if (typeof input !== 'string') return null;
    var s = input.trim();
    if (ID_RE.test(s)) return s;
    var m = LINK_RE.exec(s);
    if (!m) return null;
    var host = m[1].toLowerCase();
    var p = m[2] || '';
    var query = m[3] || '';
    var candidate = null;
    if (host === 'youtu.be') {
      candidate = p.split('/')[1];
    } else if (p === '/watch' || p === '/watch/') {
      var q = /[?&]v=([^&]+)/.exec(query);
      candidate = q ? q[1] : null;
    } else {
      var seg = /^\/(?:shorts|live|embed|v)\/([^/]+)/.exec(p);
      candidate = seg ? seg[1] : null;
    }
    return candidate && ID_RE.test(candidate) ? candidate : null;
  }

  // ------------------------------------------------------------- home page

  function parseHomeConfig(html) {
    var out = { visitorData: null, webClientVersion: null };
    if (typeof html !== 'string') return out;
    var vd = /"VISITOR_DATA":"([^"]+)"/.exec(html);
    var cv = /"INNERTUBE_CLIENT_VERSION":"([^"]+)"/.exec(html);
    if (vd) out.visitorData = vd[1];
    if (cv) out.webClientVersion = cv[1];
    return out;
  }

  // ---------------------------------------------------------------- search

  function collect(node, key, out) {
    if (Array.isArray(node)) {
      for (var i = 0; i < node.length; i++) collect(node[i], key, out);
    } else if (isObject(node)) {
      if (Object.prototype.hasOwnProperty.call(node, key)) out.push(node[key]);
      for (var k in node) {
        if (Object.prototype.hasOwnProperty.call(node, k)) collect(node[k], key, out);
      }
    }
    return out;
  }

  function videoFromRenderer(r) {
    if (!isObject(r) || !ID_RE.test(r.videoId || '')) return null;
    var owner = (r.ownerText && r.ownerText.runs) || (r.longBylineText && r.longBylineText.runs) || [];
    var channelRun = owner[0] || {};
    var browse = channelRun.navigationEndpoint && channelRun.navigationEndpoint.browseEndpoint;
    var badges = Array.isArray(r.badges) ? r.badges : [];
    var liveBadge = badges.some(function (b) {
      return b.metadataBadgeRenderer && /LIVE/.test(b.metadataBadgeRenderer.style || '');
    });
    var durationText = textOf(r.lengthText);
    var isLive = liveBadge || (!durationText && !!textOf(r.viewCountText).match(/zuschauer|watching/i));
    var subtitleParts = [textOf(r.shortViewCountText) || textOf(r.viewCountText), textOf(r.publishedTimeText)].filter(Boolean);
    return makeVideo({
      videoId: r.videoId,
      title: textOf(r.title),
      channel: channelRun.text || '',
      channelId: browse ? browse.browseId : '',
      durationText: isLive && !durationText ? 'LIVE' : durationText,
      durationSeconds: parseDuration(durationText),
      thumbnail: lastThumbnail(r.thumbnail),
      isLive: isLive,
      subtitle: subtitleParts.join(' · '),
    });
  }

  function parseSearch(json) {
    var items = [];
    var seen = {};
    collect(json, 'videoRenderer', []).forEach(function (r) {
      var v = videoFromRenderer(r);
      if (v && !seen[v.videoId]) {
        seen[v.videoId] = true;
        items.push(v);
      }
    });
    var commands = collect(json, 'continuationCommand', []);
    var token = null;
    for (var i = 0; i < commands.length; i++) {
      if (isObject(commands[i]) && typeof commands[i].token === 'string') { token = commands[i].token; break; }
    }
    return { items: items, continuation: token };
  }

  // ------------------------------------------------------------ channel rss

  function tag(block, name) {
    var m = new RegExp('<' + name + '(?:\\s[^>]*)?>([\\s\\S]*?)</' + name + '>').exec(block);
    return m ? decodeEntities(m[1].trim()) : '';
  }

  function attr(block, name, attribute) {
    var m = new RegExp('<' + name + '\\s[^>]*' + attribute + '="([^"]*)"').exec(block);
    return m ? decodeEntities(m[1]) : '';
  }

  function parseFeed(xml) {
    if (typeof xml !== 'string') return [];
    var out = [];
    var re = /<entry>([\s\S]*?)<\/entry>/g;
    var m;
    while ((m = re.exec(xml)) !== null) {
      var e = m[1];
      var id = tag(e, 'yt:videoId');
      if (!ID_RE.test(id)) continue;
      var published = tag(e, 'published');
      var views = attr(e, 'media:statistics', 'views');
      var subtitle = [views ? Number(views).toLocaleString('de-DE') + ' Aufrufe' : '', published ? published.slice(0, 10).split('-').reverse().join('.') : '']
        .filter(Boolean).join(' · ');
      out.push(makeVideo({
        videoId: id,
        title: tag(e, 'title'),
        channel: tag(e, 'name'),
        channelId: tag(e, 'yt:channelId'),
        thumbnail: attr(e, 'media:thumbnail', 'url'),
        subtitle: subtitle,
      }));
    }
    return out;
  }

  function parseChannelPage(html) {
    if (typeof html !== 'string') return null;
    var id = /<meta itemprop="identifier" content="(UC[\w-]{22})"/.exec(html) ||
      /"externalId":"(UC[\w-]{22})"/.exec(html) ||
      /"channelId":"(UC[\w-]{22})"/.exec(html);
    if (!id) return null;
    var title = /<meta property="og:title" content="([^"]*)"/.exec(html);
    return { channelId: id[1], title: title ? decodeEntities(title[1]) : '' };
  }

  // ---------------------------------------------------------------- player

  function videoFromDetails(d) {
    d = isObject(d) ? d : {};
    var seconds = parseInt(d.lengthSeconds || '0', 10) || 0;
    return makeVideo({
      videoId: d.videoId,
      title: d.title,
      channel: d.author,
      channelId: d.channelId,
      durationSeconds: seconds,
      durationText: d.isLive ? 'LIVE' : (seconds ? formatDuration(seconds) : ''),
      thumbnail: lastThumbnail(d.thumbnail),
      isLive: !!d.isLive,
    });
  }

  function reasonFor(status, reason) {
    switch (status) {
      case 'LOGIN_REQUIRED':
        return 'YouTube verlangt eine Anmeldung (Bot-Prüfung).';
      case 'AGE_CHECK_REQUIRED':
      case 'AGE_VERIFICATION_REQUIRED':
      case 'CONTENT_CHECK_REQUIRED':
        return 'Video ist altersbeschränkt.';
      case 'LIVE_STREAM_OFFLINE':
        return 'Livestream hat noch nicht begonnen.';
      default:
        return 'Video nicht verfügbar' + (reason ? ': ' + reason : '.');
    }
  }

  function evaluatePlayer(json) {
    if (!isObject(json) || !isObject(json.playabilityStatus)) {
      return { ok: false, code: 'BAD_RESPONSE', reason: 'Unerwartete Antwort von YouTube.' };
    }
    var ps = json.playabilityStatus;
    var status = ps.status || 'UNKNOWN';
    if (status !== 'OK') {
      return { ok: false, code: status, reason: reasonFor(status, ps.reason || textOf(ps.errorScreen && ps.errorScreen.playerErrorMessageRenderer && ps.errorScreen.playerErrorMessageRenderer.reason)) };
    }
    var video = videoFromDetails(json.videoDetails);
    var sd = isObject(json.streamingData) ? json.streamingData : {};
    if (typeof sd.hlsManifestUrl === 'string' && sd.hlsManifestUrl) {
      return { ok: true, kind: 'hls', url: sd.hlsManifestUrl, video: video };
    }
    var muxed = (Array.isArray(sd.formats) ? sd.formats : []).filter(function (f) { return typeof f.url === 'string'; });
    muxed.sort(function (a, b) { return (b.itag === 22) - (a.itag === 22) || (b.height || 0) - (a.height || 0); });
    if (muxed.length) {
      return { ok: true, kind: 'progressive', url: muxed[0].url, video: video };
    }
    return { ok: false, code: 'NO_STREAM', reason: 'Kein abspielbarer Stream für diesen Client.' };
  }

  // --------------------------------------------------------------- clients
  // Values mirror yt-dlp (yt_dlp/extractor/youtube/_base.py, July 2026).

  var SAFARI_UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.5 Safari/605.1.15';
  var WEB_CLIENT_VERSION_FALLBACK = '2.20261012.01.00';
  var VISITOR_TTL_MS = 6 * 3600 * 1000;

  var CLIENTS = [
    {
      name: 'visionos', id: '101',
      context: { clientName: 'VISIONOS', clientVersion: '1.02', deviceMake: 'Apple', deviceModel: 'RealityDevice17,1', osName: 'visionOS', osVersion: '26.5.23O471' },
      userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15',
    },
    {
      name: 'ios', id: '5',
      context: { clientName: 'IOS', clientVersion: '21.26.4', deviceMake: 'Apple', deviceModel: 'iPhone16,2', osName: 'iPhone', osVersion: '18.3.2.22D82' },
      userAgent: 'com.google.ios.youtube/21.26.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)',
    },
    {
      name: 'android_vr', id: '28',
      context: { clientName: 'ANDROID_VR', clientVersion: '1.65.10', deviceMake: 'Oculus', deviceModel: 'Quest 3', androidSdkVersion: 32, osName: 'Android', osVersion: '12L' },
      userAgent: 'com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip',
    },
  ];

  function fail(code, message) {
    var e = new Error(message);
    e.code = code;
    return e;
  }

  function networkMessage(err) {
    var detail = err && err.message ? err.message : String(err);
    return 'Kein Netz oder Server nicht erreichbar (' + detail + ').';
  }

  function compareVersions(a, b) {
    var pa = String(a).split('.').map(Number);
    var pb = String(b).split('.').map(Number);
    for (var i = 0; i < Math.max(pa.length, pb.length); i++) {
      var d = (pa[i] || 0) - (pb[i] || 0);
      if (d !== 0) return d < 0 ? -1 : 1;
    }
    return 0;
  }

  function create(host) {
    var now = typeof host.now === 'function' ? function () { return host.now(); } : function () { return Date.now(); };
    var log = typeof host.log === 'function' ? function (t) { host.log(String(t)); } : function () {};
    var visitor = null; // {visitorData, webClientVersion, at}

    function getVisitor(forceRefresh) {
      if (!forceRefresh && visitor && now() - visitor.at < VISITOR_TTL_MS) return Promise.resolve(visitor);
      return host.fetch({
        url: 'https://www.youtube.com/?hl=de&gl=DE',
        method: 'GET',
        headers: { 'User-Agent': SAFARI_UA, 'Accept-Language': 'de-DE,de;q=0.9', Cookie: 'SOCS=CAI' },
      }).then(function (res) {
        var cfg = parseHomeConfig(res && res.status === 200 ? res.body : '');
        if (!cfg.visitorData) log('Startseite ohne VISITOR_DATA (Status ' + (res && res.status) + ')');
        visitor = { visitorData: cfg.visitorData, webClientVersion: cfg.webClientVersion || WEB_CLIENT_VERSION_FALLBACK, at: now() };
        return visitor;
      }, function (err) {
        log('Startseite nicht erreichbar: ' + (err && err.message));
        // Do not cache the failure: the next call tries again.
        return { visitorData: null, webClientVersion: WEB_CLIENT_VERSION_FALLBACK, at: 0 };
      });
    }

    function innertube(endpoint, client, vis, payload) {
      var ctxClient = {};
      for (var k in client.context) ctxClient[k] = client.context[k];
      ctxClient.hl = 'de';
      ctxClient.gl = 'DE';
      if (vis.visitorData) ctxClient.visitorData = vis.visitorData;
      var body = { context: { client: ctxClient } };
      for (var p in payload) body[p] = payload[p];
      var headers = {
        'Content-Type': 'application/json',
        'User-Agent': client.userAgent,
        'X-YouTube-Client-Name': client.id,
        'X-YouTube-Client-Version': ctxClient.clientVersion,
        Origin: 'https://www.youtube.com',
      };
      if (vis.visitorData) headers['X-Goog-Visitor-Id'] = vis.visitorData;
      return host.fetch({
        url: 'https://www.youtube.com/youtubei/v1/' + endpoint + '?prettyPrint=false',
        method: 'POST',
        headers: headers,
        body: JSON.stringify(body),
      });
    }

    function verifyHls(url, client) {
      return host.fetch({ url: url, method: 'GET', headers: { 'User-Agent': client.userAgent } }).then(function (res) {
        if (res.status !== 200 || String(res.body).indexOf('#EXTM3U') !== 0) {
          throw fail('HLS_REJECTED', 'HLS-Liste abgelehnt (HTTP ' + res.status + ')');
        }
      });
    }

    function tryClient(client, videoId, vis) {
      return innertube('player', client, vis, { videoId: videoId, contentCheckOk: true, racyCheckOk: true })
        .then(function (res) {
          if (res.status !== 200) throw fail('HTTP', 'HTTP ' + res.status);
          var json;
          try { json = JSON.parse(res.body); } catch (e) { throw fail('BAD_RESPONSE', 'Antwort ist kein JSON'); }
          var r = evaluatePlayer(json);
          if (!r.ok) return r;
          if (r.kind !== 'hls') return r;
          return verifyHls(r.url, client).then(function () { return r; }, function (e) {
            return { ok: false, code: e.code || 'HLS_REJECTED', reason: e.message };
          });
        }, function (err) {
          return { ok: false, code: 'NETWORK', reason: networkMessage(err) };
        })
        .then(null, function (err) {
          return { ok: false, code: err.code || 'ERROR', reason: err.message || String(err) };
        });
    }

    function summarize(attempts) {
      var meaningful = attempts.filter(function (a) { return a.code !== 'NO_STREAM' && a.code !== 'NETWORK'; });
      var pick = meaningful[0] || attempts[0];
      return 'Video kann nicht abgespielt werden. ' + (pick ? pick.reason : '');
    }

    function resolve(input, opts) {
      var videoId = parseVideoId(input);
      if (!videoId) return Promise.reject(fail('INVALID_INPUT', 'Das ist kein YouTube-Link und keine Video-ID.'));
      var exclude = (opts && Array.isArray(opts.exclude)) ? opts.exclude : [];
      var queue = CLIENTS.filter(function (c) { return exclude.indexOf(c.name) < 0; });
      var attempts = [];
      var refreshed = false;

      function next(i, vis) {
        if (i >= queue.length) {
          var err = fail('ALL_CLIENTS_FAILED', summarize(attempts));
          err.attempts = attempts;
          return Promise.reject(err);
        }
        var client = queue[i];
        return tryClient(client, videoId, vis).then(function (r) {
          attempts.push({ client: client.name, ok: r.ok, code: r.ok ? 'OK' : r.code, reason: r.ok ? r.kind : r.reason });
          log('Client ' + client.name + ': ' + (r.ok ? 'OK ' + r.kind : r.code + ' – ' + r.reason));
          if (r.ok) {
            return { kind: r.kind, url: r.url, client: client.name, userAgent: client.userAgent, video: r.video, attempts: attempts };
          }
          if (r.code === 'LOGIN_REQUIRED' && !refreshed) {
            refreshed = true;
            return getVisitor(true).then(function (fresh) { return next(i, fresh); });
          }
          return next(i + 1, vis);
        });
      }

      return getVisitor(false).then(function (vis) { return next(0, vis); });
    }

    function search(query, continuation) {
      var q = typeof query === 'string' ? query.trim() : '';
      if (!q && !continuation) return Promise.resolve({ items: [], continuation: null });
      var web = { name: 'web', id: '1', context: { clientName: 'WEB' }, userAgent: SAFARI_UA };
      return getVisitor(false).then(function (vis) {
        web.context.clientVersion = vis.webClientVersion || WEB_CLIENT_VERSION_FALLBACK;
        var payload = continuation ? { continuation: continuation } : { query: q, params: 'EgIQAQ==' };
        return innertube('search', web, vis, payload).then(function (res) {
          if (res.status !== 200) throw fail('NETWORK', 'Suche fehlgeschlagen (HTTP ' + res.status + ').');
          var json;
          try { json = JSON.parse(res.body); } catch (e) { throw fail('BAD_RESPONSE', 'Unerwartete Antwort von YouTube.'); }
          return parseSearch(json);
        }, function (err) {
          throw fail('NETWORK', networkMessage(err));
        });
      });
    }

    function getText(url) {
      return host.fetch({ url: url, method: 'GET', headers: { 'User-Agent': SAFARI_UA, 'Accept-Language': 'de-DE,de;q=0.9', Cookie: 'SOCS=CAI' } })
        .then(null, function (err) { throw fail('NETWORK', networkMessage(err)); });
    }

    function channelFeed(channelId) {
      if (!/^UC[\w-]{22}$/.test(channelId || '')) return Promise.reject(fail('INVALID_INPUT', 'Ungültige Kanal-ID.'));
      return getText('https://www.youtube.com/feeds/videos.xml?channel_id=' + channelId).then(function (res) {
        if (res.status !== 200) throw fail(res.status === 404 ? 'NOT_FOUND' : 'NETWORK', 'Kanal-Feed nicht abrufbar (HTTP ' + res.status + ').');
        return parseFeed(res.body);
      });
    }

    function resolveChannel(input) {
      var s = typeof input === 'string' ? input.trim() : '';
      if (!s) return Promise.reject(fail('INVALID_INPUT', 'Bitte Kanal-Link, @Name oder Kanal-ID eingeben.'));
      var direct = /(?:^|\/channel\/)(UC[\w-]{22})(?:[/?#]|$)/.exec(s);
      var pageUrl;
      if (direct) {
        pageUrl = 'https://www.youtube.com/channel/' + direct[1];
      } else {
        var handle = /(?:^|youtube\.com\/)(@[\w.\-]+)/i.exec(s);
        if (!handle) return Promise.reject(fail('INVALID_INPUT', 'Bitte Kanal-Link, @Name oder Kanal-ID eingeben.'));
        pageUrl = 'https://www.youtube.com/' + handle[1];
      }
      return getText(pageUrl).then(function (res) {
        var info = res.status === 200 ? parseChannelPage(res.body) : null;
        if (info) return info;
        if (direct) return { channelId: direct[1], title: '' };
        throw fail('NOT_FOUND', 'Kanal nicht gefunden.');
      });
    }

    function selfTest() {
      try {
        var okId = parseVideoId('https://youtu.be/dQw4w9WgXcQ?t=1') === 'dQw4w9WgXcQ' && parseVideoId('nope') === null;
        var hls = evaluatePlayer({
          playabilityStatus: { status: 'OK' },
          videoDetails: { videoId: 'dQw4w9WgXcQ', title: 't', author: 'a', lengthSeconds: '61' },
          streamingData: { hlsManifestUrl: 'https://manifest.googlevideo.com/x' },
        });
        var login = evaluatePlayer({ playabilityStatus: { status: 'LOGIN_REQUIRED' } });
        var feed = parseFeed('<entry><yt:videoId>dQw4w9WgXcQ</yt:videoId><title>A &amp; B</title></entry>');
        return okId && hls.ok && hls.kind === 'hls' && hls.video.durationText === '1:01' &&
          !login.ok && login.code === 'LOGIN_REQUIRED' && feed.length === 1 && feed[0].title === 'A & B' &&
          CLIENTS.length > 0;
      } catch (e) {
        return false;
      }
    }

    return {
      version: VERSION,
      resolve: resolve,
      search: search,
      channelFeed: channelFeed,
      resolveChannel: resolveChannel,
      selfTest: selfTest,
      parseVideoId: parseVideoId,
    };
  }

  return {
    version: VERSION,
    create: create,
    compareVersions: compareVersions,
    parseVideoId: parseVideoId,
    parseHomeConfig: parseHomeConfig,
    parseSearch: parseSearch,
    parseFeed: parseFeed,
    parseChannelPage: parseChannelPage,
    evaluatePlayer: evaluatePlayer,
    decodeEntities: decodeEntities,
    formatDuration: formatDuration,
  };
})();

if (typeof module !== 'undefined' && module.exports) {
  module.exports = BordkinoExtractor;
}

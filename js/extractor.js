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

  return {
    version: VERSION,
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

// Live smoke test: runs js/extractor.js against the real YouTube from this machine.
// Not part of `npm test` – it depends on the network and on YouTube's mood.
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const X = require('../js/extractor.js');

const host = {
  async fetch(req) {
    const res = await fetch(req.url, { method: req.method || 'GET', headers: req.headers, body: req.body, redirect: 'follow' });
    return { status: res.status, body: await res.text(), url: res.url };
  },
  log: (t) => console.log('  log:', t),
};

const api = X.create(host);
let failed = false;
const step = async (name, fn) => {
  try {
    console.log(`OK   ${name}: ${await fn()}`);
  } catch (e) {
    failed = true;
    console.log(`FAIL ${name}: ${e.code || ''} ${e.message}`);
  }
};

console.log(`extractor ${X.version}, selfTest=${api.selfTest()}`);
let first;
await step('Suche "tagesschau"', async () => {
  const r = await api.search('tagesschau');
  first = r.items[0];
  return `${r.items.length} Treffer, erster: ${first.videoId} „${first.title.slice(0, 40)}“ (${first.durationText})`;
});
await step('Auflösen erster Treffer', async () => {
  const s = await api.resolve(first.videoId);
  return `${s.client} ${s.kind} (${s.video.durationText}) nach ${s.attempts.length} Versuch(en)`;
});
await step('Auflösen 9bZkp7q19f0 per Kurzlink', async () => {
  const s = await api.resolve('https://youtu.be/9bZkp7q19f0?t=10');
  return `${s.client} ${s.kind} „${s.video.title.slice(0, 30)}“`;
});
await step('Kanal @tagesschau', async () => {
  const c = await api.resolveChannel('@tagesschau');
  const feed = await api.channelFeed(c.channelId);
  return `${c.channelId} „${c.title}“, ${feed.length} Videos`;
});
process.exit(failed ? 1 : 0);

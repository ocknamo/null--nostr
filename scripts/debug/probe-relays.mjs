// Diagnostic: probe relays for Kind-445 events on a given MLS group.
// Usage: pnpm dlx ws; GID=<group_id_hex> SINCE=<unix_ts> node scripts/debug/probe-relays.mjs
//
// The group_id and since-timestamp are NOT committed: pass them via env so
// committed code does not pin a specific user's Talk session.
import WebSocket from 'ws';

const GID = process.env.GID || '<32-byte-mls-group-id-hex>';
const SINCE = Number(process.env.SINCE || 0); // unix seconds; 0 = no since filter
const RELAYS = [
  'wss://yabu.me',
  'wss://r.kojira.io',
  'wss://relay.0xchat.com',
  'wss://auth.nostr1.com',
  'wss://relay.damus.io',
  'wss://relay-jp.nostr.wirednet.jp',
];

if (!/^[0-9a-f]{64}$/i.test(GID)) {
  console.error('GID env var must be a 32-byte hex MLS group_id (64 hex chars).');
  process.exit(2);
}

async function probe(url) {
  return new Promise((resolve) => {
    const ws = new WebSocket(url);
    const events = [];
    const subId = 'probe' + Math.random().toString(36).slice(2, 7);
    const t = setTimeout(() => { try { ws.close(); } catch {} resolve({ url, events, timedOut: true }); }, 8000);
    ws.on('open', () => {
      const filter = { kinds: [445], '#h': [GID], limit: 50 };
      if (SINCE > 0) filter.since = SINCE;
      ws.send(JSON.stringify(['REQ', subId, filter]));
    });
    ws.on('message', (data) => {
      try {
        const msg = JSON.parse(data.toString());
        if (msg[0] === 'EVENT' && msg[1] === subId) events.push({ id: msg[2].id.slice(0, 12), created_at: msg[2].created_at, pubkey: msg[2].pubkey.slice(0, 8) });
        else if (msg[0] === 'EOSE' && msg[1] === subId) { clearTimeout(t); try { ws.close(); } catch {} resolve({ url, events, timedOut: false }); }
      } catch {}
    });
    ws.on('error', () => { clearTimeout(t); resolve({ url, events: [], error: true }); });
  });
}

const results = await Promise.all(RELAYS.map(probe));
for (const r of results) {
  const tag = r.error ? '❌ERR' : r.timedOut ? '⏱TO ' : '✅OK ';
  console.log(`${tag} ${r.url.padEnd(40)} → ${r.events.length} events`);
  for (const e of r.events.sort((a, b) => a.created_at - b.created_at)) console.log(`     ${e.id}  t=${e.created_at}  by=${e.pubkey}`);
}

// CLI stand-in for the other machine. Joins a room, sends apply requests to the panel, prints the acks.
// usage: node probe-peer.js ws://host:8080 ROOM [field] [value]   (field: opacity|scale|rotation)
const WebSocket = require('ws');
const [url, room, field = 'opacity', value = '37'] = process.argv.slice(2);
if (!url || !room) { console.error('usage: node probe-peer.js <ws-url> <room> [field] [value]'); process.exit(2); }
const ws = new WebSocket(url);
const sent = {};
ws.on('open', () => ws.send(JSON.stringify({ t: 'join', room, name: 'cli-peer' })));
ws.on('message', (d) => {
  const m = JSON.parse(d.toString());
  console.log('<-', JSON.stringify(m));
  if (m.t === 'joined' || m.t === 'peer') {
    const id = 'cli-' + Date.now();
    sent[id] = Date.now();
    ws.send(JSON.stringify({ t: 'apply', id, track: 0, clip: 0, field, value: Number(value) }));
  }
  if (m.t === 'applied') { console.log('round trip ms:', Date.now() - sent[m.id]); ws.close(); }
});
ws.on('close', () => process.exit(0));
setTimeout(() => { console.error('timeout, no ack'); process.exit(1); }, 15000);

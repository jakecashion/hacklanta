// ping.js - check a relay from the command line: node ping.js ws://192.168.x.x:8080
const { WebSocket } = require('ws');

const url = process.argv[2] || 'ws://localhost:8080';
const ws = new WebSocket(url);
const timer = setTimeout(() => { console.error('Timeout: no pong in 5 s'); process.exit(1); }, 5000);

ws.on('open', () => {
  ws.send(JSON.stringify({ type: 'hello', name: 'ping.js' }));
  ws.send(JSON.stringify({ type: 'ping', t: Date.now() }));
});
ws.on('message', (raw) => {
  const msg = JSON.parse(raw);
  if (msg.type === 'pong') {
    console.log(`OK ${url} round trip ${Date.now() - msg.t} ms`);
    clearTimeout(timer);
    ws.close();
  }
});
ws.on('error', (e) => { console.error('Error:', e.message); process.exit(1); });

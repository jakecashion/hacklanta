// fake-cursor.js - a second editor's mouse pointer for testing cursor.ps1 on one laptop.
// node fake-cursor.js [ws://host:8080] [name]
// Sends a pointer that loops around Premiere's window at 20 Hz, and prints a summary of the
// cursor messages it receives (your own cursor.ps1 shows up here).
const { WebSocket } = require('ws');

const url = process.argv[2] || 'ws://localhost:8080';
const name = process.argv[3] || 'Bot';

const ws = new WebSocket(url);
let got = 0;
let last = null;
ws.on('open', () => {
  console.log(`Connected to ${url} as "${name}". Pointer loops over Premiere. Ctrl+C to stop.`);
  const t0 = Date.now();
  setInterval(() => {
    const t = (Date.now() - t0) / 1000;
    // Figure eight across the middle of the window, one loop every 8 s.
    const x = 0.5 + 0.3 * Math.sin(t * Math.PI / 4);
    const y = 0.5 + 0.2 * Math.sin(t * Math.PI / 2);
    ws.send(JSON.stringify({ type: 'cursor', name, x: +x.toFixed(4), y: +y.toFixed(4), inside: true }));
  }, 50);
  setInterval(() => {
    if (got) console.log(`received ${got} cursor msgs in 2 s, last from "${last.name}": x ${last.x} y ${last.y} inside ${last.inside}`);
    got = 0;
  }, 2000);
});
ws.on('message', (raw) => {
  const msg = JSON.parse(raw);
  if (msg.type === 'cursor') { got += 1; last = msg; }
});
ws.on('close', () => { console.log('Disconnected'); process.exit(0); });
ws.on('error', (e) => { console.error('Error:', e.message); process.exit(1); });

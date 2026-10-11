// fake-peer.js - a second "editor" for testing sync on one laptop.
// node fake-peer.js [ws://host:8080] [clipId] [rename]
// Prints every commit (your Premiere edits show up here), then every 4 s sends one edit
// to the clip (default nodeId 000f4242, V1 clip 0 in demo.prproj) so you can watch Premiere change by itself.
// With "rename" it renames the clip instead (two test names; rename it back by hand after).
const { WebSocket } = require('ws');

const url = process.argv[2] || 'ws://localhost:8080';
const clipId = process.argv[3] || '000f4242';
const steps = process.argv[4] === 'rename'
  ? [['Clip.name', 'Renamed by fake peer'], ['Clip.name', 'Fake peer rename 2']]
  : [
    ['Motion.Scale', 175], ['Motion.Rotation', 30], ['Opacity.Opacity', 60],
    ['Motion.Scale', 100], ['Motion.Rotation', 0], ['Opacity.Opacity', 100],
  ];

const ws = new WebSocket(url);
let n = 0;
ws.on('open', () => {
  ws.send(JSON.stringify({ type: 'hello', name: 'Fake peer' }));
  console.log(`Connected to ${url}. Sending an edit to ${clipId} every 4 s. Ctrl+C to stop.`);
  setInterval(() => {
    const [field, value] = steps[n % steps.length];
    n += 1;
    ws.send(JSON.stringify({ type: 'op', opId: `fake-${n}`, clipId, field, value }));
  }, 4000);
});
ws.on('message', (raw) => {
  const msg = JSON.parse(raw);
  if (msg.type === 'commit') {
    const { op } = msg;
    console.log(`rev ${msg.rev}: ${op.author} set ${op.clipId} ${op.field} = ${op.value}`);
  } else if (msg.type === 'peers') {
    console.log('Here:', msg.names.join(', '));
  } else if (msg.type === 'error') {
    console.log('Relay error:', msg.err);
  }
});
ws.on('close', () => { console.log('Disconnected'); process.exit(0); });
ws.on('error', (e) => { console.error('Error:', e.message); process.exit(1); });

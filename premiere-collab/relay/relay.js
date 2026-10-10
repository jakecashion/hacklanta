// relay.js - Phase 1 relay: ping/pong, presence of names, broadcast everything else.
// Run on the host laptop: node relay.js [port]
const os = require('os');
const { WebSocketServer, WebSocket } = require('ws');

const PORT = parseInt(process.argv[2] || process.env.PORT || '8080', 10);

function lanIps() {
  const out = [];
  for (const [ifname, addrs] of Object.entries(os.networkInterfaces())) {
    for (const a of addrs || []) {
      if (a.family === 'IPv4' && !a.internal) out.push({ ifname, address: a.address });
    }
  }
  return out;
}

const wss = new WebSocketServer({ port: PORT });

function broadcast(msg, except) {
  const data = JSON.stringify(msg);
  for (const c of wss.clients) {
    if (c !== except && c.readyState === WebSocket.OPEN) c.send(data);
  }
}

function sendPeers() {
  const names = [...wss.clients].map((c) => c.name).filter(Boolean);
  broadcast({ type: 'peers', names });
}

wss.on('connection', (ws, req) => {
  ws.isAlive = true;
  ws.on('pong', () => { ws.isAlive = true; });
  const from = req.socket.remoteAddress;
  console.log(`+ connection from ${from}`);
  ws.send(JSON.stringify({ type: 'welcome', ips: lanIps().map((i) => i.address) }));

  ws.on('message', (raw) => {
    let msg;
    try { msg = JSON.parse(raw); } catch (_) { return; }
    if (msg.type === 'ping') {
      ws.send(JSON.stringify({ type: 'pong', t: msg.t }));
    } else if (msg.type === 'hello') {
      ws.name = String(msg.name || 'Editor').slice(0, 40);
      console.log(`  ${from} is "${ws.name}"`);
      sendPeers();
    } else {
      broadcast({ ...msg, from: ws.name }, ws);
    }
  });

  ws.on('close', () => {
    console.log(`- ${ws.name || from} left`);
    sendPeers();
  });
});

// Heartbeat: browser WebSockets auto-reply to pings; drop dead sockets and keep tunnels warm.
const hb = setInterval(() => {
  for (const ws of wss.clients) {
    if (!ws.isAlive) { ws.terminate(); continue; }
    ws.isAlive = false;
    ws.ping();
  }
}, 20000);
wss.on('close', () => clearInterval(hb));

wss.on('listening', () => {
  console.log(`Relay listening on port ${PORT}`);
  for (const i of lanIps()) console.log(`  Tell the guest: ws://${i.address}:${PORT}   (${i.ifname})`);
});

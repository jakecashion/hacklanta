// Room relay. Forwards each message to the other members of the sender's room. Reads no edits.
// First message from a client must be {t:'join', room, name}.
const os = require('os');
const { WebSocketServer } = require('ws');

function lanIps() {
  const out = [];
  for (const list of Object.values(os.networkInterfaces()))
    for (const i of list || []) if (i.family === 'IPv4' && !i.internal) out.push(i.address);
  return out;
}

function startRelay({ port = Number(process.env.PORT) || 8080, host = '0.0.0.0', pingMs = 20000 } = {}) {
  const wss = new WebSocketServer({ host, port, maxPayload: 1 << 20 });
  const rooms = new Map(); // room -> Set<ws>

  wss.on('connection', (ws) => {
    ws.isAlive = true;
    ws.room = null;
    ws.on('pong', () => { ws.isAlive = true; });
    ws.on('message', (data) => {
      let m;
      try { m = JSON.parse(data.toString()); } catch { return; }
      if (!ws.room) {
        if (m.t !== 'join' || typeof m.room !== 'string' || !m.room) return;
        ws.room = m.room; ws.name = String(m.name || '?');
        if (!rooms.has(ws.room)) rooms.set(ws.room, new Set());
        const peers = rooms.get(ws.room);
        ws.send(JSON.stringify({ t: 'joined', room: ws.room, peers: [...peers].map((p) => p.name), ips: lanIps() }));
        for (const p of peers) p.send(JSON.stringify({ t: 'peer', name: ws.name }));
        peers.add(ws);
        return;
      }
      for (const p of rooms.get(ws.room)) if (p !== ws && p.readyState === 1) p.send(data.toString());
    });
    ws.on('close', () => {
      const peers = rooms.get(ws.room);
      if (!peers) return;
      peers.delete(ws);
      for (const p of peers) p.send(JSON.stringify({ t: 'peer-left', name: ws.name }));
      if (!peers.size) rooms.delete(ws.room);
    });
  });

  const timer = setInterval(() => {
    for (const ws of wss.clients) {
      if (!ws.isAlive) { ws.terminate(); continue; }
      ws.isAlive = false; ws.ping();
    }
  }, pingMs);
  wss.on('close', () => clearInterval(timer));
  return wss;
}

module.exports = { startRelay, lanIps };

if (require.main === module) {
  const wss = startRelay();
  const port = wss.options.port;
  console.log('relay listening on port ' + port);
  for (const ip of lanIps()) console.log('  guest address: ws://' + ip + ':' + port);
}

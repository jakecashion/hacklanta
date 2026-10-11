// relay.js - relay and sequencer: ping/pong, names, and ops -> numbered commits.
// Run on the host laptop: node relay.js [port]
// Clients send {type:'op', opId, clipId, field, value}. The relay gives each op the next
// rev, keeps it in the log and sends {type:'commit', rev, op} to every client, sender included.
const os = require('os');
const { WebSocketServer, WebSocket } = require('ws');

const FIELDS = new Set(['Motion.Scale', 'Motion.Rotation', 'Opacity.Opacity']);
const CLIP_ID = /^v\d+:\d+$/;

function lanIps() {
  const out = [];
  for (const [ifname, addrs] of Object.entries(os.networkInterfaces())) {
    for (const a of addrs || []) {
      if (a.family === 'IPv4' && !a.internal) out.push({ ifname, address: a.address });
    }
  }
  return out;
}

function validOp(msg) {
  return typeof msg.opId === 'string' && CLIP_ID.test(msg.clipId) && FIELDS.has(msg.field) &&
    typeof msg.value === 'number' && Number.isFinite(msg.value);
}

// Latest committed entry per (clipId, field), ascending by rev. Keeps the { rev, op } shape.
function collapseLog(log) {
  const latest = new Map();
  for (const e of log) latest.set(e.op.clipId + '|' + e.op.field, e);
  return [...latest.values()].sort((x, y) => x.rev - y.rev);
}

function start(port, { quiet = false } = {}) {
  const say = quiet ? () => {} : console.log;
  const wss = new WebSocketServer({ port });
  let rev = 0;
  const opLog = []; // committed ops; Phase 3 snapshot join reads from here

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
    say(`+ connection from ${from}`);
    ws.send(JSON.stringify({ type: 'welcome', ips: lanIps().map((i) => i.address), rev }));
    // Join snapshot: latest committed value per (clip, field). Single-threaded, so every later
    // op gets a higher rev and reaches this socket after the catch-up.
    const commits = collapseLog(opLog);
    ws.send(JSON.stringify({ type: 'catchup', rev, commits }));
    say(`  catch-up: ${commits.length} change(s) at rev ${rev}`);

    ws.on('message', (raw) => {
      let msg;
      try { msg = JSON.parse(raw); } catch (_) { return; }
      if (msg.type === 'ping') {
        ws.send(JSON.stringify({ type: 'pong', t: msg.t }));
      } else if (msg.type === 'hello') {
        ws.name = String(msg.name || 'Editor').slice(0, 40);
        say(`  ${from} is "${ws.name}"`);
        sendPeers();
      } else if (msg.type === 'op') {
        if (!validOp(msg)) {
          ws.send(JSON.stringify({ type: 'error', err: 'bad op', op: msg }));
          return;
        }
        const op = { opId: msg.opId, author: ws.name || 'Editor', clipId: msg.clipId,
                     field: msg.field, value: msg.value };
        rev += 1;
        opLog.push({ rev, op });
        say(`  rev ${rev}: ${op.author} ${op.clipId} ${op.field} = ${op.value}`);
        broadcast({ type: 'commit', rev, op });
      } else {
        broadcast({ ...msg, from: ws.name }, ws);
      }
    });

    ws.on('close', () => {
      say(`- ${ws.name || from} left`);
      sendPeers();
    });
  });

  // Heartbeat: browser WebSockets auto-reply to pings; drop dead sockets.
  const hb = setInterval(() => {
    for (const ws of wss.clients) {
      if (!ws.isAlive) { ws.terminate(); continue; }
      ws.isAlive = false;
      ws.ping();
    }
  }, 20000);
  wss.on('close', () => clearInterval(hb));

  wss.on('listening', () => {
    say(`Relay listening on port ${port}`);
    for (const i of lanIps()) say(`  Tell the guest: ws://${i.address}:${port}   (${i.ifname})`);
  });

  return { wss, get rev() { return rev; }, opLog };
}

module.exports = { start, collapseLog };

if (require.main === module) {
  start(parseInt(process.argv[2] || process.env.PORT || '8080', 10));
}

const test = require('node:test'), assert = require('node:assert/strict');
const { Engine, Sequencer, same } = require('../panel/js/sync.js');

// Fake Premiere: stores values rounded to 2 decimals (like Premiere's float drift) and reports the rounded value.
class FakeBridge {
  constructor(init) { this.v = JSON.parse(JSON.stringify(init)); }
  userEdit(f, x) { this.v[f] = x; }
  snapshot() { return JSON.parse(JSON.stringify(this.v)); }
  apply(f, x) { this.v[f] = Array.isArray(x) ? x.map((n) => Math.round(n * 100) / 100) : Math.round(x * 100) / 100; return this.v[f]; }
}
const INIT = { 'v0:0.Opacity': 100, 'v0:0.Scale': 100, 'v0:0.Rotation': 0, 'v0:0.Position': [0.5, 0.5], 'v0:1.Opacity': 100 };

// Two clients + sequencer with per-link FIFO queues so tests control delivery order.
function rig(n = 2) {
  const toSeq = [], clients = [];
  const inbox = Array.from({ length: n }, () => []);
  const seq = new Sequencer((c) => inbox.forEach((q) => q.push(c)));
  for (let i = 0; i < n; i++) {
    const bridge = new FakeBridge(INIT);
    const eng = new Engine({ author: 'u' + i, bridge, send: (op) => toSeq.push(op) });
    eng.load(INIT);
    clients.push({ bridge, eng });
  }
  const scan = (i) => { const c = clients[i]; c.eng.tick(c.bridge.snapshot(), c.eng.scanToken()); };
  const upload = (k = Infinity) => { while (toSeq.length && k-- > 0) seq.submit(toSeq.shift()); };
  const deliver = (i, k = Infinity) => { while (inbox[i].length && k-- > 0) clients[i].eng.onCommit(inbox[i].shift()); };
  const drain = () => { for (let r = 0; r < 5; r++) { upload(); inbox.forEach((_, i) => deliver(i)); clients.forEach((_, i) => scan(i)); } };
  return { clients, scan, upload, deliver, drain, seq, toSeq, inbox };
}

test('edit on one side shows on the other', () => {
  const r = rig(); r.clients[0].bridge.userEdit('v0:0.Opacity', 40);
  r.scan(0); r.drain();
  assert.equal(r.clients[1].bridge.v['v0:0.Opacity'], 40);
});

test('no echo: after drain nothing is left to send, even with rounding on apply', () => {
  const r = rig(); r.clients[0].bridge.userEdit('v0:0.Scale', 133.3333);
  r.scan(0); r.drain();
  assert.equal(r.clients[1].bridge.v['v0:0.Scale'], 133.33); // rounded by fake Premiere
  r.scan(1); assert.equal(r.toSeq.length, 0, 'receiver must not re-send the rounded value');
  assert.equal(r.seq.rev, 1);
});

test('array field (Position) round trip, no echo', () => {
  const r = rig(); r.clients[1].bridge.userEdit('v0:0.Position', [0.6123, 0.4]);
  r.scan(1); r.drain();
  assert.ok(same(r.clients[0].bridge.v['v0:0.Position'], [0.61, 0.4]));
  assert.equal(r.seq.rev, 1);
});

test('same field at the same time: both converge on the later rev', () => {
  const r = rig();
  r.clients[0].bridge.userEdit('v0:0.Opacity', 10); r.clients[1].bridge.userEdit('v0:0.Opacity', 90);
  r.scan(0); r.scan(1);
  r.upload(); // toSeq order is u0 then u1, so u1 is the later rev and wins
  r.drain();
  assert.equal(r.clients[0].bridge.v['v0:0.Opacity'], 90);
  assert.equal(r.clients[1].bridge.v['v0:0.Opacity'], 90);
});

test('different fields and clips merge', () => {
  const r = rig();
  r.clients[0].bridge.userEdit('v0:0.Scale', 150); r.clients[1].bridge.userEdit('v0:1.Opacity', 20);
  r.scan(0); r.scan(1); r.drain();
  for (const c of r.clients) { assert.equal(c.bridge.v['v0:0.Scale'], 150); assert.equal(c.bridge.v['v0:1.Opacity'], 20); }
});

test('stale scan (started before a remote apply) is dropped, not sent as a revert', () => {
  const r = rig();
  const c1 = r.clients[1], token = c1.eng.scanToken(), staleSnap = c1.bridge.snapshot(); // scan starts
  r.clients[0].bridge.userEdit('v0:0.Rotation', 90); r.scan(0); r.upload(); r.deliver(1); // remote apply lands mid-scan
  assert.equal(c1.eng.tick(staleSnap, token), false);
  r.scan(1); assert.equal(r.toSeq.length, 0);
  r.drain(); assert.equal(c1.bridge.v['v0:0.Rotation'], 90);
});

test('rapid successive edits to one field: last one survives everywhere', () => {
  const r = rig();
  for (const x of [10, 20, 30]) { r.clients[0].bridge.userEdit('v0:0.Opacity', x); r.scan(0); }
  r.drain();
  assert.equal(r.clients[1].bridge.v['v0:0.Opacity'], 30); assert.equal(r.clients[0].bridge.v['v0:0.Opacity'], 30);
});

// fake Premiere rounds to 0.01, so the author's typed value and the receiver's stored value may differ by up to 0.005
const close = (x, y) => (Array.isArray(x) ? x.every((n, i) => close(n, y[i])) : Math.abs(x - y) <= 0.006);
test('fuzz: random edits and random delivery order always converge, nothing loops', () => {
  let seed = 12345; const rnd = () => (seed = (seed * 1664525 + 1013904223) >>> 0) / 2 ** 32;
  const fields = Object.keys(INIT);
  for (let round = 0; round < 300; round++) {
    const r = rig();
    for (let step = 0; step < 40; step++) {
      const i = Math.floor(rnd() * 2), a = rnd();
      if (a < 0.35) { const f = fields[Math.floor(rnd() * fields.length)]; r.clients[i].bridge.userEdit(f, Array.isArray(INIT[f]) ? [rnd(), rnd()] : Math.round(rnd() * 20000) / 100); }
      else if (a < 0.6) r.scan(i);
      else if (a < 0.8) r.upload(1 + Math.floor(rnd() * 2));
      else r.deliver(i, 1 + Math.floor(rnd() * 2));
    }
    r.drain();
    const [a, b] = r.clients;
    for (const f of fields) assert.ok(close(a.bridge.v[f], b.bridge.v[f]), `round ${round} ${f}: ${a.bridge.v[f]} vs ${b.bridge.v[f]}`);
    const revBefore = r.seq.rev; r.clients.forEach((_, i) => r.scan(i));
    assert.equal(r.toSeq.length, 0, 'quiescent after drain, no ping-pong'); assert.equal(r.seq.rev, revBefore);
  }
});

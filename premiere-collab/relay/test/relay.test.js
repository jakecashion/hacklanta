// End to end: real relay + two simulated editors running the real sync engine.
// Each fake "Premiere" rounds stored values to 0.1, like a real param might.
const test = require('node:test');
const assert = require('node:assert/strict');
const { WebSocket } = require('ws');
const { start } = require('../relay.js');
const { createSync } = require('../../panel/js/sync.js');

const round = (v) => Math.round(v * 10) / 10;
const wait = (ms) => new Promise((r) => setTimeout(r, ms));

function fakeEditor(url, name) {
  const timeline = { 'v0:0': { 'Motion.Scale': 100, 'Motion.Rotation': 0, 'Opacity.Opacity': 100 } };
  const scan = () => Object.entries(timeline).map(([id, p]) => ({ id, p: { ...p } }));
  const sync = createSync({ author: name });
  sync.reset(scan());
  const ws = new WebSocket(url);
  const ed = {
    name, timeline, sync, ws,
    edit(field, value) { timeline['v0:0'][field] = round(value); },
    poll() { for (const op of sync.diff(scan())) ws.send(JSON.stringify({ type: 'op', ...op })); },
    ready: new Promise((res) => ws.on('open', () => { ws.send(JSON.stringify({ type: 'hello', name })); res(); })),
  };
  ws.on('message', (raw) => {
    const msg = JSON.parse(raw);
    if (msg.type !== 'commit') return;
    const op = sync.receiveCommit(msg);
    if (op) {
      timeline[op.clipId][op.field] = round(op.value);
      sync.afterApply(op.clipId, op.field, timeline[op.clipId][op.field]);
    }
  });
  return ed;
}

async function setup(t) {
  const relay = start(0, { quiet: true });
  await new Promise((r) => relay.wss.on('listening', r));
  const url = `ws://localhost:${relay.wss.address().port}`;
  const a = fakeEditor(url, 'Host');
  const b = fakeEditor(url, 'Guest');
  await Promise.all([a.ready, b.ready]);
  t.after(() => { a.ws.close(); b.ws.close(); relay.wss.close(); });
  return { relay, a, b };
}

test('edits sync both ways and nothing echoes', async (t) => {
  const { relay, a, b } = await setup(t);

  a.edit('Motion.Scale', 150.04);
  a.poll();
  await wait(50);
  assert.equal(b.timeline['v0:0']['Motion.Scale'], 150);

  b.edit('Motion.Rotation', 45);
  b.poll();
  await wait(50);
  assert.equal(a.timeline['v0:0']['Motion.Rotation'], 45);

  const revAfterEdits = relay.rev;
  assert.equal(revAfterEdits, 2);
  for (let i = 0; i < 5; i++) { a.poll(); b.poll(); await wait(10); }
  assert.equal(relay.rev, revAfterEdits, 'rev must not climb after the edits (no echo)');
  assert.equal(a.sync.pendingCount, 0);
  assert.equal(b.sync.pendingCount, 0);
});

test('simultaneous edits to one field converge to the later rev', async (t) => {
  const { relay, a, b } = await setup(t);

  a.edit('Opacity.Opacity', 30);
  b.edit('Opacity.Opacity', 70);
  a.poll();
  b.poll(); // reaches the relay second, so it wins
  await wait(80);

  const last = relay.opLog[relay.opLog.length - 1].op.value;
  assert.equal(a.timeline['v0:0']['Opacity.Opacity'], last);
  assert.equal(b.timeline['v0:0']['Opacity.Opacity'], last);

  const rev = relay.rev;
  for (let i = 0; i < 5; i++) { a.poll(); b.poll(); await wait(10); }
  assert.equal(relay.rev, rev, 'no echo after the conflict');
});

test('relay rejects bad ops and sends commits to the sender too', async (t) => {
  const { relay, a } = await setup(t);
  const got = [];
  a.ws.on('message', (raw) => got.push(JSON.parse(raw)));

  a.ws.send(JSON.stringify({ type: 'op', opId: 'x', clipId: 'nope', field: 'Motion.Scale', value: 1 }));
  a.ws.send(JSON.stringify({ type: 'op', opId: 'x', clipId: 'v0:0', field: 'Position', value: 1 }));
  a.ws.send(JSON.stringify({ type: 'op', opId: 'y', clipId: 'v0:0', field: 'Motion.Scale', value: 120 }));
  await wait(50);

  assert.equal(got.filter((m) => m.type === 'error').length, 2);
  const commits = got.filter((m) => m.type === 'commit');
  assert.equal(commits.length, 1);
  assert.equal(commits[0].rev, 1);
  assert.equal(commits[0].op.author, 'Host');
  assert.equal(relay.rev, 1);
});

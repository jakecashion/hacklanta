// End to end: real relay + two simulated editors running the real sync engine.
// Each fake "Premiere" rounds stored values to 0.1, like a real param might.
const test = require('node:test');
const assert = require('node:assert/strict');
const { WebSocket } = require('ws');
const { start } = require('../relay.js');
const { createSync } = require('../../panel/js/sync.js');

const round = (v) => Math.round(v * 10) / 10;
const wait = (ms) => new Promise((r) => setTimeout(r, ms));

const pristine = () => ({ 'v0:0': { 'Motion.Scale': 100, 'Motion.Rotation': 0, 'Opacity.Opacity': 100 } });

// Optional third arg: a starting timeline (stands in for the same Premiere after a reconnect).
function fakeEditor(url, name, timeline = pristine()) {
  const scan = () => Object.entries(timeline).map(([id, p]) => ({ id, p: { ...p } }));
  const sync = createSync({ author: name });
  sync.reset(scan());
  const ws = new WebSocket(url);
  let gotCatchup;
  const ed = {
    name, timeline, sync, ws, msgs: [], applied: 0,
    edit(field, value) { timeline['v0:0'][field] = round(value); },
    poll() { for (const op of sync.diff(scan())) ws.send(JSON.stringify({ type: 'op', ...op })); },
    ready: new Promise((res) => ws.on('open', () => { ws.send(JSON.stringify({ type: 'hello', name })); res(); })),
    caughtUp: new Promise((res) => { gotCatchup = res; }),
  };
  const write = (op) => {
    timeline[op.clipId][op.field] = round(op.value);
    sync.afterApply(op.clipId, op.field, timeline[op.clipId][op.field]);
    ed.applied += 1;
  };
  ws.on('message', (raw) => {
    const msg = JSON.parse(raw);
    ed.msgs.push(msg);
    if (msg.type === 'catchup') {
      for (const op of sync.receiveCatchup(msg.commits)) write(op);
      gotCatchup(msg);
    } else if (msg.type === 'commit') {
      const op = sync.receiveCommit(msg);
      if (op) write(op);
    }
  });
  return ed;
}

async function startRelay(t) {
  const relay = start(0, { quiet: true });
  await new Promise((r) => relay.wss.on('listening', r));
  t.after(() => relay.wss.close());
  return { relay, url: `ws://localhost:${relay.wss.address().port}` };
}

async function setup(t) {
  const { relay, url } = await startRelay(t);
  const a = fakeEditor(url, 'Host');
  const b = fakeEditor(url, 'Guest');
  await Promise.all([a.ready, b.ready]);
  t.after(() => { a.ws.close(); b.ws.close(); });
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
  a.ws.send(JSON.stringify({ type: 'op', opId: 'x', clipId: 'v0:0', field: 'Clip.name', value: 5 }));
  a.ws.send(JSON.stringify({ type: 'op', opId: 'x', clipId: 'v0:0', field: 'Clip.name', value: '' }));
  a.ws.send(JSON.stringify({ type: 'op', opId: 'x', clipId: 'v0:0', field: 'Motion.Scale', value: '120' }));
  a.ws.send(JSON.stringify({ type: 'op', opId: 'y', clipId: 'v0:0', field: 'Motion.Scale', value: 120 }));
  a.ws.send(JSON.stringify({ type: 'op', opId: 'z', clipId: 'v0:0', field: 'Clip.name', value: 'Opening' }));
  await wait(50);

  assert.equal(got.filter((m) => m.type === 'error').length, 5);
  const commits = got.filter((m) => m.type === 'commit');
  assert.equal(commits.length, 2);
  assert.equal(commits[1].op.value, 'Opening');
  assert.equal(commits[0].rev, 1);
  assert.equal(commits[0].op.author, 'Host');
  assert.equal(relay.rev, 2);
});

test("a late joiner catches up to the host's edits and nothing echoes", async (t) => {
  const { relay, url } = await startRelay(t);
  const host = fakeEditor(url, 'Host');
  await host.ready;
  t.after(() => host.ws.close());

  host.edit('Motion.Scale', 150);
  host.poll();
  await wait(50);
  host.edit('Motion.Scale', 160);
  host.edit('Motion.Rotation', 45);
  host.poll();
  await wait(50);
  assert.equal(relay.rev, 3);

  const guest = fakeEditor(url, 'Guest');
  t.after(() => guest.ws.close());
  const cu = await guest.caughtUp;
  assert.equal(cu.rev, relay.rev);
  assert.equal(cu.commits.length, 2);
  assert.deepEqual(cu.commits.map((c) => c.rev), [2, 3]);
  assert.deepEqual(guest.timeline['v0:0'], host.timeline['v0:0']);
  assert.equal(guest.timeline['v0:0']['Motion.Scale'], 160);
  assert.equal(guest.sync.lastRev, 3);

  for (let i = 0; i < 5; i++) { host.poll(); guest.poll(); await wait(10); }
  assert.equal(relay.rev, 3, 'rev must not climb after the join (no echo)');
  assert.equal(guest.sync.pendingCount, 0);
});

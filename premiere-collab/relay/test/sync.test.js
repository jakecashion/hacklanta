const test = require('node:test');
const assert = require('node:assert/strict');
const { createSync } = require('../../panel/js/sync.js');

const clip = (id, s, r, o) => ({ id, p: { 'Motion.Scale': s, 'Motion.Rotation': r, 'Opacity.Opacity': o } });

test('no ops when the scan matches the baseline', () => {
  const s = createSync();
  s.reset([clip('000f4242', 100, 0, 100)]);
  assert.deepEqual(s.diff([clip('000f4242', 100, 0, 100)]), []);
});

test('a local edit becomes one op, once', () => {
  const s = createSync({ author: 'Sam' });
  s.reset([clip('000f4242', 100, 0, 100)]);
  const ops = s.diff([clip('000f4242', 150, 0, 100)]);
  assert.equal(ops.length, 1);
  assert.equal(ops[0].field, 'Motion.Scale');
  assert.equal(ops[0].value, 150);
  assert.equal(ops[0].author, 'Sam');
  assert.equal(s.pendingCount, 1);
  assert.deepEqual(s.diff([clip('000f4242', 150, 0, 100)]), []);
});

test('changes within epsilon are ignored', () => {
  const s = createSync({ epsilon: 0.05 });
  s.reset([clip('000f4242', 100, 0, 100)]);
  assert.deepEqual(s.diff([clip('000f4242', 100.04, 0.01, 99.99)]), []);
});

test('own commit clears pending and is not applied', () => {
  const s = createSync();
  s.reset([clip('000f4242', 100, 0, 100)]);
  const [op] = s.diff([clip('000f4242', 150, 0, 100)]);
  assert.equal(s.ownsOp(op.opId), true);
  assert.equal(s.receiveCommit({ rev: 1, op }), null);
  assert.equal(s.pendingCount, 0);
  assert.equal(s.lastRev, 1);
});

test('remote commit is applied; Premiere rounding does not echo back', () => {
  const s = createSync();
  s.reset([clip('000f4242', 100, 0, 100)]);
  const remote = { opId: 'other-1', author: 'Alex', clipId: '000f4242', field: 'Motion.Rotation', value: 33.333333 };
  const toApply = s.receiveCommit({ rev: 1, op: remote });
  assert.deepEqual(toApply, remote);
  assert.equal(s.ownsOp(remote.opId), false);
  s.afterApply('000f4242', 'Motion.Rotation', 33.3); // Premiere stored a rounded value
  assert.deepEqual(s.diff([clip('000f4242', 100, 33.3, 100)]), []);
});

test('a failed apply does not send the old value back', () => {
  const s = createSync();
  s.reset([clip('000f4242', 100, 0, 100)]);
  const remote = { opId: 'other-1', author: 'Alex', clipId: '000f4242', field: 'Motion.Scale', value: 175 };
  assert.deepEqual(s.receiveCommit({ rev: 1, op: remote }), remote);
  // Apply failed (e.g. no active sequence), so afterApply is never called.
  assert.deepEqual(s.diff([clip('000f4242', 100, 0, 100)]), [], 'unchanged timeline is not a local edit');
  assert.equal(s.shadowValue('000f4242', 'Motion.Scale'), 100);
});

test('conflict: a pending local edit beats an earlier remote commit', () => {
  const s = createSync();
  s.reset([clip('000f4242', 100, 0, 100)]);
  const [mine] = s.diff([clip('000f4242', 100, 0, 40)]);
  const theirs = { opId: 'other-1', author: 'Alex', clipId: '000f4242', field: 'Opacity.Opacity', value: 70 };
  assert.equal(s.receiveCommit({ rev: 1, op: theirs }), null, 'remote skipped while ours is pending');
  assert.equal(s.receiveCommit({ rev: 2, op: mine }), null);
  assert.equal(s.shadowValue('000f4242', 'Opacity.Opacity'), 40);
  assert.equal(s.pendingCount, 0);
});

test('a stale own commit does not clear a newer pending edit', () => {
  const s = createSync();
  s.reset([clip('000f4242', 100, 0, 100)]);
  const [first] = s.diff([clip('000f4242', 120, 0, 100)]);
  s.diff([clip('000f4242', 140, 0, 100)]);
  assert.equal(s.receiveCommit({ rev: 1, op: first }), null);
  assert.equal(s.pendingCount, 1, 'second edit still pending');
});

test('duplicate or old revs are ignored', () => {
  const s = createSync();
  s.reset([clip('000f4242', 100, 0, 100)]);
  const op = { opId: 'x-1', author: 'A', clipId: '000f4242', field: 'Motion.Scale', value: 110 };
  assert.ok(s.receiveCommit({ rev: 5, op }));
  assert.equal(s.receiveCommit({ rev: 5, op }), null);
  assert.equal(s.receiveCommit({ rev: 3, op: { ...op, value: 90 } }), null);
});

test('a clip that appears later is baselined, not sent', () => {
  const s = createSync();
  s.reset([clip('000f4242', 100, 0, 100)]);
  assert.deepEqual(s.diff([clip('000f4242', 100, 0, 100), clip('000f4243', 80, 10, 50)]), []);
});

test('Position and Anchor Point: a 1-pixel move is an op, float noise is not', () => {
  const s = createSync();
  const pos = (x, y) => ({ id: '000f4242', p: { 'Motion.Position.x': x, 'Motion.Position.y': y, 'Motion.AnchorPoint.x': 0.40625 } });
  s.reset([pos(0.375, 0.44444444775581)]);
  assert.deepEqual(s.diff([pos(0.375 + 1e-9, 0.44444444775581)]), []);
  const ops = s.diff([pos(0.375 + 1 / 640, 0.44444444775581)]);
  assert.equal(ops.length, 1);
  assert.equal(ops[0].field, 'Motion.Position.x');
  // Scale keeps the coarse default epsilon.
  const t = createSync();
  t.reset([clip('000f4242', 100, 0, 100)]);
  assert.deepEqual(t.diff([clip('000f4242', 100.01, 0, 100)]), []);
});

test('Clip.name: a rename is one op, exact string compare, remote rename applies once', () => {
  const s = createSync();
  const named = (n) => ({ id: '000f4242', p: { 'Motion.Scale': 100, 'Clip.name': n } });
  s.reset([named('Intro')]);
  assert.deepEqual(s.diff([named('Intro')]), []);
  const ops = s.diff([named('Intro ')]); // one trailing space is a real rename
  assert.equal(ops.length, 1);
  assert.equal(ops[0].field, 'Clip.name');
  assert.equal(ops[0].value, 'Intro ');
  assert.equal(s.receiveCommit({ rev: 1, op: ops[0] }), null);

  const remote = { opId: 'other-1', author: 'Alex', clipId: '000f4242', field: 'Clip.name', value: 'Opening' };
  assert.deepEqual(s.receiveCommit({ rev: 2, op: remote }), remote);
  s.afterApply('000f4242', 'Clip.name', 'Opening');
  assert.deepEqual(s.diff([named('Opening')]), [], 'applied rename does not echo');
  // Catch-up skips a name the timeline already has.
  const t = createSync();
  t.reset([named('Opening')]);
  assert.deepEqual(t.receiveCatchup([{ rev: 2, op: remote }]), []);
});

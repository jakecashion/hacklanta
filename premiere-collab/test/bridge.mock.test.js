// Logic-only test of bridge.jsx against a MOCK of the Premiere object model. Proves nothing about the real API.
const test = require('node:test'), assert = require('node:assert/strict'), vm = require('node:vm'), fs = require('node:fs');
function param(name, v) { return { displayName: name, v, getValue() { return this.v; }, setValue(x) { this.v = x; return true; }, isTimeVarying() { return false; } }; }
function ctx() {
  const clip = { name: 'Hero', nodeId: 'n1', start: { ticks: '0' }, end: { ticks: '508032000000' }, inPoint: { ticks: '0' }, outPoint: { ticks: '508032000000' },
    components: [{ displayName: 'Motion', matchName: 'AE.ADBE Motion', properties: [param('Position', [0.5, 0.5]), param('Scale', 100), param('Rotation', 0)] },
                 { displayName: 'Opacity', matchName: 'AE.ADBE Opacity', properties: [param('Opacity', 100)] }] };
  const seq = { name: 'S', videoTracks: [{ clips: [clip] }], getSelection: () => [clip], getPlayerPosition: () => ({ ticks: '5' }) };
  const sandbox = { app: { version: '22.3.1', build: '1', project: { name: 'p', path: 'x', activeSequence: seq }, bind: () => true },
    $: { global: {}, os: 'Win' }, Time: function () {}, File: function () {}, Folder: {} };
  vm.createContext(sandbox);
  vm.runInContext(fs.readFileSync(__dirname + '/../panel/jsx/bridge.jsx', 'utf8'), sandbox);
  return sandbox;
}
test('roundTrip + dump + setParam + events produce parseable JSON', () => {
  const s = ctx();
  const rt = JSON.parse(s.collabRoundTrip(0, 0));
  assert.ok(rt.ok); assert.equal(rt.data.length, 4);
  assert.ok(rt.data.every((f) => f.changed && f.restored), JSON.stringify(rt.data));
  const d = JSON.parse(s.collabDump()); assert.equal(d.data[0].comps[1].props[0].value, 100);
  const sp = JSON.parse(s.collabSetParam(0, 0, 'Opacity', 'Opacity', '42')); assert.equal(sp.data.after, 42);
  assert.equal(JSON.parse(s.collabSetParam(0, 0, 'Nope', 'x', '1')).ok, false);
  assert.ok(JSON.parse(s.collabBind()).ok);
  assert.deepEqual(JSON.parse(s.collabPresence()).data.selected, ['n1']);
});

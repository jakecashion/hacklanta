const test = require('node:test');
const assert = require('node:assert/strict');
const WebSocket = require('../relay/node_modules/ws');
const { startRelay, lanIps } = require('../relay/relay.js');

const open = (url) => new Promise((res) => { const w = new WebSocket(url); w.msgs = []; w.on('message', (d) => w.msgs.push(JSON.parse(d.toString()))); w.on('open', () => res(w)); });
const until = async (f) => { for (let i = 0; i < 100; i++) { if (f()) return; await new Promise((r) => setTimeout(r, 20)); } throw new Error('timeout'); };

async function roundTrip(url) {
  const a = await open(url), b = await open(url);
  a.send(JSON.stringify({ t: 'join', room: 'R1', name: 'A' }));
  await until(() => a.msgs.some((m) => m.t === 'joined'));
  b.send(JSON.stringify({ t: 'join', room: 'R1', name: 'B' }));
  await until(() => b.msgs.some((m) => m.t === 'joined'));
  await until(() => a.msgs.some((m) => m.t === 'peer' && m.name === 'B'));
  const t0 = Date.now();
  a.send(JSON.stringify({ t: 'apply', id: 1, field: 'opacity', value: 40 }));
  await until(() => b.msgs.some((m) => m.t === 'apply'));
  b.send(JSON.stringify({ t: 'applied', id: 1, after: 40 }));
  await until(() => a.msgs.some((m) => m.t === 'applied'));
  const ms = Date.now() - t0;
  assert.ok(!a.msgs.some((m) => m.t === 'apply'), 'sender must not get its own message');
  a.close(); b.close();
  return ms;
}

test('two clients exchange messages both ways, no self-echo', async () => {
  const wss = startRelay({ port: 0, host: '127.0.0.1' });
  await new Promise((r) => wss.on('listening', r));
  const ms = await roundTrip('ws://127.0.0.1:' + wss.address().port);
  console.log('localhost round trip ms', ms);
  wss.close();
});

test('reachable on the LAN address (what the guest laptop will use)', async (t) => {
  const ips = lanIps();
  if (!ips.length) return t.skip('no LAN IPv4');
  const wss = startRelay({ port: 0 });
  await new Promise((r) => wss.on('listening', r));
  const ms = await roundTrip('ws://' + ips[0] + ':' + wss.address().port);
  console.log('LAN round trip ms', ms, 'via', ips[0]);
  wss.close();
});

test('rooms are isolated and non-join first message is ignored', async () => {
  const wss = startRelay({ port: 0, host: '127.0.0.1' });
  await new Promise((r) => wss.on('listening', r));
  const url = 'ws://127.0.0.1:' + wss.address().port;
  const a = await open(url), b = await open(url), c = await open(url);
  a.send(JSON.stringify({ t: 'join', room: 'X', name: 'A' }));
  b.send(JSON.stringify({ t: 'join', room: 'Y', name: 'B' }));
  c.send(JSON.stringify({ t: 'apply', room: 'X' })); // never joined
  await until(() => a.msgs.length && b.msgs.length);
  a.send(JSON.stringify({ t: 'apply' }));
  await new Promise((r) => setTimeout(r, 150));
  assert.ok(!b.msgs.some((m) => m.t === 'apply'));
  a.close(); b.close(); c.close(); wss.close();
});

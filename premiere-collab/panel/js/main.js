// Panel JS (Chromium 88). Phase 1: bridge + kill test buttons. Phase 2: live sync of
// Scale, Rotation and Opacity through the relay (see sync.js for the rules).
const cs = new CSInterface();
const $ = (id) => document.getElementById(id);
const logEl = $('log');

function log(msg, obj) {
  const t = new Date().toLocaleTimeString();
  const line = obj === undefined ? msg : msg + ' ' + JSON.stringify(obj, null, 2);
  logEl.textContent = `[${t}] ${line}\n` + logEl.textContent;
  saveLog();
}

// Mirror the log to panel/panel-log.txt (newest first) so it can be read without copy/paste.
const logPath = cs.getSystemPath(SystemPath.EXTENSION) + '/panel-log.txt';
function saveLog() {
  try { window.cep.fs.writeFile(logPath, logEl.textContent); } catch (e) { /* no-op */ }
}

// ---------- ExtendScript bridge ----------
function jsx(code) {
  return new Promise((resolve) => {
    cs.evalScript(code, (res) => {
      if (res === 'EvalScript error.') return resolve({ ok: false, err: res });
      try { resolve(JSON.parse(res)); } catch (e) { resolve({ ok: false, raw: res }); }
    });
  });
}

function loadBridge() {
  const root = cs.getSystemPath(SystemPath.EXTENSION).replace(/\\/g, '/');
  const code =
    `$.evalFile("${root}/jsx/json2.js"); $.evalFile("${root}/jsx/bridge.jsx");`;
  cs.evalScript(code, (res) => log('Bridge: ' + res));
}

const clipIdx = () => parseInt($('clipIdx').value, 10) || 0;

$('jsxPing').onclick = async () => log('pc_ping', await jsx('pc_ping()'));
$('list').onclick = async () => log('pc_listClips', await jsx('pc_listClips(0)'));
$('kill').onclick = async () => log('pc_killTest', await jsx(`pc_killTest(0, ${clipIdx()})`));
$('reset').onclick = async () => log('pc_resetClip', await jsx(`pc_resetClip(0, ${clipIdx()})`));
$('scan').onclick = async () => log('pc_scanCost', await jsx('pc_scanCost(0)'));
$('set').onclick = async () => {
  const field = $('field').value;
  const value = parseFloat($('value').value);
  log('pc_setParam', await jsx(`pc_setParam(0, ${clipIdx()}, "${field}", ${value})`));
};

// ---------- Sync ----------
// All Premiere work (scan, apply) runs through one queue, so a scan never interleaves
// with an apply and reads a half-updated timeline.
let chain = Promise.resolve();
const enqueue = (fn) => (chain = chain.then(fn).catch((e) => log('Sync error: ' + e)));

let sync = null;          // PCSync instance while connected
let clipNames = {};       // clipId -> clip name, from the last scan
let polling = false;      // a poll is queued or running
let lastScanErr = '';

const FIELD_LABEL = {
  'Motion.Scale': 'Scale', 'Motion.Rotation': 'Rotation', 'Opacity.Opacity': 'Opacity',
  'Motion.Position.x': 'Position X', 'Motion.Position.y': 'Position Y',
  'Motion.AnchorPoint.x': 'Anchor Point X', 'Motion.AnchorPoint.y': 'Anchor Point Y',
  'Clip.name': 'Name', 'Clip.timing': 'Timing',
};
// Position/Anchor Point values are fractions of the frame, so keep 3 decimals for those.
const TICKS_PER_SECOND = 254016000000; // Premiere ticks
const fmt = (v) => (typeof v === 'string' ? `"${v}"`
  : Math.abs(v) < 2 ? Math.round(v * 1000) / 1000 : Math.round(v * 100) / 100);

// Feed text for a Clip.timing op. prev is the shadow before the op (equal to next for our own op).
function timingText(clip, prev, next) {
  const [s, e, i] = next.split(':').map(Number);
  const sec = (t) => fmt(t / TICKS_PER_SECOND);
  const p = typeof prev === 'string' ? prev.split(':').map(Number) : null;
  if (p && p[0] !== s && p[1] - p[0] === e - s && p[2] === i) return `moved ${clip} to ${sec(s)} s`;
  if (p && p.join(':') !== next) return `trimmed ${clip} to ${sec(s)}-${sec(e)} s (in ${sec(i)} s)`;
  return `set ${clip} to ${sec(s)}-${sec(e)} s (in ${sec(i)} s)`;
}

function feed(text) {
  const li = document.createElement('li');
  li.textContent = text;
  const ul = $('feed');
  ul.insertBefore(li, ul.firstChild);
  while (ul.children.length > 30) ul.removeChild(ul.lastChild);
  log(text);
}

function showSyncStatus() {
  $('syncStatus').textContent = sync
    ? `Syncing: rev ${sync.lastRev}, ${sync.pendingCount} pending`
    : 'Sync off';
}

async function scan() {
  const res = await jsx('pc_scan(0)');
  if (!res.ok) {
    const err = res.err || res.raw || 'scan failed';
    if (err !== lastScanErr) log('Scan error: ' + err);
    lastScanErr = err;
    return null;
  }
  lastScanErr = '';
  clipNames = {};
  for (const c of res.clips) clipNames[c.id] = c.name;
  return res.clips;
}

// Called once per connection: the current timeline is the baseline, nothing is sent.
function startSync(author) {
  enqueue(async () => {
    const clips = await scan();
    sync = PCSync.createSync({ author });
    sync.reset(clips || []);
    log(`Sync started: ${clips ? clips.length : 0} clips on V1`);
    showSyncStatus();
  });
}

function stopSync() {
  sync = null;
  showSyncStatus();
}

function pollOnce() {
  if (!sync || polling) return;
  polling = true;
  enqueue(async () => {
    try {
      if (!sync) return;
      const clips = await scan();
      if (!clips || !sync) return; // sync may have stopped while the scan ran
      for (const op of sync.diff(clips)) send({ type: 'op', ...op });
      showSyncStatus();
    } finally {
      polling = false;
    }
  });
}

function onCommit(msg) {
  enqueue(async () => {
    if (!sync) return;
    const { op } = msg;
    const who = sync.ownsOp(op.opId) ? 'You' : op.author;
    const clip = clipNames[op.clipId] || op.clipId;
    if (op.field === 'Clip.name') {
      // Own rename: the last scan already holds the new name, so name the clip by its ID.
      const from = clip !== op.value ? clip : op.clipId;
      feed(`${who} renamed ${from} to ${fmt(op.value)} (rev ${msg.rev})`);
    } else if (op.field === 'Clip.timing') {
      feed(`${who} ${timingText(clip, sync.shadowValue(op.clipId, op.field), op.value)} (rev ${msg.rev})`);
    } else {
      feed(`${who} set ${clip} ${FIELD_LABEL[op.field] || op.field} to ${fmt(op.value)} (rev ${msg.rev})`);
    }
    const toApply = sync.receiveCommit(msg);
    if (toApply) await applyOps([toApply]);
    showSyncStatus();
  });
}

async function applyOps(ops) {
  const res = await jsx(`pc_applyOps(${JSON.stringify(JSON.stringify(ops))})`);
  if (!res.ok) log('Apply error', res);
  if (!sync) return; // disconnected while applying
  for (const r of res.results || []) {
    if (r.ok) sync.afterApply(r.clipId, r.field, r.after);
    else log('Apply failed', r);
  }
}

// Join snapshot: runs after startSync's baseline (same queue). One feed line, details to the log.
function onCatchup(msg) {
  enqueue(async () => {
    if (!sync) return;
    const ops = sync.receiveCatchup(msg.commits || []);
    for (const op of ops) {
      log(`Catch-up: ${op.author} ${clipNames[op.clipId] || op.clipId} ${FIELD_LABEL[op.field] || op.field} = ${fmt(op.value)}`);
    }
    if (ops.length) await applyOps(ops);
    feed(`Caught up to rev ${msg.rev} (${ops.length} change${ops.length === 1 ? '' : 's'} applied)`);
    showSyncStatus();
  });
}

setInterval(pollOnce, 1000);

// ---------- Relay ----------
let ws = null;

function setBadge(state, text) {
  const b = $('badge');
  b.className = 'badge ' + state;
  b.textContent = text;
}

function send(msg) {
  if (ws && ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(msg));
  else log('Not connected');
}

// Accept a bare IP ("100.101.102.103") or a full ws:// / wss:// URL.
function relayUrl(text) {
  if (/^wss?:\/\//.test(text)) return text;
  return `ws://${text}${/:\d+$/.test(text) ? '' : ':8080'}`;
}

$('connect').onclick = () => {
  const host = $('url').value.trim();
  if (!host || /\s/.test(host)) {
    log(`Host IP "${host}" is not valid: type only the IP (e.g. 100.101.102.103 or localhost), and your name in Name`);
    return;
  }
  if (ws) ws.close();
  const url = relayUrl(host);
  const name = $('name').value.trim() || 'Editor';
  setBadge('wait', 'Connecting…');
  log('Connecting to ' + url);
  const sock = new WebSocket(url);
  ws = sock;
  sock.onopen = () => {
    setBadge('on', 'Connected as ' + name);
    send({ type: 'hello', name });
    startSync(name);
  };
  sock.onclose = (e) => {
    if (ws !== sock) return; // an older socket closing after a reconnect
    stopSync();
    setBadge('off', 'Not connected');
    $('peers').textContent = 'No peers';
    log(`Socket closed (code ${e.code})`);
  };
  sock.onerror = () => log('Socket error (check IP, relay running, firewall)');
  sock.onmessage = (e) => {
    let msg;
    try { msg = JSON.parse(e.data); } catch (_) { return log('Bad message: ' + e.data); }
    if (msg.type === 'commit') {
      onCommit(msg);
    } else if (msg.type === 'catchup') {
      onCatchup(msg);
    } else if (msg.type === 'cursor') {
      // 20 Hz pointer traffic from cursor.ps1; the helper draws it, the panel ignores it.
    } else if (msg.type === 'pong') {
      log(`Pong from relay: round trip ${Date.now() - msg.t} ms`);
    } else if (msg.type === 'welcome') {
      log(`Relay says hi (rev ${msg.rev}). Host IPs:`, msg.ips);
    } else if (msg.type === 'peers') {
      $('peers').textContent = msg.names.length ? 'Here: ' + msg.names.join(', ') : 'No peers';
    } else if (msg.type === 'error') {
      log('Relay error', msg);
    } else {
      log('Message', msg);
    }
  };
};

$('disconnect').onclick = () => { if (ws) ws.close(); };
$('pingRelay').onclick = () => send({ type: 'ping', t: Date.now() });

// ---------- Misc ----------
$('clear').onclick = () => { logEl.textContent = ''; saveLog(); };
$('reload').onclick = () => location.reload();

loadBridge();
showSyncStatus();

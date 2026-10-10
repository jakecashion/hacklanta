// Panel JS (Chromium 88). Phase 1: load bridge, kill test buttons, relay connect + ping.
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

$('connect').onclick = () => {
  if (ws) ws.close();
  const url = $('url').value.trim();
  const name = $('name').value.trim() || 'Editor';
  setBadge('wait', 'Connecting…');
  log('Connecting to ' + url);
  ws = new WebSocket(url);
  ws.onopen = () => {
    setBadge('on', 'Connected');
    send({ type: 'hello', name });
  };
  ws.onclose = (e) => {
    setBadge('off', 'Not connected');
    $('peers').textContent = 'No peers';
    log(`Socket closed (code ${e.code})`);
  };
  ws.onerror = () => log('Socket error (check IP, relay running, firewall)');
  ws.onmessage = (e) => {
    let msg;
    try { msg = JSON.parse(e.data); } catch (_) { return log('Bad message: ' + e.data); }
    if (msg.type === 'pong') {
      log(`Pong from relay: round trip ${Date.now() - msg.t} ms`);
    } else if (msg.type === 'welcome') {
      log('Relay says hi. Host IPs:', msg.ips);
    } else if (msg.type === 'peers') {
      $('peers').textContent = msg.names.length ? 'Here: ' + msg.names.join(', ') : 'No peers';
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

(function () {
  var $ = function (id) { return document.getElementById(id); };
  var R = { machine: '', checks: {}, data: {}, remote: { sentOk: false, receivedOk: false } };
  var CHECKS = [
    ['c1', '1 Panel loads, bridge responds'],
    ['c2', '2 Panel reaches relay; message crosses machines'],
    ['c3', '3 nodeId stable after move/trim'],
    ['c4', '4 start/end move and inPoint/outPoint trim (stretch)'],
    ['c5', '5 Events fire for move, trim, param change'],
    ['c6', '6 setValue changes value, read-back ok, monitor updates (KILL GATE)'],
    ['c7', '7 Remote apply: peer message changes my timeline, acked']
  ];

  function log(s) { var l = $('log'); l.textContent += s + '\n'; l.scrollTop = l.scrollHeight; }
  function mark(id, v, note) { R.checks[id] = { v: v, note: note || '' }; draw(); }
  function draw() {
    var h = '';
    CHECKS.forEach(function (c) {
      var r = R.checks[c[0]] || { v: 'TODO', note: '' };
      h += '<tr><td>' + c[1] + '</td><td class="' + r.v + '">' + r.v + '</td><td>' + r.note + '</td></tr>';
    });
    $('checks').innerHTML = h;
  }
  function show(name, r) { log('== ' + name + '\n' + JSON.stringify(r, null, 1)); R.data[name] = r; }

  // ---- 1 env ----
  $('bEnv').onclick = function () {
    cep.call('collabPing').then(function (r) {
      if (!r.ok) return mark('c1', 'FAIL', r.err);
      return cep.call('collabEnv').then(function (e) { show('env', e); R.machine = e.ok ? e.data.project : ''; mark('c1', e.ok ? 'PASS' : 'FAIL', e.ok ? 'v' + e.data.version : e.err); });
    });
  };
  $('bDump').onclick = function () { cep.call('collabDump').then(function (r) { show('dump', r); }); };
  $('bRound').onclick = function () {
    cep.call('collabRoundTrip', 0, 0).then(function (r) {
      show('roundTrip', r);
      if (!r.ok) return mark('c6', 'FAIL', r.err);
      var bad = r.data.filter(function (f) { return f.err || !f.changed || !f.restored; });
      mark('c6', bad.length ? 'FAIL' : 'TODO', bad.length ? bad.map(function (f) { return f.field; }).join(',') + ' failed' : 'values ok; confirm monitor with YES/NO');
    });
  };
  $('bVisYes').onclick = function () { var c = R.checks.c6; if (c && c.v !== 'FAIL') mark('c6', 'PASS', 'monitor confirmed'); R.data.monitor = 'yes'; };
  $('bVisNo').onclick = function () { mark('c6', 'FAIL', 'monitor did not update'); R.data.monitor = 'no'; };
  $('bMove').onclick = function () {
    cep.call('collabMoveTrim', 0, 0).then(function (r) {
      show('moveTrim', r);
      var ok = r.ok && r.data.moveWorked && r.data.trimWorked && r.data.restoredOk;
      mark('c4', ok ? 'PASS' : 'FAIL', r.ok ? ('move ' + r.data.moveWorked + ' trim ' + r.data.trimWorked) : r.err);
    });
  };
  $('bScan').onclick = function () { cep.call('collabScan', 20).then(function (r) { show('scan', r); }); };

  // ---- 3 ids ----
  var recorded = null;
  $('bIdRec').onclick = function () { cep.call('collabIds').then(function (r) { recorded = r.data; show('ids-recorded', r); }); };
  $('bIdCmp').onclick = function () {
    cep.call('collabIds').then(function (r) {
      if (!recorded || !r.ok) return log('record first');
      var diffs = [];
      recorded.forEach(function (a, i) { var b = r.data[i]; if (!b || a.nodeId !== b.nodeId) diffs.push(a.name + ': ' + a.nodeId + ' -> ' + (b && b.nodeId)); });
      show('ids-compare', { diffs: diffs, now: r.data });
      mark('c3', diffs.length ? 'FAIL' : 'PASS', diffs.length ? diffs.length + ' changed' : 'stable');
    });
  };

  // ---- 5 events ----
  $('bBind').onclick = function () { cep.call('collabBind').then(function (r) { show('bind', r); cep.call('collabEventsReset'); }); };
  var evSeen = {};
  function evStep(label) {
    cep.call('collabEvents').then(function (r) {
      show('events-' + label, r);
      var structure = (r.data.counts.onActiveSequenceStructureChanged || 0) > 0;
      evSeen[label] = structure;
      var done = ['move', 'trim', 'param'].every(function (k) { return k in evSeen; });
      if (done) {
        var all = evSeen.move && evSeen.trim && evSeen.param;
        mark('c5', all ? 'PASS' : 'FAIL', 'structure event: move ' + evSeen.move + ', trim ' + evSeen.trim + ', param ' + evSeen.param + (all ? '' : ' (use timer polling only)'));
      }
      cep.call('collabEventsReset');
    });
  }
  $('bEvMove').onclick = function () { evStep('move'); };
  $('bEvTrim').onclick = function () { evStep('trim'); };
  $('bEvParam').onclick = function () { evStep('param'); };
  $('bEvSel').onclick = function () { evStep('selection'); };
  $('bPresence').onclick = function () { cep.call('collabPresence').then(function (r) { show('presence', r); }); };

  // ---- 4 relay ----
  var ws = null;
  var pending = {};
  var FIELDS = { opacity: ['Opacity', 'Opacity'], scale: ['Motion', 'Scale'], rotation: ['Motion', 'Rotation'] };
  function send(o) { if (ws && ws.readyState === 1) ws.send(JSON.stringify(o)); }
  $('bConn').onclick = function () {
    if (ws) ws.close();
    ws = new WebSocket($('relayUrl').value);
    var name = $('who').value || ('m' + Math.floor(Math.random() * 1000));
    ws.onopen = function () { send({ t: 'join', room: $('room').value, name: name }); log('ws open'); };
    ws.onerror = function () { mark('c2', 'FAIL', 'websocket error'); };
    ws.onclose = function () { $('peerState').textContent = 'closed'; };
    ws.onmessage = function (e) {
      var m = JSON.parse(e.data);
      if (m.t === 'joined') { $('peerState').textContent = 'in room, peers: ' + m.peers.join(',') + ' | relay IPs ' + m.ips.join(','); mark('c2', 'TODO', 'connected; send a message to peer'); }
      else if (m.t === 'peer') $('peerState').textContent = 'peer joined: ' + m.name;
      else if (m.t === 'apply') applyRemote(m);
      else if (m.t === 'applied') gotAck(m);
    };
  };
  $('bSend').onclick = function () {
    var id = 'm' + Date.now();
    pending[id] = Date.now();
    send({ t: 'apply', id: id, track: 0, clip: 0, field: 'opacity', value: 35 + Math.floor(Math.random() * 30) });
  };
  function applyRemote(m) {
    var f = FIELDS[m.field];
    var t0 = Date.now();
    if (!f) return send({ t: 'applied', id: m.id, ok: false, err: 'unknown field' });
    cep.call('collabSetParam', m.track, m.clip, f[0], f[1], JSON.stringify(m.value)).then(function (r) {
      var ok = r.ok && r.data.after === m.value;
      log('remote apply ' + m.field + '=' + m.value + ' -> ' + (r.ok ? JSON.stringify(r.data) : r.err));
      if (ok) { R.remote.receivedOk = true; mark('c7', R.remote.sentOk ? 'PASS' : 'TODO', 'received ok; ' + (R.remote.sentOk ? 'both directions' : 'now send one back')); }
      send({ t: 'applied', id: m.id, ok: ok, err: r.ok ? null : r.err, before: r.ok ? r.data.before : null, after: r.ok ? r.data.after : null, applyMs: Date.now() - t0 });
    });
  }
  function gotAck(m) {
    var rt = Date.now() - pending[m.id];
    log('ack ' + JSON.stringify(m) + ' round trip ' + rt + ' ms');
    mark('c2', m.ok ? 'PASS' : 'FAIL', 'round trip ' + rt + ' ms');
    if (m.ok) { R.remote.sentOk = true; mark('c7', R.remote.receivedOk ? 'PASS' : 'TODO', 'sent ok; ' + (R.remote.receivedOk ? 'both directions' : 'now receive one from peer')); }
    else mark('c7', 'FAIL', m.err || 'peer apply mismatch');
  }

  // ---- export ----
  $('bExport').onclick = function () {
    var name = 'collab-probe-' + Date.now() + '.json';
    var text = JSON.stringify(R, null, 1);
    $('out').value = text;
    cep.call('collabWriteResults', name, text).then(function (r) { log('saved: ' + (r.ok ? r.data : r.err)); });
  };

  draw();
  $('env').textContent = cep.available ? '(CEP ok)' : '(NOT in CEP)';
  if (cep.available) $('bEnv').click();
})();

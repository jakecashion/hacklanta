// Phase 1 probe bridge. ExtendScript (ES3): var only, no JSON, no forEach.
// Every function returns a JSON string and never throws.

function cJ(v) {
  if (v === null || v === undefined) return 'null';
  var t = typeof v;
  if (t === 'number') return isFinite(v) ? String(v) : 'null';
  if (t === 'boolean') return v ? 'true' : 'false';
  if (t === 'string') {
    var s = '"';
    for (var i = 0; i < v.length; i++) {
      var c = v.charAt(i), n = v.charCodeAt(i);
      if (c === '"') s += '\\"'; else if (c === '\\') s += '\\\\';
      else if (n < 32) s += '\\u' + ('0000' + n.toString(16)).slice(-4);
      else s += c;
    }
    return s + '"';
  }
  if (v instanceof Array) {
    var a = [];
    for (var j = 0; j < v.length; j++) a.push(cJ(v[j]));
    return '[' + a.join(',') + ']';
  }
  var o = [];
  for (var k in v) if (v.hasOwnProperty(k)) o.push(cJ(k) + ':' + cJ(v[k]));
  return '{' + o.join(',') + '}';
}

function cWrap(fn) {
  try { return cJ({ ok: true, data: fn() }); }
  catch (e) { return cJ({ ok: false, err: String(e), line: e.line }); }
}

function cNow() { return new Date().getTime(); }
function cCount(coll) { return coll.numItems !== undefined ? coll.numItems : coll.length; }
function cTicks(n) { var t = new Time(); t.ticks = String(n); return t; }
function cNum(ticks) { return Number(ticks); }

function cSeq() {
  var s = app.project.activeSequence;
  if (!s) throw new Error('no active sequence');
  return s;
}

function cClip(ti, ci) {
  var tr = cSeq().videoTracks[ti];
  if (!tr) throw new Error('no video track ' + ti);
  var c = tr.clips[ci];
  if (!c) throw new Error('no clip ' + ti + ':' + ci);
  return c;
}

function cFindParam(clip, compName, propName) {
  var comps = clip.components, n = cCount(comps);
  for (var i = 0; i < n; i++) {
    if (comps[i].displayName !== compName) continue;
    var props = comps[i].properties, m = cCount(props);
    for (var j = 0; j < m; j++) if (props[j].displayName === propName) return props[j];
  }
  throw new Error('param not found: ' + compName + '.' + propName);
}

function cRead(p) {
  var tv = null;
  try { tv = p.isTimeVarying(); } catch (e) {}
  var v = null;
  try { v = p.getValue(); } catch (e2) { v = 'ERR ' + e2; }
  return { v: v, keyframed: tv };
}

// ---- env ----
function collabEnv() {
  return cWrap(function () {
    var seq = app.project.activeSequence;
    return {
      version: app.version, build: app.build, os: $.os, locale: app.getAppSystemPreferencePath ? 'n/a' : 'n/a',
      project: app.project.name, projectPath: app.project.path,
      sequence: seq ? seq.name : null, videoTracks: seq ? cCount(seq.videoTracks) : 0
    };
  });
}

// ---- component / param dump (ENV-03) ----
function collabDump() {
  return cWrap(function () {
    var seq = cSeq(), out = [];
    for (var ti = 0; ti < cCount(seq.videoTracks); ti++) {
      var tr = seq.videoTracks[ti];
      for (var ci = 0; ci < cCount(tr.clips); ci++) {
        var c = tr.clips[ci], comps = [];
        for (var k = 0; k < cCount(c.components); k++) {
          var comp = c.components[k], props = [];
          for (var m = 0; m < cCount(comp.properties); m++) {
            var p = comp.properties[m], r = cRead(p);
            props.push({ name: p.displayName, value: r.v, keyframed: r.keyframed });
          }
          comps.push({ name: comp.displayName, matchName: comp.matchName, props: props });
        }
        out.push({ ti: ti, ci: ci, name: c.name, nodeId: c.nodeId, start: c.start.ticks, end: c.end.ticks,
                   inPoint: c.inPoint.ticks, outPoint: c.outPoint.ticks, comps: comps });
      }
    }
    return out;
  });
}

// ---- ids / selection / playhead (check 3, presence) ----
function collabIds() {
  return cWrap(function () {
    var seq = cSeq(), out = [];
    for (var ti = 0; ti < cCount(seq.videoTracks); ti++)
      for (var ci = 0; ci < cCount(seq.videoTracks[ti].clips); ci++) {
        var c = seq.videoTracks[ti].clips[ci];
        out.push({ ti: ti, ci: ci, name: c.name, nodeId: c.nodeId, start: c.start.ticks });
      }
    return out;
  });
}

function collabPresence() {
  return cWrap(function () {
    var seq = cSeq(), sel = seq.getSelection(), ids = [];
    for (var i = 0; i < sel.length; i++) ids.push(sel[i].nodeId);
    return { selected: ids, playhead: seq.getPlayerPosition().ticks };
  });
}

// ---- param set + read-back (check 6 / kill gate) ----
function collabSetParam(ti, ci, compName, propName, valueJson) {
  return cWrap(function () {
    var p = cFindParam(cClip(ti, ci), compName, propName);
    var value = eval('(' + valueJson + ')'); // local panel input only, never peer data
    var before = cRead(p);
    var t0 = cNow();
    var ret = p.setValue(value, true);
    var ms = cNow() - t0;
    var after = cRead(p);
    return { before: before.v, set: value, after: after.v, keyframed: before.keyframed, setValueReturned: ret, ms: ms };
  });
}

// Sets each of the four core fields on one clip, reads back, restores the original.
function collabRoundTrip(ti, ci) {
  return cWrap(function () {
    var clip = cClip(ti, ci), res = [];
    var cases = [
      ['Opacity', 'Opacity', 40],
      ['Motion', 'Scale', 150],
      ['Motion', 'Rotation', 90],
      ['Motion', 'Position', null] // derived from the current value below
    ];
    for (var i = 0; i < cases.length; i++) {
      var comp = cases[i][0], prop = cases[i][1], target = cases[i][2];
      var entry = { field: comp + '.' + prop };
      try {
        var p = cFindParam(clip, comp, prop);
        var orig = cRead(p);
        entry.original = orig.v; entry.keyframed = orig.keyframed;
        if (prop === 'Position') target = [orig.v[0] + 0.1, orig.v[1] + 0.1];
        p.setValue(target, true);
        var got = cRead(p);
        entry.set = target; entry.readBack = got.v;
        entry.changed = cJ(got.v) !== cJ(orig.v);
        entry.exact = cJ(got.v) === cJ(target);
        p.setValue(orig.v, true);
        entry.restored = cJ(cRead(p).v) === cJ(orig.v);
      } catch (e) { entry.err = String(e); }
      res.push(entry);
    }
    return res;
  });
}

// ---- move / trim (check 4, stretch only) ----
function collabMoveTrim(ti, ci) {
  return cWrap(function () {
    var c = cClip(ti, ci), sec = 254016000000, out = {};
    var s0 = c.start.ticks, e0 = c.end.ticks, i0 = c.inPoint.ticks, o0 = c.outPoint.ticks;
    out.before = { start: s0, end: e0, inPoint: i0, outPoint: o0 };
    try {
      c.start = cTicks(cNum(s0) + sec); c.end = cTicks(cNum(e0) + sec);
      out.afterMove = { start: c.start.ticks, end: c.end.ticks };
      out.moveWorked = cNum(c.start.ticks) === cNum(s0) + sec;
      c.start = cTicks(cNum(s0)); c.end = cTicks(cNum(e0));
    } catch (e) { out.moveErr = String(e); }
    try {
      c.outPoint = cTicks(cNum(o0) - sec);
      out.afterTrim = { inPoint: c.inPoint.ticks, outPoint: c.outPoint.ticks, end: c.end.ticks };
      out.trimWorked = cNum(c.outPoint.ticks) === cNum(o0) - sec;
      c.outPoint = cTicks(cNum(o0));
    } catch (e2) { out.trimErr = String(e2); }
    out.restored = { start: c.start.ticks, end: c.end.ticks, inPoint: c.inPoint.ticks, outPoint: c.outPoint.ticks };
    out.restoredOk = out.restored.start === s0 && out.restored.end === e0 && out.restored.outPoint === o0;
    return out;
  });
}

// ---- events (check 5) ----
var cEv = $.global.cEv || ($.global.cEv = { counts: {}, last: {}, bound: false, names: [] });
var CEV_NAMES = ['onActiveSequenceStructureChanged', 'onActiveSequenceSelectionChanged', 'onActiveSequenceTrackItemAdded',
                 'onActiveSequenceChanged', 'onProjectChanged'];

function cEvMake(name) {
  return function () {
    cEv.counts[name] = (cEv.counts[name] || 0) + 1;
    cEv.last[name] = cNow();
  };
}

function collabBind() {
  return cWrap(function () {
    if (cEv.bound) return { already: true, names: cEv.names };
    var res = {};
    for (var i = 0; i < CEV_NAMES.length; i++) {
      var n = CEV_NAMES[i];
      try { res[n] = String(app.bind(n, cEvMake(n))); cEv.names.push(n); } catch (e) { res[n] = 'ERR ' + e; }
    }
    cEv.bound = true;
    return res;
  });
}

function collabEvents() { return cWrap(function () { return { counts: cEv.counts, last: cEv.last, now: cNow() }; }); }
function collabEventsReset() { return cWrap(function () { cEv.counts = {}; cEv.last = {}; return true; }); }

// ---- scan timing ----
function collabScan(reps) {
  return cWrap(function () {
    var seq = cSeq(), n = 0, t0 = cNow();
    for (var r = 0; r < reps; r++) {
      for (var ti = 0; ti < cCount(seq.videoTracks); ti++)
        for (var ci = 0; ci < cCount(seq.videoTracks[ti].clips); ci++) {
          var c = seq.videoTracks[ti].clips[ci];
          cRead(cFindParam(c, 'Opacity', 'Opacity')); cRead(cFindParam(c, 'Motion', 'Position'));
          cRead(cFindParam(c, 'Motion', 'Scale')); cRead(cFindParam(c, 'Motion', 'Rotation'));
          var x = c.start.ticks, y = c.end.ticks, nm = c.name;
          if (r === 0) n++;
        }
    }
    var ms = cNow() - t0;
    return { clips: n, reps: reps, totalMs: ms, msPerScan: ms / reps };
  });
}

function collabWriteResults(name, text) {
  return cWrap(function () {
    var f = new File(Folder.myDocuments.fsName + '/' + name);
    f.encoding = 'UTF-8'; f.open('w'); f.write(text); f.close();
    return f.fsName;
  });
}

function collabPing() { return cJ({ ok: true, data: 'bridge loaded' }); }

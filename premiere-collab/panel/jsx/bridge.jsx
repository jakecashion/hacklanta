// bridge.jsx - ExtendScript (ES3). Loaded by the panel via $.evalFile after json2.js.
// Rules: var only, for loops only, always return a JSON string.

var PC_FIELDS = {
    // field: [component matchName, param displayName, fallback param index, array index]
    // Position and Anchor Point are [x, y] normalized to the frame (0..1); each axis is its own field.
    "Motion.Scale":    ["AE.ADBE Motion", "Scale", 1],
    "Motion.Rotation": ["AE.ADBE Motion", "Rotation", 4],
    "Opacity.Opacity": ["AE.ADBE Opacity", "Opacity", 0],
    "Motion.Position.x":    ["AE.ADBE Motion", "Position", 0, 0],
    "Motion.Position.y":    ["AE.ADBE Motion", "Position", 0, 1],
    "Motion.AnchorPoint.x": ["AE.ADBE Motion", "Anchor Point", 5, 0],
    "Motion.AnchorPoint.y": ["AE.ADBE Motion", "Anchor Point", 5, 1]
};

// Read one field: a number, or one axis of an [x, y] param.
function pc_getField(param, field) {
    var v = param.getValue();
    var idx = PC_FIELDS[field][3];
    return (idx === undefined) ? v : v[idx];
}

// Write one field. For an axis, keep the other axis as Premiere holds it now.
function pc_setField(param, field, value) {
    var idx = PC_FIELDS[field][3];
    if (idx === undefined) { param.setValue(value, true); return; }
    var cur = param.getValue();
    var arr = [cur[0], cur[1]];
    arr[idx] = value;
    param.setValue(arr, true);
}

function pc_ok(data) { data = data || {}; data.ok = true; return JSON.stringify(data); }
function pc_err(e) {
    return JSON.stringify({ ok: false, err: String(e), line: (e && e.line) ? e.line : null });
}

function pc_seq() {
    var seq = app.project.activeSequence;
    if (!seq) { throw new Error("No active sequence. Open the demo sequence in the timeline."); }
    return seq;
}

function pc_clip(trackIndex, clipIndex) {
    var seq = pc_seq();
    var track = seq.videoTracks[trackIndex];
    if (!track) { throw new Error("No video track " + trackIndex); }
    var clip = track.clips[clipIndex];
    if (!clip) { throw new Error("No clip " + clipIndex + " on V" + (trackIndex + 1)); }
    return clip;
}

function pc_findParam(clip, field) {
    var spec = PC_FIELDS[field];
    if (!spec) { throw new Error("Unknown field " + field); }
    var comps = clip.components;
    for (var i = 0; i < comps.numItems; i++) {
        var c = comps[i];
        if (c.matchName === spec[0]) {
            var props = c.properties;
            for (var k = 0; k < props.numItems; k++) {
                if (props[k].displayName === spec[1]) { return props[k]; }
            }
            if (props[spec[2]]) { return props[spec[2]]; }
            throw new Error("Param " + spec[1] + " not found in " + spec[0]);
        }
    }
    throw new Error("Component " + spec[0] + " not found on clip " + clip.name);
}

// Clip.name is not an effect param: it is trackItem.name, read and written directly.
var PC_NAME = "Clip.name";

function pc_readFields(clip) {
    var out = {};
    out[PC_NAME] = clip.name;
    for (var f in PC_FIELDS) {
        if (PC_FIELDS.hasOwnProperty(f)) {
            try { out[f] = pc_getField(pc_findParam(clip, f), f); }
            catch (e) { out[f] = "ERR: " + String(e); }
        }
    }
    return out;
}

function pc_ping() {
    try {
        var seq = app.project.activeSequence;
        return pc_ok({
            version: app.version,
            project: app.project.name,
            sequence: seq ? seq.name : null
        });
    } catch (e) { return pc_err(e); }
}

// List clips on one video track with their synced fields, nodeId and component/param names (probe info).
function pc_listClips(trackIndex) {
    try {
        trackIndex = trackIndex || 0;
        var seq = pc_seq();
        var track = seq.videoTracks[trackIndex];
        var clips = [];
        for (var j = 0; j < track.clips.numItems; j++) {
            var clip = track.clips[j];
            var comps = [];
            for (var i = 0; i < clip.components.numItems; i++) {
                var c = clip.components[i];
                var names = [];
                for (var k = 0; k < c.properties.numItems; k++) { names.push(c.properties[k].displayName); }
                comps.push({ matchName: c.matchName, displayName: c.displayName, params: names });
            }
            clips.push({
                id: "v" + trackIndex + ":" + j,
                name: clip.name,
                nodeId: clip.nodeId,
                selected: clip.isSelected(),
                p: pc_readFields(clip),
                components: comps
            });
        }
        return pc_ok({ sequence: seq.name, track: trackIndex, clips: clips });
    } catch (e) { return pc_err(e); }
}

// Write one field, then read it back. Returns before / wrote / after.
function pc_setParam(trackIndex, clipIndex, field, value) {
    try {
        var clip = pc_clip(trackIndex, clipIndex);
        var param = pc_findParam(clip, field);
        var before = param.getValue();
        var t0 = new Date().getTime();
        param.setValue(value, true);
        var ms = new Date().getTime() - t0;
        var after = param.getValue();
        return pc_ok({ clip: clip.name, field: field, before: before, wrote: value, after: after, ms: ms,
                       timeVarying: param.isTimeVarying() });
    } catch (e) { return pc_err(e); }
}

// Kill test: big jump edits on all three fields of one clip.
function pc_killTest(trackIndex, clipIndex) {
    try {
        var targets = { "Motion.Scale": 150, "Motion.Rotation": 45, "Opacity.Opacity": 50 };
        var results = [];
        for (var f in targets) {
            if (targets.hasOwnProperty(f)) {
                results.push(JSON.parse(pc_setParam(trackIndex, clipIndex, f, targets[f])));
            }
        }
        return pc_ok({ results: results });
    } catch (e) { return pc_err(e); }
}

function pc_resetClip(trackIndex, clipIndex) {
    try {
        var defaults = { "Motion.Scale": 100, "Motion.Rotation": 0, "Opacity.Opacity": 100 };
        var results = [];
        for (var f in defaults) {
            if (defaults.hasOwnProperty(f)) {
                results.push(JSON.parse(pc_setParam(trackIndex, clipIndex, f, defaults[f])));
            }
        }
        return pc_ok({ results: results });
    } catch (e) { return pc_err(e); }
}

// Time a full read of the track (scan cost for the 1 s poll).
function pc_scanCost(trackIndex) {
    try {
        var t0 = new Date().getTime();
        var r = JSON.parse(pc_listClips(trackIndex || 0));
        return pc_ok({ ms: new Date().getTime() - t0, clips: r.clips ? r.clips.length : 0 });
    } catch (e) { return pc_err(e); }
}

// ---------- Phase 2: sync ----------

// Light scan for the 1 s poll: clip IDs and the three synced fields only.
function pc_scan(trackIndex) {
    try {
        trackIndex = trackIndex || 0;
        var track = pc_seq().videoTracks[trackIndex];
        var clips = [];
        for (var j = 0; j < track.clips.numItems; j++) {
            var clip = track.clips[j];
            clips.push({ id: clip.nodeId, name: clip.name, p: pc_readFields(clip) });
        }
        return pc_ok({ clips: clips });
    } catch (e) { return pc_err(e); }
}

// Find a clip on any video track by its nodeId (the shared clip ID).
function pc_clipByNodeId(nodeId) {
    var tracks = pc_seq().videoTracks;
    for (var t = 0; t < tracks.numTracks; t++) {
        var clips = tracks[t].clips;
        for (var j = 0; j < clips.numItems; j++) {
            if (clips[j].nodeId === nodeId) { return clips[j]; }
        }
    }
    throw new Error("No clip with nodeId " + nodeId);
}

// Apply ops [{clipId:"000f4242", field, value}, ...] (clipId = nodeId). Returns each op's read-back value.
function pc_applyOps(opsJson) {
    try {
        var ops = JSON.parse(opsJson);
        var results = [];
        for (var i = 0; i < ops.length; i++) {
            var op = ops[i];
            try {
                var clip = pc_clipByNodeId(String(op.clipId));
                if (op.field === PC_NAME) {
                    clip.name = String(op.value);
                    results.push({ clipId: op.clipId, field: op.field, after: clip.name, ok: true });
                    continue;
                }
                var param = pc_findParam(clip, op.field);
                pc_setField(param, op.field, op.value);
                results.push({ clipId: op.clipId, field: op.field, after: pc_getField(param, op.field), ok: true });
            } catch (e1) {
                results.push({ clipId: op.clipId, field: op.field, ok: false, err: String(e1) });
            }
        }
        return pc_ok({ results: results });
    } catch (e) { return pc_err(e); }
}

"bridge loaded";

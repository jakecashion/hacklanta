// sync.js - sync engine (pure logic, no Premiere or socket code).
// UMD: module.exports under Node (node --test), global PCSync in the panel.
//
// Shadow = last known value of each (clipId, field). A scan that differs from the shadow
// by more than epsilon is a local edit: it becomes an op, the shadow takes the new value
// and the field is marked pending until the relay commits that op.
// Commits arrive in relay (rev) order. Rules:
//   - own op: clear the pending mark (shadow already has the value)
//   - field pending with a newer local op: skip; our op comes later in relay order and wins
//   - otherwise: apply, then set the shadow from Premiere's read-back (kills rounding echoes).
//     The shadow changes only after a successful apply: if the apply fails (no active
//     sequence, keyframed param), the shadow keeps Premiere's real value, so the next scan
//     doesn't mistake the unapplied value for a local edit and send the old value back.
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.PCSync = factory();
})(typeof self !== 'undefined' ? self : this, function () {
  const FIELDS = ['Motion.Scale', 'Motion.Rotation', 'Opacity.Opacity',
    'Motion.Position.x', 'Motion.Position.y', 'Motion.AnchorPoint.x', 'Motion.AnchorPoint.y'];
  // Position and Anchor Point are fractions of the frame (0..1): 0.0005 is about a third of a
  // pixel at 640 wide. The other fields use the default epsilon.
  const AXIS_EPSILON = 0.0005;
  const isAxis = (f) => f.endsWith('.x') || f.endsWith('.y');
  const key = (clipId, field) => clipId + '|' + field;

  function createSync(opts = {}) {
    const epsilon = opts.epsilon ?? 0.05;
    const eps = (f) => (isAxis(f) ? AXIS_EPSILON : epsilon);
    const author = opts.author || 'Editor';
    let opCounter = 0;
    const idPrefix = opts.idPrefix || Math.random().toString(36).slice(2, 8);

    const shadow = new Map();   // key -> number
    const pending = new Map();  // key -> opId of our newest unsent-or-uncommitted op
    let lastRev = 0;

    // Set the baseline from a scan without producing ops (on connect).
    function reset(clips) {
      shadow.clear();
      pending.clear();
      for (const c of clips) {
        for (const f of FIELDS) {
          if (typeof c.p[f] === 'number') shadow.set(key(c.id, f), c.p[f]);
        }
      }
    }

    // Compare a scan to the shadow. Returns ops for every field that moved.
    function diff(clips) {
      const ops = [];
      for (const c of clips) {
        for (const f of FIELDS) {
          const v = c.p[f];
          if (typeof v !== 'number') continue;
          const k = key(c.id, f);
          const old = shadow.get(k);
          if (old === undefined) { shadow.set(k, v); continue; } // new clip: baseline only
          if (Math.abs(v - old) <= eps(f)) continue;
          const opId = idPrefix + '-' + (++opCounter);
          shadow.set(k, v);
          pending.set(k, opId);
          ops.push({ opId, author, clipId: c.id, field: f, value: v });
        }
      }
      return ops;
    }

    // Handle one commit from the relay. Returns the op to apply in Premiere, or null.
    function receiveCommit(commit) {
      if (commit.rev <= lastRev) return null; // duplicate or stale
      lastRev = commit.rev;
      const op = commit.op;
      const k = key(op.clipId, op.field);
      const mine = pending.get(k);
      if (mine !== undefined) {
        if (mine === op.opId) pending.delete(k);
        return null; // own op, or a remote op that our pending op will override
      }
      return op; // caller applies it, then calls afterApply with the read-back
    }

    // Join snapshot from the relay: latest commit per field. Same rules as live commits, in rev
    // order; values the timeline already holds are skipped. Returns the ops to apply.
    function receiveCatchup(commits) {
      const ops = [];
      for (const c of [...commits].sort((x, y) => x.rev - y.rev)) {
        const op = receiveCommit(c);
        if (!op) continue;
        const cur = shadow.get(key(op.clipId, op.field));
        if (cur !== undefined && Math.abs(cur - op.value) <= eps(op.field)) continue;
        ops.push(op);
      }
      return ops;
    }

    // After applyOps: store what Premiere actually holds so the next scan matches.
    function afterApply(clipId, field, readBack) {
      if (typeof readBack === 'number') shadow.set(key(clipId, field), readBack);
    }

    return {
      reset, diff, receiveCommit, receiveCatchup, afterApply,
      get lastRev() { return lastRev; },
      get pendingCount() { return pending.size; },
      shadowValue: (clipId, field) => shadow.get(key(clipId, field)),
      ownsOp: (opId) => typeof opId === 'string' && opId.startsWith(idPrefix + '-'),
    };
  }

  return { createSync, FIELDS };
});

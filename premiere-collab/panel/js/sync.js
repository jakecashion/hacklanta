// Pure sync engine: no Premiere, no sockets. Loads in the panel (global) and in node (module).
// Model: every edit goes through one sequencer that assigns rev. Last commit in rev order wins per field.
(function (root) {
  var EPS = 1e-3;
  function same(a, b) {
    if (Array.isArray(a) && Array.isArray(b)) return a.length === b.length && a.every(function (x, i) { return same(x, b[i]); });
    if (typeof a === 'number' && typeof b === 'number') return Math.abs(a - b) <= EPS;
    return a === b;
  }
  var clone = function (v) { return Array.isArray(v) ? v.slice() : v; };

  // bridge: { apply(field, value) -> readBack }   send(op): ship an op to the sequencer
  function Engine(opts) {
    this.me = opts.author; this.bridge = opts.bridge; this.send = opts.send;
    this.shadow = {};   // field -> last value we believe the timeline has
    this.pending = {};  // field -> id of my newest uncommitted op
    this.epoch = 0;     // bumps on every remote apply; invalidates scans started before it
    this.feed = []; this.n = 0;
  }
  Engine.prototype.load = function (snap) { // join / resync: adopt a full state without emitting ops
    this.shadow = {}; this.pending = {};
    for (var f in snap) this.shadow[f] = clone(snap[f]);
    this.epoch++;
  };
  Engine.prototype.scanToken = function () { return this.epoch; };
  // snap = timeline read by bridge; token from scanToken() taken BEFORE the read started
  Engine.prototype.tick = function (snap, token) {
    if (token !== this.epoch) return false; // stale: a remote apply landed while the read was in flight
    for (var f in snap) {
      if (f in this.shadow && same(snap[f], this.shadow[f])) continue;
      var op = { id: this.me + ':' + (++this.n), author: this.me, field: f, value: clone(snap[f]) };
      this.shadow[f] = clone(snap[f]); this.pending[f] = op.id;
      this.send(op);
    }
    return true;
  };
  Engine.prototype.onCommit = function (c) {
    var op = c.op, f = op.field;
    this.feed.push(op.author + ' set ' + f + ' to ' + JSON.stringify(op.value) + ' (rev ' + c.rev + ')');
    if (op.author === this.me) { if (this.pending[f] === op.id) delete this.pending[f]; return; }
    if (this.pending[f]) return; // my newer op is later in rev order, so it wins; skip this one
    this.shadow[f] = clone(this.bridge.apply(f, op.value)); // shadow = read-back, so rounding can't echo
    this.epoch++;
  };

  function Sequencer(onCommit) { this.rev = 0; this.onCommit = onCommit; }
  Sequencer.prototype.submit = function (op) { this.onCommit({ rev: ++this.rev, op: op }); };

  var api = { Engine: Engine, Sequencer: Sequencer, same: same };
  if (typeof module !== 'undefined') module.exports = api; else root.CollabSync = api;
})(this);

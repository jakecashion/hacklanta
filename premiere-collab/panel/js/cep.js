// Minimal CSInterface stand-in (evalScript, events, extension path). Uses the CEP host object directly.
(function () {
  var host = window.__adobe_cep__;
  window.cep = {
    available: !!host,
    eval: function (script) {
      return new Promise(function (resolve) {
        if (!host) return resolve('{"ok":false,"err":"not running inside CEP"}');
        host.evalScript(script, function (r) { resolve(r); });
      });
    },
    // calls a bridge function with JSON-encoded args; resolves to the parsed {ok,data|err}
    call: function (fn) {
      var args = Array.prototype.slice.call(arguments, 1).map(function (a) { return JSON.stringify(a); }).join(',');
      return window.cep.eval(fn + '(' + args + ')').then(function (r) {
        try { return JSON.parse(r); } catch (e) { return { ok: false, err: 'bad reply: ' + r }; }
      });
    },
    extensionPath: function () {
      if (!host) return '';
      var p = decodeURI(host.getSystemPath('extension'));
      return p.replace('file:///', '');
    }
  };
})();

# Technology Stack

**Project:** Premiere Live Collab (two-user live collaboration panel for Premiere Pro 22.3.1, Windows)
**Researched:** 2026-10-10
**Overall confidence:** HIGH for the CEP runtime facts (checked on the dev machine and in Adobe's repos). MEDIUM for the cloudflared fallback and the ExtendScript debugger. Both are called out below.

## Verified on this machine (2026-10-10)

These came from the installed Premiere, not from docs. They set the targets for everything below.

| Fact | Value | How checked |
|------|-------|-------------|
| CEP runtime in Premiere 22.3.1 | `CEPHtmlEngine.exe` **11.3.0** (so CSXS.11) | File version of `C:\Program Files\Adobe\Adobe Premiere Pro 2022\CEPHtmlEngine\CEPHtmlEngine.exe` |
| Browser engine | **Chromium 88.0.4324.182** (CEF 88) | File version of `libcef.dll` in the same folder |
| Node.js inside CEP | 15.9.0 (only when Node is enabled in the manifest) | CEP 11.1 HTML Extension Cookbook |
| Registry key | `HKCU\Software\Adobe\CSXS.11` exists, `PlayerDebugMode` not set | `Get-ItemProperty` |
| Per-user extensions folder | `%APPDATA%\Adobe\CEP\extensions` does not exist yet | Already in `PROJECT.md`; must be created |
| Script events exist in this build | `onActiveSequenceStructureChanged`, `onActiveSequenceSelectionChanged`, `onActiveSequenceTrackItemAdded`, `onActiveSequenceChanged`, `onProjectChanged` all appear as strings in `ScriptLayerPPro.dll` | `grep -a` on the install folder |
| `CSXSEvent` support library | `PlugPlugExternalObject.dll` is in the install folder | `grep -a` on the install folder |

The event-name check only proves the names are registered. It does not prove they fire for every edit kind. Pre-build check 5 in `08-mvp.md` still has to run.

## Recommended Stack

### Core Framework (panel)

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| CEP panel (HTML + JS) | CEP 11.3 / CSXS.11 | Panel UI and sync engine host | The only panel tech that runs in 22.3.1. UXP needs Premiere 25.6. | HIGH |
| Plain HTML + CSS + vanilla JS, classic `<script>` tags | ES2020 allowed (Chromium 88) | UI, WebSocket, timers, `evalScript` calls | No build step means no build failures at 3am. Chromium 88 supports optional chaining, `??`, `async/await`, `Map`/`Set`, and `fetch`. | HIGH |
| `CSInterface.js` | **v11.0.0** from `Adobe-CEP/CEP-Resources/CEP_11.x/CSInterface.js` | `evalScript`, `addEventListener` for `CSXSEvent`, `getSystemPath` | Official file. Its header reads `CSInterface - v11.0.0`; last commit 2021-06-11. Copy it into `panel/js/`. Do not use the CEP_12.x or CEP_13.x copies; this runtime is 11.3. | HIGH |
| Native browser `WebSocket` | Built into Chromium 88 | Panel to relay connection | Yes, CEP's Chromium has a full native `WebSocket`. No library and no Node needed. `ws://` works from the panel's `file://` origin; `wss://` works for the tunnel. | HIGH |
| ExtendScript (ES3) `bridge.jsx` | Premiere's built-in engine | Read and write the timeline | The only way to reach the Premiere object model from CEP. | HIGH |
| `json2.js` | **2023-05-10 build** (Douglas Crockford, `douglascrockford/JSON-js`, public domain, 530 lines) | `JSON.parse` / `JSON.stringify` in ExtendScript | ExtendScript is ES3 and has no `JSON` object. json2 adds it and does nothing where it already exists. Vendor it into `panel/jsx/json2.js`; do not load it from a server. | HIGH |

### Relay (host laptop only)

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| Node.js | **24.x** (dev machine has v24.21.0) | Runs `relay.js`, `fake-peer.js`, and `node --test` | Already installed. Only the machine that hosts needs it. The guest needs no Node at all, because the panel uses the native WebSocket. | HIGH |
| `ws` | **8.22.0** (npm `latest`, published 2026-09-26; zero runtime dependencies; `engines.node >=10`) | WebSocket server in the relay, and client in `fake-peer.js` | The standard Node WebSocket library. Use the named export `const { WebSocketServer } = require('ws')`. Pin the exact version in `package.json`. If 8.22.0 misbehaves, fall back to 8.21.3. The 8.22.0 release only adds a `protocols` option and a `close()` fix, so there is no reason to avoid it. | HIGH |
| `node:test` + `node:assert/strict` | Built into Node 24 | Tests for `sync.js` | Zero installs. `08-mvp.md` already specifies `node --test`. | HIGH |

### Database

None. Session state lives in memory on the host panel. Do not add one.

### Infrastructure

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| Same Wi-Fi or phone hotspot, `ws://<host IPv4>:8080` | n/a | Primary transport | No internet dependency, lowest latency. | HIGH |
| Windows Firewall inbound rule for TCP 8080 | n/a | Lets the guest reach the host relay | The Node.js prompt only covers the network profile you click. Venue Wi-Fi is often classed Public. Create the rule ahead of time with `profile=any`. | HIGH |
| `cloudflared` quick tunnel | Latest release from the GitHub releases page (`.exe`, Windows 64-bit) | Fallback when venue Wi-Fi isolates clients | Needs no account and no domain: `cloudflared tunnel --url http://localhost:8080` gives a `wss://<random>.trycloudflare.com` address. | MEDIUM (see notes below) |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `bufferutil`, `utf-8-validate` | do not install | Optional native speedups for `ws` | Never here. They need a native build on Windows and bring no gain at 4 Hz presence traffic. `ws` falls back to pure JS. |
| Nothing else | n/a | | The panel has zero npm dependencies. The relay has one (`ws`). |

## Answers to the specific questions

### 1. Manifest and version targeting for PPRO 22.x

Use manifest schema `Version="6.0"`, `RequiredRuntime CSXS 6.0`, and a wide PPRO range. Adobe's own panels installed in this Premiere (`com.adobe.ccx.start-2.16.0`) use exactly this: `ExtensionManifest Version="6.0"`, `PPRO Version="[14.3,99.9]"`, `RequiredRuntime CSXS 6.0`. A lower required runtime still loads on CEP 11. A host range that is too narrow makes the panel silently missing from **Window > Extensions**, so keep it wide. (Adobe's `PProPanel` sample is older still: schema 5.0, CSXS 6.0, PPRO min 9.0.)

Do **not** put `--enable-nodejs` or `--mixed-context` in `<CEFCommandLine>`. This differs from `07` §2 step 3. `08` §4 already says the panel needs no Node modules; the manifest should match.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<ExtensionManifest Version="6.0" ExtensionBundleId="com.hacklanta.premierecollab"
    ExtensionBundleVersion="0.1.0" ExtensionBundleName="Premiere Live Collab"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <ExtensionList>
    <Extension Id="com.hacklanta.premierecollab.panel" Version="0.1.0"/>
  </ExtensionList>
  <ExecutionEnvironment>
    <HostList><Host Name="PPRO" Version="[14.3,99.9]"/></HostList>
    <LocaleList><Locale Code="All"/></LocaleList>
    <RequiredRuntimeList><RequiredRuntime Name="CSXS" Version="6.0"/></RequiredRuntimeList>
  </ExecutionEnvironment>
  <DispatchInfoList>
    <Extension Id="com.hacklanta.premierecollab.panel">
      <DispatchInfo>
        <Resources><MainPath>./index.html</MainPath></Resources>
        <Lifecycle><AutoVisible>true</AutoVisible></Lifecycle>
        <UI>
          <Type>Panel</Type>
          <Menu>Live Collab</Menu>
          <Geometry>
            <Size><Height>600</Height><Width>360</Width></Size>
            <MinSize><Height>300</Height><Width>280</Width></MinSize>
          </Geometry>
        </UI>
      </DispatchInfo>
    </Extension>
  </DispatchInfoList>
</ExtensionManifest>
```

Notes: `<Size>` is mandatory. No `ScriptPath`: load the JSX from the panel (see pattern below). Do not use `#` in any folder path (CEF treats it as a delimiter).

### 2. `PlayerDebugMode` (CSXS.11)

The key must be a string value (`REG_SZ`) named `PlayerDebugMode` with data `1`, under `HKCU\Software\Adobe\CSXS.11`. The key already exists on the dev machine. Run on **both** machines, then restart Premiere:

```bat
reg add HKCU\Software\Adobe\CSXS.11 /v PlayerDebugMode /t REG_SZ /d 1 /f
```

Only `CSXS.11` matters for 22.3.1 (runtime 11.3.0). No admin rights needed. Source: CEP 11.1 HTML Extension Cookbook. Confidence: HIGH.

### 3. Debugging

| Layer | Tool | Setup | Confidence |
|-------|------|-------|------------|
| Panel JS | Chrome DevTools via CEP remote debug | Put a file named exactly `.debug` in the panel root (next to `CSXS/`). Open `http://localhost:8088` in Chrome, click the panel page. Ports must be 1024 to 65534. | HIGH (format and port rules confirmed in the CEP 11.1 Cookbook; this closes the "not verified" item in `07` §9) |
| ExtendScript | Return errors, don't step through | Wrap every bridge function in `try/catch` and return `JSON.stringify({ok:false, err:String(e), line:e.line})`. Failed `evalScript` calls otherwise return only `"EvalScript error."`. Add `$.writeln` and `app.setSDKEventMessage`. | HIGH |
| ExtendScript (optional) | VS Code + Adobe "ExtendScript Debugger" | Adobe's PProPanel readme lists it as the supported environment. A "Can't initialize target" error with Premiere is reported in forum threads, with a hack workaround. Treat as optional; do not spend hackathon time on it. | MEDIUM |
| Panel reload | A dev-only "Reload" button calling `location.reload()` | Adobe's sample uses `history.go(0)`. Closing and reopening the panel also works. | HIGH |

Create the `.debug` file with the correct name: Notepad will add `.txt`. Use `copy con .debug` or write it from a script. The `Extension Id` inside must equal the one in the manifest's `DispatchInfoList` (`com.hacklanta.premierecollab.panel` above).

```xml
<?xml version="1.0" encoding="UTF-8"?>
<ExtensionList>
  <Extension Id="com.hacklanta.premierecollab.panel">
    <HostList><Host Name="PPRO" Port="8088"/></HostList>
  </Extension>
</ExtensionList>
```

### 4. Does CEP's Chromium have a native WebSocket?

Yes. CEF 3 branch 88 / Chromium 88.0.4324.182 (verified in `libcef.dll`) has full `WebSocket`. The CEP cookbook itself notes that localhost ports seen in TCPView are Chromium opening sockets for HTML-extension WebSockets. Use it. A `ws` client inside the panel would require Node enabled in CEP (Node 15.9), which adds failure modes for no gain.

Rules for the panel's socket code:
- The panel's origin is `file://`, so `ws://192.168.x.x:8080` is not blocked as mixed content. Confirm in first-hour check 2.
- The tunnel's `wss://` certificate is a public one, so no certificate flags are needed. (CEP strips `--ignore-certificate-errors` anyway.)
- Send `Origin: file://` is expected. Do not enforce an Origin check in the relay.
- A browser `WebSocket` cannot send protocol-level pings, but it auto-replies to the server's pings. So run the heartbeat **on the relay**: `ws.ping()` every 20 s, terminate on a missed pong. This also keeps the Cloudflare tunnel from closing an idle socket.
- Do not use ES module `<script type="module">` from `file://` unless you also add `--allow-file-access-from-files`. Use classic scripts. Write `sync.js` as UMD (`module.exports` when present, else a global) so `node --test` and the panel load the same file.

### 5. json2.js for ES3

- Version: the 2023-05-10 file on `douglascrockford/JSON-js` master. Public domain.
- Load it at the top of `bridge.jsx` with `#include "json2.js"` (ExtendScript preprocessor, resolved relative to the including file), or `$.evalFile` it first.
- ES3 traps to design around in `bridge.jsx`: no `Array.prototype.forEach/map/filter`, no `Object.keys`, no `String.prototype.trim`, no `let/const`/arrow functions/template strings, no trailing commas. Use `for` loops and `var`. Keep all ES2020 code on the panel side only.
- Return **strings only** from `evalScript`; always `JSON.stringify` the result.

### 6. Loading the JSX and events back

- Load `bridge.jsx` from the panel on every panel load instead of through manifest `ScriptPath`, so closing and reopening the panel picks up edits:
  ```js
  const cs = new CSInterface();
  const root = cs.getSystemPath(SystemPath.EXTENSION);
  cs.evalScript('$.evalFile("' + root + '/jsx/bridge.jsx")', ...);
  ```
  This is the PProPanel approach (it builds a path string and evals it). Whether a changed `.jsx` needs a full Premiere restart is still unverified (MEDIUM); test it in the first hour.
- JSX to panel events (`CSXSEvent`) need the support library loaded first. On Windows the name is `PlugPlugExternalObject.dll` (no `.dll` on macOS). Copy Adobe's pattern from `Premiere.jsx`:
  ```js
  var eo = (Folder.fs === 'Macintosh') ? 'PlugPlugExternalObject' : 'PlugPlugExternalObject.dll';
  var lib = new ExternalObject('lib:' + eo);
  var ev = new CSXSEvent(); ev.type = 'com.hacklanta.premierecollab.changed'; ev.data = '...'; ev.dispatch();
  ```
  Panel side: `cs.addEventListener('com.hacklanta.premierecollab.changed', handler)`.
- Event binding (`app.bind('onActiveSequenceStructureChanged', fn)`) is how Adobe's sample does it. Inside the handler, do almost nothing: dispatch a `CSXSEvent` and let the panel call `snapshot()`.

### 7. Packaging and install into `%APPDATA%\Adobe\CEP\extensions`

No ZXP signing, no `ZXPSignCmd`. Debug mode loads unsigned panels. Use a `scripts/install.ps1`, run once per machine:

```powershell
reg add HKCU\Software\Adobe\CSXS.11 /v PlayerDebugMode /t REG_SZ /d 1 /f
$dst = Join-Path $env:APPDATA 'Adobe\CEP\extensions\com.hacklanta.premierecollab'
robocopy "$PSScriptRoot\..\panel" $dst /MIR /XD node_modules | Out-Null
```

- Folder name does not have to match the extension ID, but keeping them equal avoids confusion.
- **Use `robocopy /MIR` as the default.** Re-run it after each change on the guest machine. On the dev machine, use a **directory junction** instead: `mklink /J "%APPDATA%\Adobe\CEP\extensions\com.hacklanta.premierecollab" "C:\...\hacklanta\premiere-collab\panel"`. Junctions need no admin rights. `07` §2 suggests `mklink /D` (symbolic link), which needs an elevated prompt or Developer Mode. Whether CEP follows a junction is unverified (MEDIUM); if the panel does not show up, fall back to robocopy.
- The `.debug` file ships in `panel/` for the hackathon. Remove it for any real release.
- Firewall rule for the relay (one time, elevated prompt, host machine):
  ```bat
  netsh advfirewall firewall add rule name="premiere-collab relay" dir=in action=allow protocol=TCP localport=8080 profile=any
  ```
- Guest machine: copy the repo `panel/` folder (git clone, zip, or USB) and run `install.ps1`. No Node install needed on the guest. On the host, install Node 24 or drop a portable `node.exe` next to `relay.js` so either laptop can host.
- After the first install, restart Premiere, then **Window > Extensions > Live Collab**.

### 8. Relay (about 60 lines of real code)

```js
const { WebSocketServer } = require('ws');
const wss = new WebSocketServer({ host: '0.0.0.0', port: Number(process.env.PORT) || 8080, maxPayload: 1 << 20 });
wss.on('connection', (ws) => {
  ws.isAlive = true;
  ws.on('pong', () => { ws.isAlive = true; });
  ws.on('message', (data, isBinary) => { /* parse JSON, route by room code */ });
});
setInterval(() => {
  for (const ws of wss.clients) { if (!ws.isAlive) { ws.terminate(); continue; } ws.isAlive = false; ws.ping(); }
}, 20000);
```

- Print the machine's LAN IPv4 addresses at startup (`os.networkInterfaces()`), and also send them to the host panel in the `created` reply. That way the host panel can show "Tell the guest: 192.168.x.x" without enabling Node in CEP.
- No Express, no `socket.io`. Plain `ws`.

### 9. Optional cloudflared tunnel

- Install: download the Windows 64-bit `.exe` or MSI from the cloudflared GitHub releases page. (`winget install Cloudflare.cloudflared` is likely to work but was not confirmed here.) cloudflared does not auto-update on Windows. Install it on the host **before** the demo, not on venue Wi-Fi.
- Run: `cloudflared tunnel --url http://localhost:8080`. Copy the printed `https://<random>.trycloudflare.com` and give the guest `wss://<random>.trycloudflare.com`.
- Documented limits (Cloudflare docs): no uptime guarantee, 200 in-flight requests, no SSE, hostname changes on every run, "for testing and development". An existing `config.yaml` in `~/.cloudflared` blocks quick tunnels; rename it.
- WebSockets: Cloudflare's proxy supports them with no configuration, and closes idle sockets after an unspecified time. The quick-tunnel docs do not mention WebSockets, so test it. The relay-side 20 s ping covers the idle timeout.
- If QUIC (UDP) is blocked on the venue network, try `cloudflared tunnel --protocol http2 --url http://localhost:8080` (flag from general cloudflared knowledge, not confirmed in the docs fetched; MEDIUM).
- Security: a tunnel puts the relay on the public internet. The session code and the host's Approve click are the only gate. Use a 6-character code from a random source, limit join attempts per connection, and stop the tunnel after the demo.
- Expect extra latency of tens to low hundreds of milliseconds. Still inside the 1 to 2 s budget.

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| Panel tech | CEP 11 | UXP | Needs Premiere 25.6. Both machines have 22.3.1. UXP does not load. |
| Panel framework | Vanilla JS, no build | React / Vue / Svelte | A build step and a bundle add failure modes. The UI is a status badge, a few inputs, a user list, and a feed. |
| Panel boilerplate | Hand-rolled from the PProPanel pattern | Bolt CEP (Vite + TypeScript) | Its README targets Adobe CC apps "2024 or later", and it brings Vite, TypeScript, and an ExtendScript compile step. Wrong target and wrong risk for a 12-hour build. |
| Language | JavaScript | TypeScript | Compile step plus ES3 output concerns in `bridge.jsx`. `node --test` already covers the logic in `sync.js`. |
| Transport client | Native `WebSocket` | `ws` or `socket.io-client` in Node-enabled CEP | Needs `--enable-nodejs`, runs Node 15.9, and widens the failure surface. |
| Relay | `ws` 8.22.0 | `socket.io`, Express + `express-ws`, `uWebSockets.js` | Extra layers (long-polling fallback, protocol overhead, native builds) with no benefit for a 2-peer room. |
| Conflict model | Host-authoritative `rev` + last-writer-wins per field (`08` §8) | Yjs / Automerge CRDT | Premiere state is not a CRDT document. The ops are property setters, so a host-ordered log is simpler and adequate for two users. |
| JSON in ExtendScript | `json2.js` | Hand-written string building, or `JSON3` | json2 is the standard, tiny, public domain, and tested. |
| Install | `install.ps1` (reg add + robocopy / junction) | ZXP + `ZXPSignCmd` + installer | Signing and installers cost hours and add nothing. Debug mode loads unsigned panels. |
| Tunnel fallback | `cloudflared` quick tunnel | ngrok, localtunnel, Tailscale | ngrok needs an account and has WebSocket limits on free plans; localtunnel is unreliable; Tailscale needs an account on both machines. Hotspot is the first fallback anyway. |
| ExtendScript debugging | try/catch to JSON + `$.writeln` | ExtendScript Toolkit (ESTK) | ESTK is discontinued and 32-bit. |

## What NOT to use

| Do not use | Why |
|------------|-----|
| **UXP** (plugin, UDT, Spectrum UXP) | Needs Premiere 25.6 or later. `06-premiere-pro-uxp.md` is for a later port only. |
| **`--enable-nodejs` / `--mixed-context`** | Not needed with the native WebSocket. It switches the panel to Node 15.9 with global Node objects in every frame, which makes library behavior harder to predict. Revisit only if you decide the panel must spawn the relay or read `os.networkInterfaces()` itself; the relay-reports-IP approach above avoids that. |
| React / Vue / Svelte / Vite / webpack / TypeScript | No build step in a 12-hour event. |
| jQuery, Spectrum CSS, any UI kit | Adobe's sample bundles jQuery 1.9.1 for old reasons. Hand-written CSS in a dark theme (about 100 lines) is faster to get right than learning a kit. |
| `socket.io`, Express | Not needed. |
| ES modules over `file://` | Blocked by file-origin CORS unless you add `--allow-file-access-from-files`. Classic scripts avoid the problem. |
| `CSInterface.js` from CEP_12.x / CEP_13.x | Wrong runtime generation. Use the CEP_11.x copy. |
| ExtendScript Toolkit | Discontinued, 32-bit. |
| `bufferutil` / `utf-8-validate` | Native builds with no gain here. |
| ZXP signing / `ZXPSignCmd` | Unneeded with `PlayerDebugMode`. |
| `mklink /D` as the required step | Needs elevation. Use a junction or robocopy. |
| A newer Premiere for testing | `07` §7 already says test on 22.3.1 only. |

## Installation

```bash
# Relay (host machine only)
cd premiere-collab/relay
npm init -y
npm install --save-exact ws@8.22.0

# Panel: no npm. Vendor three files by hand:
#   panel/js/CSInterface.js  <- https://github.com/Adobe-CEP/CEP-Resources/blob/master/CEP_11.x/CSInterface.js  (v11.0.0)
#   panel/jsx/json2.js       <- https://github.com/douglascrockford/JSON-js/blob/master/json2.js               (2023-05-10)
#   panel/CSXS/manifest.xml  <- the manifest above

# Tests
node --test test/

# Per machine, once (PowerShell; elevated only for the firewall rule)
powershell -ExecutionPolicy Bypass -File scripts/install.ps1
```

## Open items for the roadmap

- **First-hour checks (from `08` §12) still own the unknowns:** the panel actually loads; `ws://<host IP>:8080` works from `file://`; `nodeId` stability; events firing per edit kind; `setValue` effect on the Program monitor.
- **Not settled by this research:** whether a changed `.jsx` needs a Premiere restart, whether CEP follows a junction, whether quick tunnels pass WebSockets on the venue network, the `--protocol http2` flag.
- Have a deploy path that does not depend on any of these: `install.ps1` with robocopy, hotspot as network fallback, and a local run of the relay on `ws://localhost` with `fake-peer.js` for demo rehearsal on one machine.

## Sources

- Installed Premiere 22.3.1 at `C:\Program Files\Adobe\Adobe Premiere Pro 2022\` (CEPHtmlEngine 11.3.0, libcef Chromium 88.0.4324.182, `ScriptLayerPPro.dll` event strings, `PlugPlugExternalObject.dll`). HIGH.
- Installed Adobe panel manifest `com.adobe.ccx.start-2.16.0` (manifest 6.0, PPRO `[14.3,99.9]`, CSXS 6.0). HIGH.
- CEP 11.1 HTML Extension Cookbook (Adobe-CEP/CEP-Resources, `CEP_11.x/Documentation`): CEF 88, Node 15.9.0, PlayerDebugMode, `.debug`, manifest rules, CEF flags, extension folders, `evalScript`. HIGH. https://github.com/Adobe-CEP/CEP-Resources/tree/master/CEP_11.x
- `CSInterface.js` v11.0.0, CEP_11.x. HIGH. https://github.com/Adobe-CEP/CEP-Resources/blob/master/CEP_11.x/CSInterface.js
- Adobe PProPanel sample, `manifest.xml`, `Premiere.jsx` (event binding, `PlugPlugExternalObject`, `CSXSEvent`). HIGH. https://github.com/Adobe-CEP/Samples/tree/master/PProPanel
- `json2.js` 2023-05-10. HIGH. https://github.com/douglascrockford/JSON-js
- `ws` 8.22.0 from the npm registry (version, `engines`, peer deps, publish dates) and release notes. HIGH. https://github.com/websockets/ws/releases
- Cloudflare quick tunnel docs (limits, command). MEDIUM. https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/do-more-with-tunnels/trycloudflare/
- Cloudflare WebSockets doc (proxy support, idle close, heartbeat advice). MEDIUM (does not mention Tunnel). https://developers.cloudflare.com/network/websockets/
- cloudflared downloads page (Windows exe/MSI, no auto-update). MEDIUM. https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/downloads/
- Bolt CEP README (2024-or-later target, Vite/TS). MEDIUM. https://github.com/hyperbrew/bolt-cep
- ExtendScript Debugger notes from Adobe community threads and scripting guides. LOW to MEDIUM. https://community.adobe.com/t5/premiere-pro-discussions/create-a-premiere-pro-extension-in-2023/m-p/14099391
- Existing team research: `research/live-collab/07-premiere-pro-22-cep.md`, `08-mvp.md`.

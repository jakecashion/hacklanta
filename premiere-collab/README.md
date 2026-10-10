# Premiere Live Collab

Two editors, one Premiere 22.3.1 timeline, live. CEP 11 panel + Node `ws` relay.

```
panel/    CEP panel (copy into %APPDATA%\Adobe\CEP\extensions)
relay/    Node relay, runs on the host laptop only
scripts/  install-panel.ps1, firewall.ps1
```

## Setup (each laptop)

```powershell
# Dev machine (junction, edits apply on panel reload):
powershell -ExecutionPolicy Bypass -File scripts\install-panel.ps1 -Link
# Guest / second laptop (copy; re-run after each change):
powershell -ExecutionPolicy Bypass -File scripts\install-panel.ps1
```

Restart Premiere, then **Window > Extensions > Live Collab**. If the panel does not show up with `-Link`, run without it (CEP may not follow junctions).

Debug the panel: open `http://localhost:8088` in Chrome.

## Host laptop only

```powershell
# Once, elevated PowerShell:
powershell -ExecutionPolicy Bypass -File scripts\firewall.ps1
# Each session:
cd relay; npm install; node relay.js
```

The relay prints `Tell the guest: ws://<ip>:8080`. Check it from the guest without Premiere: `node relay\ping.js ws://<ip>:8080` (needs Node), or use **Ping relay** in the panel.

Network order:

1. **Tailscale (primary).** Install Tailscale on both laptops and sign both in to the same account. On the host, `tailscale ip -4` prints its `100.x.y.z` address. The guest connects to `ws://100.x.y.z:8080`; the relay's startup list includes that address too. Works on any network with internet, including venue Wi-Fi that blocks devices from reaching each other. Set it up before the venue.
2. **Phone hotspot with the direct IP (fallback).** Both laptops on the hotspot; the guest uses the host's LAN IP from the relay's startup list. Use it if Tailscale can't sign in or there's no internet.

Run `firewall.ps1` either way: Windows may class the Tailscale adapter as a Public network.

## Phase 1 kill test

1. Open `C:\collab-demo\demo.prproj`, open the sequence so it is active.
2. In the panel: **Ping JSX** (bridge loaded?), **List V1** (clips, values, param names).
3. Set Clip # and click **Run kill test**: Scale 150, Rotation 45, Opacity 50. Watch the Program monitor.
4. Paste the log output into `KILL-TEST.md`, fill in what you saw, commit.
5. **Reset clip** puts the defaults back.

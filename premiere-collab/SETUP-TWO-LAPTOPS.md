# Two-laptop setup walkthrough (Phase 1 Tasks 4 and 5)

Goal: the guest laptop's panel reaches the relay on the host laptop over Tailscale, both laptops open the same demo project, and a Scale/Rotation/Opacity edit syncs both ways.

- **Host** = the laptop that runs the relay (this dev laptop).
- **Guest** = the second laptop. It needs no Node.

Budget about 45 minutes. Do Part A on the host first, because the guest copies its demo project.

---

## Part A: Host laptop

### A1. Build the 4-clip demo sequence (Task 5)

Clip IDs are positions on V1 (`v0:0` to `v0:3`), so both laptops must have the same clips in the same order. You build it once here and copy the project file.

1. Open `C:\collab-demo\demo.prproj` in Premiere.
2. In the Project panel, **File > Import** (Ctrl+I) and go to
   `C:\Users\Public\Documents\Adobe\Premiere Pro\22.0\Tutorial\Going Home project\Footage\`.
   Pick 3 more clips, for example `A001_C064_09224Y_001.mp4`, `A002_C009_092221_001.mp4`, `A003_C021_0923NJ_001.mp4`.
   This is Premiere's own tutorial footage, so the guest laptop should already have the same files at the same path.
3. Drag them onto **V1** of **Sequence 01**, one after another, after the existing clip. All 4 clips go on V1, none on V2.
4. Rename each clip **in the timeline** (right-click the clip > **Rename**), left to right: `Hero`, `Logo`, `Card`, `BG`. The change feed shows these names.
5. For each clip, check in **Effect Controls**:
   - Motion > Scale 100, Rotation 0; Opacity 100.
   - **Uniform Scale** is ticked.
   - No stopwatch is turned on (blue) next to Scale, Rotation or Opacity. A keyframed value can't be synced.
6. **File > Save** (Ctrl+S). Close Premiere.
7. Copy the saved project into the repo so the guest gets it with the code (A4 pushes it):
   ```powershell
   Copy-Item C:\collab-demo\demo.prproj C:\Users\jakca\Development\hacklanta\premiere-collab\demo\demo.prproj
   cd C:\Users\jakca\Development\hacklanta
   git add premiere-collab/demo/demo.prproj
   git commit -m "demo: 4-clip demo sequence"
   ```
   The repo holds only the project file. The footage stays in Premiere's tutorial folder on each laptop.

**Check:** the panel's **List V1** button (next time Premiere is open) shows 4 clips with IDs `v0:0` to `v0:3`.

### A2. Install Tailscale

1. Download and install from https://tailscale.com/download/windows.
2. Click the Tailscale icon in the system tray and choose **Log in**. Sign in with the account both laptops will share (Google, Microsoft or GitHub).
3. Get the host's Tailscale IP. In PowerShell:
   ```powershell
   tailscale ip -4
   ```
   It prints an address like `100.101.102.103`. **Write it down: the guest types this.**

### A3. Firewall rule (once, admin)

1. Start menu > type `PowerShell` > right-click **Windows PowerShell** > **Run as administrator**.
2. Run:
   ```powershell
   powershell -ExecutionPolicy Bypass -File C:\Users\jakca\Development\hacklanta\premiere-collab\scripts\firewall.ps1
   ```
3. Check it:
   ```powershell
   netsh advfirewall firewall show rule name="Live Collab relay 8080"
   ```
   **You should see** `Enabled: Yes`, `Direction: In`, `Profiles: Domain,Private,Public`, `LocalPort: 8080`, `Action: Allow`.

The rule allows all network profiles because Windows may class the Tailscale adapter, venue Wi-Fi or a hotspot as Public.

### A4. Get the latest code onto GitHub

The guest installs from the repo, so push the newest commits from the host:
```powershell
cd C:\Users\jakca\Development\hacklanta
git push
```
(If you can't push, copy the `premiere-collab` folder to the guest by USB instead.)

### A5. Demo project for the guest

Nothing to do if you did A1 step 7 and A4: the project is in the repo at `premiere-collab/demo/demo.prproj`. (Without Git on the guest, copy `C:\collab-demo\demo.prproj` to the USB stick too.)

### A6. Start the relay

In a normal (not admin) PowerShell:
```powershell
cd C:\Users\jakca\Development\hacklanta\premiere-collab\relay
node relay.js
```
**You should see** `Relay listening on port 8080` and one `Tell the guest:` line per network, including the Tailscale `100.x` address. Leave this window open.

---

## Part B: Guest laptop

### B1. Premiere and Adobe sign-in

1. Check that Premiere Pro **22.3.1** is installed (Help > About Premiere Pro).
2. Install the Creative Cloud desktop app from https://creativecloud.adobe.com/apps/download/creative-cloud and sign in. Without this, Premiere quits right after the splash screen (the problem the host had).
3. Premiere's UI must be **English**: the bridge finds Scale, Rotation and Opacity by their English names.

### B2. Get the repo

With Git:
```powershell
cd $HOME
git clone https://github.com/jakecashion/hacklanta.git
cd hacklanta
git checkout research
```
Without Git: copy the `premiere-collab` folder from the USB stick to any folder, for example `C:\hacklanta\premiere-collab`.

### B3. Install the panel

In a normal PowerShell, from the repo folder (adjust the path if you copied it elsewhere):
```powershell
powershell -ExecutionPolicy Bypass -File .\premiere-collab\scripts\install-panel.ps1
```
Do **not** use `-Link` here. **You should see:**
```
PlayerDebugMode = 1 (CSXS.11)
Copied panel to C:\Users\<you>\AppData\Roaming\Adobe\CEP\extensions\com.hacklanta.premierecollab
Restart Premiere, then Window > Extensions > Live Collab
```
After any later code change, run this script again and click **Reload panel**.

### B4. Put the demo project in place

1. Copy the project from the repo so it sits at exactly `C:\collab-demo\demo.prproj`. From the repo folder:
   ```powershell
   New-Item -ItemType Directory -Force C:\collab-demo | Out-Null
   Copy-Item .\premiere-collab\demo\demo.prproj C:\collab-demo\demo.prproj
   ```
2. Check the tutorial footage exists at the same path as on the host:
   ```powershell
   Test-Path "C:\Users\Public\Documents\Adobe\Premiere Pro\22.0\Tutorial\Going Home project\Footage\A001_C037_0921FG_001.mp4"
   ```
   It must print `True`. If it prints `False`, copy the 4 clips you used in A1 into that same folder.
3. Open the project in Premiere. If Premiere asks to **Link Media**, the footage path differs; fix step 2 rather than relinking by hand.
4. Don't change anything in the timeline before joining. Phase 2 has no join snapshot yet, so both laptops must start identical.

### B5. Install Tailscale with the same account

1. Install from https://tailscale.com/download/windows and log in with **the same account** as the host.
2. Check that both laptops are on the same tailnet:
   ```powershell
   tailscale status
   ```
   **You should see** both machine names with their `100.x` addresses.
3. Check the guest reaches the host:
   ```powershell
   tailscale ping 100.101.102.103
   ```
   (Use the host IP from A2.) **You should see** `pong from ...`. If it says `via DERP`, the laptops are connected through Tailscale's relay servers, which is fine; it just adds a little latency.

---

## Part C: Connection and sync test

### C1. Ping the relay from the guest panel (Task 4)

1. Guest: restart Premiere, open `C:\collab-demo\demo.prproj`, double-click **Sequence 01**, open **Window > Extensions > Live Collab**.
2. **Host IP:** type the host's Tailscale IP (`100.101.102.103`, no `ws://`, no spaces). **Name:** for example `Guest`.
3. Click **Connect**, then **Ping relay**.

**You should see:**
- Guest panel: badge "Connected as Guest", log `Pong from relay: round trip N ms` (expect under 100 ms; up to a few hundred over DERP).
- Host relay window: `+ connection from 100.x.y.z` and `100.x.y.z is "Guest"`.

That completes Task 4's main check.

### C2. Host connects too

On the host: open the demo project and sequence, open the panel, Host IP `localhost`, Name e.g. `Host`, **Connect**.
Both panels' peers line: `Here: Guest, Host` (order may differ).

### C3. Sync both ways

Put the playhead over **Hero** on both laptops.

1. **Host → guest:** on the host, select Hero, Effect Controls > Scale, type `150`, Enter. Within about 1 s the guest's Program monitor shows Hero bigger, and both feeds show `Host set Hero Scale to 150 (rev N)`.
2. **Guest → host:** on the guest, Rotation `45`, Enter. It shows on the host within about 1 s.
3. **Opacity:** either side, Opacity `40`.
4. **Conflict:** both of you type a different Opacity on Hero and press Enter at about the same moment. After 2 s both laptops show the **same** value: the one with the higher rev in the feed.
5. **No echo:** stop editing and watch the relay window for 10 s. No new `rev` lines should appear.

### C4. Fallback check: hotspot with the direct IP (once)

1. Turn on your phone hotspot and connect both laptops to it.
2. Host: restart the relay (`Ctrl+C`, then `node relay.js`). Note the `Tell the guest:` line that is **not** `100.x` (for example `192.168.43.12`, from the Wi-Fi adapter).
3. Guest: **Disconnect**, type that IP, **Connect**, **Ping relay**.

**You should see** a pong. If it times out, the hotspot isolates devices, so on stage rely on Tailscale (which still works over the hotspot's internet).

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Guest log: `Socket error` right after Connect | Relay not running, wrong IP, or firewall | Check the relay window is open; retype the IP from `tailscale ip -4`; rerun A3 and check the rule |
| `tailscale ping` works but the panel can't connect | Firewall rule missing on the host | A3, then **Connect** again |
| `tailscale status` doesn't list the other laptop | Different Tailscale accounts | Log both into the same account |
| Panel not in Window > Extensions | Premiere not restarted, or debug mode not set | Rerun B3, restart Premiere fully |
| Premiere quits after the splash | Not signed in to Adobe | B1 step 2 |
| Guest log: `Scan error: No active sequence` | Sequence not open | Double-click Sequence 01 |
| Edit shows in the feed but the picture doesn't change | Playhead isn't over that clip | Move the playhead onto the clip |
| Edit lands on the wrong clip | Clip order on V1 differs | Re-copy `demo.prproj` from the repo (A1 step 7, B4) |
| Feed shows `Apply failed ... Param Scale not found` | Premiere UI not in English | Switch Premiere's language to English |

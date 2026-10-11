# Two-laptop live sync test plan

Goal: prove that Scale, Rotation and Opacity sync both ways between two real laptops quickly, correctly and without echo, and find the failure modes before the judges do.

Do this **after** `SETUP-TWO-LAPTOPS.md` Parts A to C2 pass (panel loads on both, guest pings the relay, both panels show `Here: Guest, Host`). C3 in that file is a 5-minute smoke test; this plan replaces it.

- **H** = host laptop (runs the relay). **G** = guest laptop.
- Two people, one at each laptop. One of them reads the steps out loud.
- Budget: Tier 1 about 20 min, Tier 2 about 20 min, Tier 3 about 20 min. **If time is short, Tier 1 is the only must.**
- Write results in the table at the bottom (Pass / Fail / Note) as you go.

---

## 0. Reset before every tier (2 min)

There's no join snapshot yet (that's Phase 3), so both laptops must start identical.

1. Both: close the project without saving, then reopen the clean `C:\collab-demo\demo.prproj`. If it was saved with edits, copy it from the repo again (`SETUP-TWO-LAPTOPS.md` B4).
2. Both: double-click **Sequence 01**. Put the playhead over **Hero**. Open **Effect Controls**.
3. H: restart the relay (`Ctrl+C`, `node relay.js`) so revs start at 1 again and are easy to read.
4. Both: **Connect** in the panel (H: `localhost`, G: host's `100.x` IP).
5. **Check:** both panels show `Here: Guest, Host` and `Syncing: rev 0, 0 pending`. Both **List V1** outputs show `v0:0` Hero, `v0:1` Logo, `v0:2` Card, `v0:3` BG.

**What to watch the whole time:**
- The **relay window** prints one `rev N: <who> <clip> <field> = <value>` line per edit. A line nobody typed means an echo or a revert.
- The panel's **status line** should return to `0 pending` within about 1 s of each edit.
- The **Changes feed** on both panels should show the same rev numbers with the same values.

---

## Tier 1: Core sync (demo path, must pass)

| ID | Who | Steps | Expected |
|----|-----|-------|----------|
| 1.1 | H | Hero: Scale `150`, Enter | G's Program monitor shows Hero bigger within 2 s. Both feeds: `... set Hero Scale to 150 (rev 1)` (H sees `You`). Relay prints rev 1 only. |
| 1.2 | G | Hero: Rotation `45`, Enter | H shows the rotation within 2 s. rev 2. |
| 1.3 | H | Hero: Opacity `40`, Enter | G shows it within 2 s. rev 3. |
| 1.4 | G, H, G | Select Logo: Scale `120` (G). Select Card: Rotation `-20` (H). Select BG: Opacity `60` (G). Move the playhead over each clip on the other laptop to look. | Each edit lands on the **same named clip** on the other laptop. This checks the `v0:N` position mapping. |
| 1.5 | H, then G | Demo values on Hero: Scale `200`, Rotation `90`, Opacity `0`. Then G puts them back: `100`, `0`, `100`. | Opacity 0 makes Hero vanish on both; it comes back on both. Ends at 100 / 0 / 100 on both. |
| 1.6 | Both | **Latency.** Prop a phone so it films both screens. Do 5 edits, alternating sides, big visible values. Play the video back and count from Enter on one screen to the change on the other. | Every edit is 2 s or less. Expect about 0.5 to 1.5 s (1 s poll plus network). Write the worst time in the table. |
| 1.7 | Both | **No echo.** Hands off for 15 s. | No new relay lines. Both status lines stay at the same rev with `0 pending`. |
| 1.8 | Both | **Final compare.** Click each of the 4 clips and read Scale / Rotation / Opacity in Effect Controls. | All 12 values match between the laptops. |

**If 1.1 to 1.3 fail, stop.** Read the troubleshooting table in `SETUP-TWO-LAPTOPS.md`, then grab the logs (see "When something fails").

---

## Tier 2: Conflicts and fast edits

Reset (section 0) first.

| ID | Who | Steps | Expected |
|----|-----|-------|----------|
| 2.1 | Both | **Same field, same moment.** Both select Hero. One person counts "3, 2, 1, go". On "go", H types Opacity `30` and G types `70`, both press Enter. Do it 3 times with different values. | After 2 s both laptops show the **same** Opacity, and it's the value with the **higher rev** in the feed. Never one value on H and another on G. |
| 2.2 | Both | **Different fields, same clip, same moment.** On "go": H sets Hero Scale `130`, G sets Hero Rotation `30`. | Both edits apply on both laptops (Scale 130 **and** Rotation 30). Neither is lost. |
| 2.3 | Both | **Different clips, same moment.** H: Logo Scale `80`. G: Card Opacity `50`. | Both land on both laptops. |
| 2.4 | H | **Rapid typing.** On Hero Scale, type `110` Enter, `120` Enter, `130` Enter, `140` Enter, `150` Enter as fast as you can. | G ends at `150`. G may skip some middle values (the panel samples once per second); that's fine. Relay stops printing within about 2 s. |
| 2.5 | G | **Scrub drag.** Drag the blue Scale number on Hero left and right for about 3 s, then let go. | H follows in steps (about 1 per second). After you let go, both show the same final value and the relay goes quiet within about 2 s. |
| 2.6 | Both | **Ping-pong.** For 30 s, take turns changing Hero Rotation every 2 to 3 s (H, G, H, G ...). | Every change shows on the other side. Ends equal. No runaway rev counter after you stop. |
| 2.7 | Both | Run 1.7 (no echo) and 1.8 (compare all 12 values). | Quiet relay, all 12 values match. |

---

## Tier 3: Premiere behavior and connection loss

Reset (section 0) first. Many of these record **what happens** rather than pass/fail; known limits are marked. Write down what you see.

### Premiere-side

| ID | Who | Steps | Expected |
|----|-----|-------|----------|
| 3.1 | H | **Undo.** Set Hero Scale `150`, wait for G to match, then `Ctrl+Z` on H. | G goes back to 100 as well (undo shows up as a new edit, new rev). |
| 3.2 | G | **Undo a remote edit.** After H changes Hero Opacity to `50` and G matches, press `Ctrl+Z` on G. | Record: does G's undo touch the remote edit? If it does, G sends Opacity back and H follows. Either way both must end equal. |
| 3.3 | H | **Drag in the Program monitor.** Click the word **Motion** in Effect Controls so handles show on Hero, then drag a corner handle (Scale) and the rotate handle. | Scale and Rotation sync. **Position does not sync** (known limit, v2), so after moving the clip it sits in a different place on G. |
| 3.4 | G | **Clip not under the playhead.** With the playhead on Hero, select BG and set Opacity `20`. | On H, the edit shows in the feed. Move H's playhead to BG: it is 20. |
| 3.5 | H | **Decimals.** Hero Scale `123.45`, Opacity `33.3`. | G shows the same values. No echo afterwards (1.7): Premiere's rounding must not trigger a resend. |
| 3.6 | G | **Rotation out of range.** Hero Rotation `450`, then `-30`. | Record what G and H show (Premiere may display `1x90°`). Both must match, and no echo. |
| 3.7 | H | **Uniform Scale off.** On Card, untick Uniform Scale and change Scale Height. | Known limit: not synced. Record whether it causes any errors in the panel log. Tick Uniform Scale back on. |
| 3.8 | H | **Keyframes.** On Logo, turn on the stopwatch next to Opacity, then on G set Logo Opacity `25`. | Known limit: keyframed values can't be synced. Record what H's panel logs and whether H then sends anything back. Then turn the stopwatch off and reset (section 0). |
| 3.9 | G | **Sequence closed during a remote edit.** G closes the Sequence 01 tab in the Timeline. H sets Hero Scale `175`. G reopens Sequence 01 and waits 3 s. | G's log shows `Apply failed` for the edit. After G reopens, the relay shows **no** new rev with 100, and H keeps Scale 175 (fixed 2026-10-10: a failed apply used to send the old value back and undo H's edit). G stays at 100 until H retypes the value: known limit, same recovery as 4.1. |

### Connection loss

There's no join snapshot or Rejoin yet, so after any reconnect the reconnecting laptop takes **its own current timeline** as the starting point. Expect divergence in 4.1 and 4.2; that's what Phase 3 fixes. These tests show how bad it is and how to recover on stage.

| ID | Who | Steps | Expected |
|----|-----|-------|----------|
| 4.1 | G, then H | **Missed edits.** G clicks **Disconnect**. H sees `Here: Host`. H sets Hero Scale `80`. G clicks **Connect**. | Known limit: G stays at Scale 100 (divergent). Then H types `81`: G now follows. **Recovery on stage: retype the value on the host.** |
| 4.2 | G | **Edits while offline.** G clicks Disconnect, sets Hero Rotation `15`, clicks Connect. | Known limit: H never gets 15. Record it. |
| 4.3 | G | **Wi-Fi drop.** Turn off G's Wi-Fi for 10 s, then back on. Watch both badges and the relay window for 60 s. | Record: how long until G's badge says Not connected (could be never on its own), and how long until the relay prints `- Guest left` (up to about 40 s). After clicking Connect again, 1.1 works. |
| 4.4 | H | **Relay restart.** `Ctrl+C` the relay, start it again. | Both badges go to Not connected. Both click Connect; revs start at 1 again and 1.1 to 1.3 work. |
| 4.5 | G | **Panel reload.** Click **Reload panel** mid-session, then Connect. | Same as a disconnect; sync works again afterwards. |
| 4.6 | Both | **Hotspot (fallback network).** Both laptops on the phone hotspot, Tailscale still on, repeat 1.1 to 1.3 and the latency check 1.6. Then once more with the host's direct hotspot IP instead of `100.x`. | Works over both. Write the worst latency for each. |

### Soak (optional, if time allows)

| ID | Who | Steps | Expected |
|----|-----|-------|----------|
| 5.1 | Both | 10 minutes of both people making a random edit every 10 to 20 s, any clip, any field. Then 1.7 and 1.8. | No disconnects, quiet relay at the end, all 12 values match. |

---

## When something fails

Write the test ID and what you saw, then collect:

1. **Host panel log**: `premiere-collab/panel/panel-log.txt` on the host. Claude can read it directly; don't paste it into chat.
2. **Guest panel log**: `%APPDATA%\Adobe\CEP\extensions\com.hacklanta.premierecollab\panel-log.txt` on the guest. Copy it to the host by USB, or commit it to a scratch branch.
3. **Relay window**: a phone photo or a screenshot of the last 30 lines.
4. For latency or visual problems, the phone video.

Then carry on with the next test unless it was Tier 1.1 to 1.3.

---

## Results

Date: ________  Network: Tailscale / hotspot / LAN   Host: ________  Guest: ________

| ID | Result | Notes (values, latency, log lines) |
|----|--------|------------------------------------|
| 1.1 | | |
| 1.2 | | |
| 1.3 | | |
| 1.4 | | |
| 1.5 | | |
| 1.6 | | worst latency: ___ s |
| 1.7 | | |
| 1.8 | | |
| 2.1 | | |
| 2.2 | | |
| 2.3 | | |
| 2.4 | | |
| 2.5 | | |
| 2.6 | | |
| 2.7 | | |
| 3.1 | | |
| 3.2 | | |
| 3.3 | | |
| 3.4 | | |
| 3.5 | | |
| 3.6 | | |
| 3.7 | | |
| 3.8 | | |
| 3.9 | | |
| 4.1 | | |
| 4.2 | | |
| 4.3 | | |
| 4.4 | | |
| 4.5 | | |
| 4.6 | | worst latency, Tailscale: ___ s, direct IP: ___ s |
| 5.1 | | |

**Phase 2 passes** when 1.1 to 1.8 and 2.1, 2.2, 2.7 pass. Everything else feeds the Phase 3 and stretch work (Resync, Rejoin, snapshot join).

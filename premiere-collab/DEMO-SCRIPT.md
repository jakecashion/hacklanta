# Tandem demo script (DEMO-01)

Length: 3 minutes. Audience: Hacklanta judges, Creative track (Adobe).
Editors: **Jake** (host laptop) and **Bradley** (guest laptop).
Project: `C:\collab-demo\demo.prproj` (874ce31). V1: Hero 0 s, Logo 5 s, Card 10 s, BG 15 s.

## 1. Pre-demo checklist

Do these steps in order. Do not skip a step.

1. Host: stop the relay. Start it again: `cd relay; node relay.js`. This clears the op log.
2. Both: close Premiere projects without saving.
3. Both: copy a clean project. `Copy-Item premiere-collab\demo\demo.prproj C:\collab-demo\demo.prproj -Force`.
4. Both: open `C:\collab-demo\demo.prproj`. Open the sequence.
5. Both: in the panel, click **List V1**. Make sure it shows `000f4242`, `000f4263`, `000f4264`, `000f4265`.
6. Host: type `localhost` and `Jake`. Click **Connect**.
7. Guest: type the host Tailscale IP `100.122.228.122` and `Bradley`. Click **Connect**.
8. Both: make sure the badge shows **Connected** and the peers line shows both names.
9. Host: `powershell -ExecutionPolicy Bypass -File cursor\cursor.ps1 -Relay localhost -Name Jake`.
10. Guest: `powershell -ExecutionPolicy Bypass -File cursor\cursor.ps1 -Relay 100.122.228.122 -Name Bradley`.
11. Both: maximize Premiere. Use the same workspace. Show Timeline, Program monitor, Effect Controls, and the Tandem panel.
12. Both: select Hero. Open Effect Controls. Do not touch other keys in the Timeline.
13. Do one small test edit (Opacity 99, then 100). Make sure it syncs both ways.
14. Video only: start screen capture on both laptops, or point one camera at both screens. Viewers must see both screens at the same time.

## 2. Run order (3:00)

### 0:00–0:20 Hook

> "Premiere Pro, now multiplayer. Two editors, one timeline, and you watch each other's changes land live."

Shot: both screens side by side. Both live cursors are visible.

### 0:20–0:50 The problem and who it is for

> "This is for film editors. All of them. Editors have asked for this for years.
> Today, two editors cannot work on one timeline at the same time. Premiere Team Projects locks a sequence to one editor. Productions locks the project. Avid and Resolve lock the bin or the timeline. Everyone else gets read-only and waits. Or they pass project files back and forth, and the last save wipes out the other person's work.
> Adobe's own staff wrote in 2017: 'It's not currently possible for more than one editor to make changes on the same timeline.'
> Tandem fixes that. It is Google Docs for the Premiere timeline."

Shot: optional title card: "Lock. Wait. Send. Merge." then a cut back to both screens.

### 0:50–1:05 Join

> "Bradley is in another place. He connects to my session with a name and my address."

1. Guest clicks **Disconnect**, then **Connect** again. (Or show the connect step from the checklist on video.)
2. Point to both names in both panels.

> "When he joins, his timeline matches mine."

### 1:05–1:55 Movement controls (core)

Each edit is a big jump, so it is easy to see. Say who edits, then wait for the other screen to change.

1. Jake: Hero **Scale** 100 → 200. Bradley's Program monitor changes.
2. Bradley: Hero **Rotation** 0 → 90. Jake's Program monitor changes.
3. Jake: drag Hero **Position** to the top-left corner. Bradley's monitor follows.
4. Bradley: change Hero **Anchor Point**. Jake's monitor follows.
5. Jake: Hero **Opacity** 100 → 0, then back to 100.

> "Every motion control (Position, Scale, Rotation, Anchor Point, Opacity) syncs in about a second, in both directions."

6. Conflict: both set Hero Scale at the same time (Jake 150, Bradley 50).

> "If we both change the same thing, both machines end up with the same answer. No loops, and nothing gets out of sync."

### 1:55–2:25 Timeline (core)

1. Bradley: rename Logo to `Logo FINAL`. Jake's timeline shows the new name.
2. Jake: trim the end of Card. Bradley's clip gets shorter.
3. Bradley: move BG along V1. Jake's clip moves.

> "It's not only effects. It's the cut itself: rename, trim, move, live."

Note: move and trim must pass the guest check (handoff task 5) before the demo. If a step fails in rehearsal, cut it from the live run. For the video, record the take where it works.

### 2:25–2:40 Presence

1. Both: move the mouse over the Timeline. Point at Hero.

> "You see where your partner is working: their cursor and name over your own Premiere."

2. Point to the **Changes** feed: `Bradley set Hero Rotation to 90 (rev 7)`.

> "And every change is in a feed with who made it."

### 2:40–2:55 How it works

> "A Premiere panel on each laptop. A small relay on the host laptop numbers every edit and sends it to the other editor. No cloud server. It runs on Premiere 2022 today, over any internet connection with Tailscale."

Shot (video): one diagram. Premiere + panel ↔ relay (host) ↔ panel + Premiere.

### 2:55–3:00 Close

> "Next: more editors, After Effects, and the newest Premiere. Tandem: edit together, live."

## 3. If something fails on stage

| Problem | Do this |
|---|---|
| Edit does not show on the other laptop | Wait 2 s. Do the edit again with a bigger value. |
| Badge shows Not connected | Click **Connect** again. Keep talking. |
| Cursor helper is gone | Skip the cursor and point at the feed. |
| Clip changed by itself after a reconnect | Old op log. Do not fix it on stage. Move on to the next step. |
| Move or trim does not sync | Say "rename and effects are the core" and skip to Presence. |

## 4. Sources for the "editors have wanted this" claim

- Adobe Community, 2017: "How can two editors work on the same timeline simultaneously?" Adobe staff: "It's not currently possible for more than one editor to make changes on the same timeline (sequence) in Team Projects." https://community.adobe.com/questions-79/how-can-two-editors-work-on-the-same-timeline-simultaneously-1498461
- Adobe Community: requests to turn off Team Projects sequence locking (added December 2022). https://community.adobe.com/questions-79/turn-off-team-project-sequence-locking-1498187
- Frame.io, Premiere Productions guide: project locking, one editor changes a project at a time. https://blog.frame.io/2024/09/30/ultimate-guide-to-premiere-pro-productions/
- Avid bin locking: first user gets write access, others read-only (red lock). https://elements.tv/blog/bin-locking-overview-and-troubleshooting-in-avid-media-composer/
- DaVinci Resolve collaboration: automatic bin and timeline locking. https://www.blackmagicdesign.com/products/davinciresolve/collaboration

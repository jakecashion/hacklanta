# Tandem demo script (DEMO-01)

This file holds the parts that both scripts use: the pre-demo checklist and the sources.

- **Recorded video** (Devpost, cut from separate takes): [VIDEO-SCRIPT.md](VIDEO-SCRIPT.md)
- **Live pitch** (judging, 9:30 AM, 3 min + 2 min Q&A): [PITCH-SCRIPT.md](PITCH-SCRIPT.md)

Editors: **Jake** (host laptop) and **Bradley** (guest laptop).
Project: `C:\collab-demo\demo.prproj` (874ce31). V1: Hero 0 s, Logo 5 s, Card 10 s, BG 15 s.

## 1. Pre-demo checklist

Do these steps in order. Do not skip a step. Run the commands from the `premiere-collab` folder.

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
14. Video only: do the recording setup in [VIDEO-SCRIPT.md](VIDEO-SCRIPT.md) section 1.

## 2. Sources for the "editors have wanted this" claim

- Adobe Community, 2017: "How can two editors work on the same timeline simultaneously?" Adobe staff: "It's not currently possible for more than one editor to make changes on the same timeline (sequence) in Team Projects." https://community.adobe.com/questions-79/how-can-two-editors-work-on-the-same-timeline-simultaneously-1498461
- Adobe Community: requests to turn off Team Projects sequence locking (added December 2022). https://community.adobe.com/questions-79/turn-off-team-project-sequence-locking-1498187
- Frame.io, Premiere Productions guide: project locking, one editor changes a project at a time. https://blog.frame.io/2024/09/30/ultimate-guide-to-premiere-pro-productions/
- Avid bin locking: first user gets write access, others read-only (red lock). https://elements.tv/blog/bin-locking-overview-and-troubleshooting-in-avid-media-composer/
- DaVinci Resolve collaboration: automatic bin and timeline locking. https://www.blackmagicdesign.com/products/davinciresolve/collaboration

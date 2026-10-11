# Tandem video script (recorded sections)

Use: the Devpost demo video. We record each section as a separate take, then cut the takes together in Premiere.
Target length: 2:30 to 3:00. Check the Devpost limit before the final export.
Editors: **Jake** (host laptop) and **Bradley** (guest laptop).
Live judging uses a different script: [PITCH-SCRIPT.md](PITCH-SCRIPT.md).

## 1. Recording setup

Do the shared checklist in [DEMO-SCRIPT.md](DEMO-SCRIPT.md) section 1 first. Then do these steps.

1. Both: start a screen recorder on your own laptop (OBS, or Xbox Game Bar with Win+Alt+R). Record the full screen, 1080p, 30 fps.
2. Both: turn off notifications (Focus assist on).
3. Both: hide the PowerShell windows (relay and cursor helper) behind Premiere. Keep them open.
4. At the start of each take, Jake sets Hero **Opacity** to 0, then back to 100. This is the sync mark. In the edit, line up the two recordings on the frame where Bradley's Program monitor goes black.
5. Record voiceover separately, after the screen takes, on one good microphone. Read the lines in section 3.

**Rules for each take:**

- Say the take name out loud before you start (for example "V4, take 2").
- Wait 2 s after each edit lands on the other screen. Then do the next edit.
- If an edit does not land, stop. Restart the take. Do not fix it on camera.
- Before you record the next section, look at Hero on both laptops. If they do not match, reopen the clean project (checklist steps 2 to 5).

## 2. Edit layout

- Default frame: both screens side by side (host left, guest right), each scaled to 50%. Label them **Jake** and **Bradley**.
- When one edit is the subject, zoom in on the Program monitor or the Timeline of the screen that changes.
- Put a small text label on each edit, for example "Bradley: Rotation 90".

## 3. Sections

| # | Section | Length | Record |
|---|---|---|---|
| V1 | Hook | 0:15 | Screen |
| V2 | Problem | 0:30 | Title cards (no screen) |
| V3 | Join | 0:15 | Screen |
| V4 | Movement controls | 0:40 | Screen |
| V5 | Conflict | 0:10 | Screen |
| V6 | Timeline edits | 0:25 | Screen |
| V7 | Cursor and feed | 0:15 | Screen |
| V8 | How it works | 0:15 | Diagram (no screen) |
| V9 | Close | 0:10 | Screen or title card |

### V1. Hook (0:15)

Do: both editors move the mouse over Premiere. Jake sets Hero Scale to 200.

> "Premiere Pro, now multiplayer. Two editors, one timeline, and you watch each other's changes land live."

### V2. Problem (0:30)

Do: no screen recording. Make title cards in Premiere: "Team Projects: sequence locked", "Productions: project locked", "Avid: bin locked", "Resolve: timeline locked". End on the 2017 Adobe quote.

> "Two editors cannot work on one timeline at the same time. Premiere Team Projects locks the sequence. Productions locks the project. Avid and Resolve lock the bin or the timeline. Everyone else waits.
> In 2017, Adobe's own staff wrote: 'It's not currently possible for more than one editor to make changes on the same timeline.' Editors have asked for this for years."

Sources: [DEMO-SCRIPT.md](DEMO-SCRIPT.md) section 2.

### V3. Join (0:15)

Do:

1. Bradley's panel shows **Not connected**.
2. Bradley types the host IP and `Bradley`. Bradley clicks **Connect**.
3. Zoom in on both peers lines: `Here: Jake, Bradley`.

> "Bradley joins my session with his name and my address. Now we are both in one cut."

### V4. Movement controls (0:40)

Do these edits on Hero, in this order. Each edit is a big change, so it is easy to see.

1. Jake: **Scale** 100 → 200. Bradley's Program monitor changes.
2. Bradley: **Rotation** 0 → 90. Jake's Program monitor changes.
3. Jake: drag **Position** to the top-left corner. Bradley's monitor follows.
4. Bradley: change **Anchor Point**. Jake's monitor follows.
5. Jake: **Opacity** 100 → 30.

> "Every motion control syncs in about a second, in both directions: Position, Scale, Rotation, Anchor Point, and Opacity."

### V5. Conflict (0:10)

Do: count down out loud, "3, 2, 1". On "1", Jake types Scale 150 and Bradley types Scale 50. Both press Enter. Hold 2 s on both screens.

> "If we both change the same thing at the same time, both machines end up with the same answer."

### V6. Timeline edits (0:25)

Do:

1. Bradley: rename Logo to `Logo FINAL`. Zoom in on Jake's timeline.
2. Jake: trim the end of Card. Zoom in on Bradley's timeline.
3. Bradley: move BG along V1. Zoom in on Jake's timeline.

> "It is not only effects. It is the cut itself: rename, trim, and move, live."

If trim or move fails after 3 takes, keep only the rename and cut the trim and move lines.

### V7. Cursor and feed (0:15)

Do:

1. Bradley: move the mouse over the Timeline and stop on Hero. Zoom in on Jake's screen: Bradley's named pointer is on Hero.
2. Zoom in on the **Changes** feed. Show the newest lines.

> "You see where your partner is working: their pointer and name, on your own Premiere. And every change goes into a feed with who made it."

### V8. How it works (0:15)

Do: one diagram: Premiere + panel ↔ relay (host laptop) ↔ panel + Premiere. Tailscale between the laptops.

> "A panel inside Premiere on each laptop. A small relay on the host laptop numbers every edit and sends it to the other editor. No cloud server. It runs on Premiere 2022 today."

### V9. Close (0:10)

Do: both screens side by side, both cursors moving. End card: "Tandem. Edit together, live."

> "Next: more editors, and After Effects. Tandem: edit together, live."

## 4. After recording

1. Close the demo project without saving.
2. Do the voiceover. Cut it in, then fit the screen takes to it.
3. Export H.264 1080p. Upload it. Put the link on Devpost.

# Tandem live pitch script (judging, 9:30 AM)

Format: 3 minutes to pitch, then 2 minutes of Q&A. Two judges at one desk.
Speaker: **Jake** talks and drives the host laptop. **Bradley** drives the guest laptop and talks only where the script says.
Both laptops sit on the desk, side by side, screens toward the judges.
Recorded video: [VIDEO-SCRIPT.md](VIDEO-SCRIPT.md). Shared checklist: [DEMO-SCRIPT.md](DEMO-SCRIPT.md).

## 1. Before you get in line

1. Do the shared checklist in [DEMO-SCRIPT.md](DEMO-SCRIPT.md) section 1. Both laptops are connected before you get in line. Do not show the connect step live.
2. Make sure both laptops have internet (venue Wi-Fi or phone hotspot). Tailscale needs it.
3. Plug in both chargers if you can. Set sleep to **Never**.
4. Have the recorded video ready on a phone as the backup.
5. In line: every 5 minutes, look at both badges. If a badge shows **Not connected**, click **Connect** again.

## 2. At the desk (do in 15 s, before you talk)

1. Put the laptops side by side: host left, guest right.
2. Both: look at Hero in the Program monitor. If the two do not match, Bradley disconnects and connects again.

## 3. Run order (3:00)

### 0:00–0:15 Hook

> "Premiere Pro, now multiplayer. Two editors, one timeline, and you watch each other's changes land live."

Bradley moves his mouse over Premiere. Jake points at Bradley's named pointer on the host screen.

### 0:15–0:40 Problem

> "Two film editors cannot work on one timeline at the same time. Premiere Team Projects locks the sequence. Avid and Resolve lock the bin or the timeline. The second editor waits. Adobe's own staff said in 2017 it is not possible. Editors have asked for it for years. We built it."

### 0:40–1:40 Movement controls (live)

Say each edit before you do it. Wait for the other screen to change.

1. Jake: Hero **Scale** 100 → 200.
   > "I make it bigger. Watch Bradley's screen."
2. Bradley: Hero **Rotation** 0 → 90.
   > "Bradley turns it. It lands on mine."
3. Jake: drag Hero **Position** to the top-left corner.
4. Jake: **Opacity** 100 → 30.
   > "Position, Scale, Rotation, Anchor Point, Opacity: every motion control, both ways, in about a second."
5. Conflict: Jake says "3, 2, 1". Jake types Scale 150, Bradley types Scale 50. Both press Enter.
   > "We both changed the same thing at the same time. Both machines agree on one answer."

### 1:40–2:10 Timeline (live)

1. Bradley: rename Logo to `Logo FINAL`.
2. Jake: trim the end of Card.
3. Bradley: move BG along V1.

> "It is not only effects. It is the cut itself: rename, trim, and move."

If trim or move failed in rehearsal, do only the rename and say: "Rename syncs the same way."

### 2:10–2:25 Presence and feed

1. Bradley: put his pointer on Hero.
2. Jake: point at the **Changes** feed.

> "I see where my partner works, and every change has a name on it."

### 2:25–2:45 How it works

> "A panel inside Premiere on each laptop. A small relay on my laptop numbers every edit and sends it to the other editor. If two edits collide, the higher number wins on both machines. No cloud server. It runs on Premiere 2022 today, over the internet with Tailscale."

### 2:45–3:00 Close

> "Writers have Google Docs. Designers have Figma. Editors now have Tandem. Next: more editors and After Effects. Thank you."

## 4. If something fails

| Problem | Do this |
|---|---|
| An edit does not show on the other laptop | Wait 2 s. Do it again with a bigger value. Keep talking. |
| A badge shows **Not connected** | Click **Connect** again. Say "it reconnects in a second." |
| No internet at the desk | Turn on the phone hotspot. If that fails, play the video on the phone. |
| The cursor helper is gone | Skip the cursor. Point at the feed. |
| A clip changes by itself after a reconnect | Old op log. Do not fix it. Go to the next step. |
| The demo is broken | Say "here is the recorded run" and play the video. Keep to 3:00. |

## 5. Q&A answers (keep each under 20 s)

**How do you handle two edits at the same time?**
The relay gives every edit a number. For each field, the edit with the higher number wins, on both laptops. So both machines always end the same.

**Why not Team Projects?**
Team Projects locks a sequence to one editor. Everyone else is read-only. Tandem has no lock: both editors change the same sequence at the same time.

**How fast is it?**
About one second. The panel reads the timeline once a second. The network adds a fraction of a second on Tailscale.

**What syncs today?**
Position, Scale, Rotation, Anchor Point, and Opacity, plus clip rename, trim, and move on the timeline. Also the live cursor and the change feed.

**What does not sync yet?**
Keyframes, other effects, audio levels, and adding or removing clips. Premiere's scripting API cannot change keyframes.

**Does it need a server?**
No. The relay runs on the host laptop. Tailscale connects the laptops over any internet connection. A hosted relay is a next step.

**Why Premiere 2022 and not the newest version?**
Our laptops run Premiere 22. Adobe's new UXP plugins need Premiere 25.6, so we used CEP panels, which still work in new versions. A UXP version is on our list.

**More than two editors?**
The relay already sends every edit to everyone. We tested with two. More editors, with a color each, is next.

**What happens if someone joins late?**
The relay keeps a log of edits. A new editor gets the host's timeline when they join.

**Who is it for?**
Any team that edits together: an assistant and a lead editor in one sequence, or a director who gives notes and sees them happen live.

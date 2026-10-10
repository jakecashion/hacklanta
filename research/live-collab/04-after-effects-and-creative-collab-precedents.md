# After Effects extensibility and precedents for live collaboration in creative tools

Researched 2026-10-10. Tags: **[opened]** = I fetched and read the page; **[snippet-only]** = only a search snippet, page not opened; **[uncertain]** = not confirmed by a primary source.

Reference feature set: the "Collabify" TikTok promo (see `research/tiktok-collabify-observations.md`). That is an animated promo with no found product, so it is a feature reference only and says nothing about architecture. Features it shows: two AE windows on the same `Brand_Launch_v3.aep`, an Invite collaborator button, Not connected -> Connected status, the other editor's labeled cursor, shared layers and changes, and a "Rendering" badge with avatars.

---

## Part A. What After Effects actually exposes

### A1. The .aep format and why it is hard to merge
- `.aep` is a proprietary binary. National Archives PRONOM identifies it by an RIFX header (big-endian RIFF-style chunks) [snippet-only]: https://pronom.nationalarchives.gov.uk/fmt/796.xml
- Adobe does not publish the structure. There is an open, community, reverse-engineered parser (`aep_parser`, Kaitai Struct, MIT, v0.0.1), so it is read-oriented and early [snippet-only]: https://pypi.org/project/aep-parser/0.0.1/
- `.aepx` is the XML flavor of the same project. Source: fileformat.com summary [snippet-only]: https://docs.fileformat.com/video/aep
- Consequences:
  - No documented schema, so you cannot diff or three-way merge `.aep` files (inference from the above, not a quoted claim).
  - The file holds IDs, indices, and internal references to footage, comps, and effect instances, and nothing ties it to a stable cross-machine identity.
  - Treat the project file as an opaque save artifact. Sync **operations** at the scripting or SDK level, not file bytes.
  - Footage paths are absolute and machine-specific. Both machines need the same assets (shared folder or an asset sync step).

### A2. ExtendScript / JSX scripting API
- ExtendScript is ES3 plus E4X, shared with Photoshop, Illustrator, and InDesign. Scripts cannot write files or use the network unless the user enables "Allow Scripts To Write Files And Access Network" [opened]: https://ae-scripting.docsforadobe.dev/introduction/overview/
- The `Application` object [opened: https://ae-scripting.docsforadobe.dev/general/application/]:
  - `beginUndoGroup` / `endUndoGroup`: a script's actions undo as one step. Groups nest and inner names are ignored.
  - `scheduleTask(string, delay, repeat)` / `cancelTask`: a timer, so it can be used for polling.
  - `executeCommand(id)` / `findMenuCommandId`: runs menu commands (the name lookup is not reliable across languages).
  - `project` is read-only.
  - `onError` is the **only** callback member. There are no change events.
  - `watchFolder` supports render farm style rendering.
- Property addressing [opened: https://ae-scripting.docsforadobe.dev/property/propertybase/]:
  - `matchName` is a stable, non-localized identifier, which makes it good for serializing property paths.
  - `propertyIndex` and `selected` (read/write) exist.
  - `CompItem.selectedProperties` and `Layer.selectedProperties` exist. The docs warn that sampling them repeatedly across many properties can slow AE down.
- Read/write surface (from general AE scripting knowledge plus the docs above; the keyframe API page was not opened [uncertain on edge cases]):
  - Comps, layers (name, index, in/out, parent, enabled, solo), the transform and effects property tree, keyframes (`setValueAtTime`, key interpolation), expressions, markers, and project items.
  - Layer selection reads through `comp.selectedLayers`.
  - The playhead is `comp.time`.
- **No change events.** A community search found no selection-changed or project-changed listener in ExtendScript. The workaround people use is polling, which Adobe experts criticize for performance [snippet-only]:
  - https://community.adobe.com/questions-529/making-a-script-that-dynamically-checks-if-property-value-have-changed-53525
  - https://community.adobe.com/questions-529/how-to-detect-if-project-has-unsaved-changes-27155
- Engine limits: ExtendScript is single-threaded and blocks the AE UI while a script runs. A heavy poll loop therefore janks the editor.

### A3. CEP vs UXP panels (status as of Oct 2026)
- Adobe developer blog, September 2026 (the URL path says 2026/09; the page text had no explicit date) [opened]: https://blog.developer.adobe.com/en/publish/2026/09/investing-in-the-future-of-creative-cloud-extensibility-uxp-comes-to-our-flagship-applications
  - After Effects **public beta UXP plugins by November 2026**.
  - CEP stops accepting new submissions and is disabled by default in December 2028. It is removed from the app starting December 2029. There is a minimum of two years from UXP beta to CEP removal.
  - Existing Marketplace plugins keep working until then.
  - **ExtendScripts are not affected by this transition.**
  - The page does not say what scripting access UXP in AE has.
- Older third-party notes (an April 2026 GitHub note said AE UXP panels were not yet available and to use CEP plus ExtendScript) are now superseded [snippet-only, page returned 503]: https://github.com/pushREC/after-effects-sdk-kb/blob/main/scripting/UXP-STATUS-NOTE.md
- **For a hackathon today:** CEP + ExtendScript is the proven path, and every AE MCP project below uses it. The UXP beta is too new, and its AE API surface is unknown to me [uncertain].
- CEP gives a Chromium panel with Node.js (can be enabled via manifest flags) and talks to AE through `CSInterface.evalScript`. This is what lets a panel open a WebSocket to a relay.

### A4. AEGP / C++ SDK
- AEGP is the plugin type that can register hooks. Found in SDK guide and forum threads [snippet-only]:
  - https://ae-plugin-sdk-guide.readthedocs.io/aegps/aegp-suites.html
  - https://ae-plugin-sdk-guide.readthedocs.io/aegps/implementation.html
  - **Idle hook**: runs on the main thread, and it is the safe place to call commands that would crash elsewhere.
  - **Command hook**: one hook for all commands, which can intercept menu commands.
  - The Utility suite exposes the undo stack.
  - `AEGP_ProjectIsDirty` can be polled from the idle hook. A forum answer proposes an AEGP that sets a flag a script then reads [snippet-only]: https://community.adobe.com/questions-529/how-to-detect-if-project-has-unsaved-changes-27155
- Gotcha: a forum answer says tracking cut/delete via command hooks is unreliable because not every user path fires the menu command, and redo does not fire delete. The suggested approach is scan-on-idle, which lags one cycle [snippet-only]: https://community.adobe.com/questions-529/sdk-detecting-when-a-effect-is-removed-52192
- Implication: real change detection in C++ is still a diff of project state on idle, not a clean event stream. C++ is not feasible in a one-day hackathon (build per OS, signing, SDK setup).

### A5. aerender CLI
- Headless render from the command line (`-project`, `-comp`, `-output`, frame range, templates). Official page returned 403 so details are from general knowledge [uncertain]: https://helpx.adobe.com/after-effects/using/automated-rendering-network-rendering.html
- Use it for a "Rendering" badge: the host spawns `aerender` and reports progress or completion. aerender on a saved copy of the project does not require the interactive UI.

### A6. Frame.io, Team Projects, Productions, Creative Cloud sharing
- **Frame.io V4 panel in AE** (review workspace) [snippet-only]:
  - https://helpx.adobe.com/after-effects/desktop/collaboration-with-others/frame-io/collaborate-using-frame-io.html (403 on fetch)
  - https://help.frame.io/en/articles/15291379-adobe-after-effects-frame-io-v4-panel-overview
  - Review comments, annotations, and replies; sync to timeline markers; comments from Share Link reviewers arrive in real time; clicking one jumps the playhead.
  - Legacy "Review with Frame.io" panel stopped working June 1, 2026. The AE V4 panel was labeled Beta in that article [snippet-only].
  - This is feedback on a **rendered** cut, not co-editing of project state.
- **Team Projects**: cloud-hosted shared project for Premiere and AE with auto-save and version history; File > Open Team Project... Adobe's own 2020 coverage and AppleInsider say it is **not** simultaneous editing of one project: each user works on a copy, with locking and collaborate/merge-style sharing. I did not confirm whether this changed since [snippet-only]:
  - https://appleinsider.com/articles/20/04/14/adobe-improves-remote-collaboration-with-productions-and-team-projects
  - https://blog.adobe.com/en/publish/2020/04/14/adobe-offers-team-projects-to-premiere-pro-and-after-effects-users-with-a-creative-cloud-individual-license
  - A March 2025 Adobe community thread shows it still in use [snippet-only]: https://community.adobe.com/questions-606/teams-projects-lost-when-subscription-ends
  - I found no retirement notice; status in 2026 is [uncertain].
- **Productions**: a Premiere Pro feature (shared local storage, split into sub-projects). It is not an AE feature [snippet-only: diyphotography/appleinsider above]. Adobe's FAQ said it cannot be combined with Team Projects.
- **Creative Cloud sharing / synced files**: file sync, not live editing. Adobe is discontinuing Creative Cloud Synced files for business plans [snippet-only]: https://helpx.adobe.com/enterprise/kb/eol-cc-synced-files-for-business-plans.html
- **Third-party "live co-editing" for AE**: none found. Evercast streams a pro editing tool to a team (the streaming model) [snippet-only]: https://www.evercast.us/blog/how-to-collaborate-adobe-after-effects. A web search for a plugin that lets two editors change the same AE project live found no match. Collabify is also not found.

### A7. AE MCP servers and AI-agent integrations (all snippet-only, from listings)
- `p10q/ae-mcp`: MCP -> file-system bridge -> CEP panel -> ExtendScript. The author found file-based comms reliable and the CEP Node context limiting. https://mcpservers.org/servers/p10q/ae-mcp
- `Brandkick/after-effects-mcp`: stdio MCP -> WebSocket -> CEP panel -> ExtendScript. Lists AE 2021+ (18.x-26.x). [snippet-only, from search summary]
- `a-y-ibrahim/after-effects-mcp`: 47 tools (ExtendScript execution, background rendering, project/layer inspection), MIT, tiny uptake. https://enterprisedna.co/directories/mcp/a-y-ibrahim-after-effects-mcp
- `shibin0/mcp-ae`: AppleScript on macOS, VBScript COM on Windows, falls back to aerender. https://glama.ai/mcp/servers/shibin0/mcp-ae
- Takeaway: a **WebSocket from a CEP panel to an external process** is an established pattern (Brandkick). It is the same transport a collab relay needs. These repos can be mined for working CEP panel + JSX bridge code, but verify licenses and maturity before reuse.

### A8. What AE state could be mirrored between two machines
| State | Readable via JSX | Writable via JSX | Mirror difficulty |
|---|---|---|---|
| Layer list (names, order, in/out, enabled) | yes | yes | easy |
| Transform and effect property values | yes | yes (`setValue`) | medium (need stable IDs) |
| Keyframes | yes | yes | medium |
| Expressions | yes | yes | medium |
| Selection (layers, properties) | yes, polled | yes | easy to read, janky |
| Playhead (`comp.time`) | yes | yes | easy |
| Markers | yes | yes | easy |
| Comp settings | yes | yes | easy |
| New footage / imports | yes | yes | needs shared assets |
| Effect instances / third-party params | partly | partly | hard |
| Undo/redo history | **no read access**; only `beginUndoGroup` | cannot undo remotely except `executeCommand` of Undo | **ruled out as a shared stack** |
| Mouse cursor position inside the AE canvas | not exposed | n/a | see section C |

Stable cross-machine IDs are not exposed. Layers have an `index` and a `name`, which both change. A real sync layer needs its own IDs (for example stored in layer comments, or in a `Layer.comment` field as a tag) [inference, not tested].

---

## Part B. Precedents for real-time collaboration in creative tools

### B1. Figma multiplayer
- Architecture [opened]: https://www.figma.com/blog/how-figmas-multiplayer-technology-works/
  - WebSocket clients; one server process per document that is the **ultimate authority**.
  - Not OT ("overkill"); a simplified CRDT-inspired design that uses the central server.
  - **Property-level last-writer-wins**: edits to different properties or objects never conflict.
  - Local changes apply immediately; incoming conflicting server values are discarded while a local change is unacked, which avoids flicker.
  - Tree structure: child stores a parent link; fractional indexing for ordering; server rejects cycles.
  - Client IDs embedded in object IDs allow offline creation without collisions.
  - Undo is per-client.
  - The post doesn't cover cursors or presence. Presence being a separate ephemeral channel is a common design but Figma specifics were not confirmed [uncertain].
- Earlier post: https://www.figma.com/blog/multiplayer-editing-in-figma/ [snippet-only]
- **Lesson for AE:** AE's property tree (layer -> property group -> property) maps well onto "object ID + property = value" last-writer-wins. Per-user undo avoids the unsolved shared-undo problem.

### B2. Frame.io
- Sync model: media is uploaded; comments and annotations attach to timecode; the panel syncs comments to markers. See A6.
- **Lesson:** review is asynchronous and tied to rendered media. It is not a source of live state sync. It is a good fit for the "render and comment" part.

### B3. DaVinci Resolve collaboration
- Source [opened]: https://www.blackmagicdesign.com/products/davinciresolve/collaboration
  - Project Server (PostgreSQL-backed, per the QNAP guide [snippet-only]: https://www.qnap.com/en/how-to/tutorial/con_show.php?cid=362) holds the shared database.
  - Users save small incremental changes to the database constantly.
  - **Bins and timelines lock automatically** to one editor and are read-only for others. Clips being graded lock too.
  - Incoming changes are reviewed and accepted, with timeline compare and merge into a master. Blackmagic Cloud IDs are used for invites.
- **Lesson:** a media tool with a heavy engine chose **locking + accept/merge** over fine-grained live merge. For AE: lock at comp or layer granularity is a pragmatic first model.

### B4. Blender collaboration add-ons
- **Multi-User** (slumber): free, client/server, replicates Blender data-blocks, presence overlay of other users in the 3D view, per-datablock rights; docs warn scenes can occasionally be corrupted. Extensions page lists v0.7.4 (2026-03-18) [opened: https://multi-user.readthedocs.io/en/latest/about/features.html; version from snippet at https://extensions.blender.org/add-ons/multi-user/].
- **Mixer** (Ubisoft): same idea, repo now archived [snippet-only]: https://mixer-github.readthedocs.io
- **Lesson:** this is the closest direct precedent to "replicate state between two real instances of a heavy desktop app." It works but corruption risk and maintenance burden are real. Per-object rights help avoid conflict.

### B5. Premiere Productions / Team Projects
- See A6. **Lesson:** Adobe's own answer was shared storage, locks, and copies, not live merge.

### B6. Unreal Engine Multi-User Editing
- Multiple editors join a shared session and edit one world in real time; built for virtual production; marked **Beta** [opened: https://dev.epicgames.com/documentation/en-us/unreal-engine/multi-user-editing-in-unreal-engine].
- It uses the Concert framework, with a session server and replication of selected properties (default 30 fps) over one stream per client [snippet-only]: https://dev.epicgames.com/documentation/unreal-engine/multi-user-replication-in-unreal-engine
- I did not find how transactions are ordered or how undo maps to them [uncertain].
- **Lesson:** engine-level property replication from a session server is the "serious" version of the state-sync approach. Each editor runs a full local copy; only edits move over the wire.
- Unity multi-user editing: not researched [uncertain].

### B7. Miro
- Not researched in depth; no primary source opened. Assume a server-authoritative whiteboard model, similar to Figma [uncertain].

### B8. tldraw sync / Liveblocks / PartyKit
- tldraw sync [opened: https://tldraw.dev/docs/sync]: one `TLSocketRoom` per document holds the authoritative copy and relays changes over WebSockets; Cloudflare Durable Objects (SQLite) for rooms; in-memory default loses data on restart. Presence and conflict resolution were not on the page.
- Liveblocks (managed rooms, presence, storage with LiveObject/LiveList, Yjs-compatible) and PartyKit (low-level edge WebSocket servers; one source says Cloudflare acquired it in 2024) [snippet-only, secondary blogs; pricing claims conflicted]:
  - https://www.pkgpulse.com/guides/liveblocks-vs-partykit-vs-hocuspocus-realtime-2026
  - https://apiscout.dev/guides/liveblocks-vs-partykit-realtime-collab-api-2026
  - Yjs is the CRDT library behind several of these (Hocuspocus is a self-hostable Yjs server).
- **Lesson:** a presence/cursor and room layer is available off the shelf. A Liveblocks room (or a 30-line `ws` relay) gives you invite codes, presence, and a broadcast channel in an hour. It is a message bus for AE operations, not an AE-aware merge engine.

### B9. Parsec-style remote editing
- Guest streams the **host's actual desktop** and drives the host's AE. Reported latency about 90.6 ms total at 1080p60, of which about 40 ms was the host display, from a 2021 Digital Foundry comparison cited by a blog [snippet-only]: https://jonnyelwyn.co.uk/film-and-video-editing/using-parsec-remote-desktop-for-video-editing/
- Parsec Team licensing allows several people to connect to one machine; list price quoted about $35/user/month in one review [snippet-only]: https://broadcastbeat.com/news/remote-editing-on-a-budget-with-parsec. I did not verify guest-control permissions.
- **Lesson:** this is exactly option (2). It is easy and robust but it is a screen stream, not collaboration: one shared cursor and keyboard, no per-user presence or independent views.

---

## Part C. Evaluating the architectures

### Option 1: State-sync between two real AE instances (Collabify-style)
- Each user runs their own AE with the same project and the same assets. A CEP panel in each AE captures local edits as operations and applies remote edits via ExtendScript (A8). A relay (or the host) forwards ops.
- Pros: matches the promo; each user has a local-latency UI; guest does not need the host's GPU for editing; "host with fastest GPU" is still useful for final renders.
- Cons / risks:
  - **No change events** (A2). You must poll (`scheduleTask` + diff) at roughly 200-500 ms. Latency is poll interval plus network.
  - **Echo loops**: applying a remote op fires your own diff; you need op IDs or a "applying remote" suppress flag.
  - **No stable IDs** for layers (A8), so you need a tagging scheme.
  - **ExtendScript blocks the UI** while applying, and writes pollute each user's local undo stack (undo groups help, but there is no remote-undo).
  - Effects and third-party plugin params will diverge in edge cases. Footage must exist at the same path on both machines.
  - The project file is not merged (A1). Both sides must start from an identical `.aep` copy (host sends the file on join).

### Option 2: Host streams its GPU desktop to the guest
- Parsec/WebRTC style (B9). Guest sees and controls the host's AE.
- Pros: **zero state-sync logic**; works with any AE content, plugins, and expressions; the host's GPU does all the work.
- Cons: one real AE instance, so no independent cursors, selections, or views; you would only have the OS-level shared mouse; latency about 50-100 ms plus network; building your own capture and WebRTC pipeline is a big project, and using Parsec means you are not building the product.
- Collabify-style features (labeled cursor of the *other* person, independent layer panel) are **not** natural here.

### Option 3: Hybrid (recommended)
- Host runs the "real" AE project and is the authority. Guest runs a **thin web or panel client** that receives host state (layer list, selection, playhead, a change feed) and can send *commands* that the host's panel applies. Optionally add a low-fps preview image of the active comp for the guest.
- This is the Figma model with the host acting as the server (B1): the server is authoritative, clients are optimistic, last-writer-wins per property, per-user undo only (A8).
- It avoids both the project merge problem (only one real project) and the 2-instances desync problem.
- If the guest also runs AE, the guest panel can mirror the host's state read-only plus send edits, which gets closer to the promo.

### Collabify-style feature feasibility
| Feature | Feasible? | How |
|---|---|---|
| Invite collaborator / Connected status | **Yes (easy)** | Room code + WebSocket handshake; show status in the panel |
| Shared layer list / selection | **Yes** | Poll `comp.layers` and `selectedLayers`, broadcast diffs |
| Change feed ("X moved Hero Title") | **Yes** | Diff of polled state, rendered as a log |
| Other editor's labeled cursor *in the layer list / timeline* | **Partly** | Show which layer/property the other user has selected (a proxy for a cursor) |
| Other editor's mouse cursor in the AE canvas | **No** via ExtendScript (no mouse API) | Only possible with a screen overlay app or a stream (option 2) [inference] |
| Live property edits applied on the other side | **Yes, laggy** | Poll + `setValue`; hundreds of ms |
| Shared undo | **Ruled out** | No API (A2, A8) |
| Render status badge with avatars | **Yes** | Spawn `aerender` on host, report progress via the relay |
| Project file merge | **Ruled out** | Opaque binary (A1) |
| Live preview to guest | **Hard but possible** | Render a still every N sec (`comp.saveFrameToPng` exists in newer AE [uncertain]) or use a stream |

---

## Implications for our After Effects live-session idea

**Design consequences**
1. **Go hybrid, with the host as the server.** One authoritative project on the host machine; the guest mirrors state and sends commands. This matches the team's "host locally" lean and the Figma/Blender/Unreal pattern (server-authoritative, property-level last-writer-wins).
2. **Build it as a CEP panel + JSX bridge + small WebSocket relay.** CEP is proven for AE today (all MCP bridges use it); UXP for AE is only entering public beta (November 2026) and its AE API is not known to me. Do not bet the demo on UXP.
3. **Define the sync unit as (stable layer ID, property matchName path, value).** Use `matchName` for paths. Add your own layer ID (for example in `Layer.comment`) because AE gives no stable cross-machine IDs.
4. **Poll, don't subscribe.** There are no change events. Use `scheduleTask` at a few hundred ms and diff, with an echo-suppress flag. Limit polling to selection, layer list, playhead, and a watched set of properties to avoid slowing AE.
5. **Wrap each remote application in `beginUndoGroup`** so one remote change is one local undo step, and accept that undo is local only.
6. **Put the room/presence layer on a hosted bus** (Liveblocks, PartyKit, or a tiny `ws` relay) rather than building NAT traversal in a day. The host-must-be-reachable problem is covered by other files in this folder (not read).
7. **Assets are a prerequisite**: both machines need the same footage paths (a shared folder, or the host sends the packed project via Collect Files).
8. **Use `aerender` for the render badge**: the host runs it and the relay broadcasts progress.

**Enabled** (realistic for one day): invite code + connect flow; presence list with avatars; each user's selected layer shown as a labeled "cursor" in the layer list; change feed; shared playhead; one-way or limited two-way property edits (position, opacity, text, etc.) with last-writer-wins; render status badge; lock-a-layer-while-editing as a simple conflict rule (Resolve model).

**Ruled out / infeasible in a day**: shared undo/redo stack; merging `.aep` files; the other editor's literal mouse cursor in the canvas; syncing arbitrary third-party effect internals; guaranteed frame-accurate shared playback; C++ AEGP plugin work; production-grade security and NAT traversal.

**If the demo must look like the promo**: the safest hack is a **scripted mock for the cursor** (animate a labeled marker in the layer panel) plus real sync of layer selection, playhead, and a small set of properties, and the host-side `aerender` badge. Be honest in the pitch that the stream (Parsec) fallback exists for anything the sync layer can't cover.

**Open questions** to test early: (a) how fast can a JSX poll of ~50 layers run without UI jank; (b) can a CEP panel hold a WebSocket reliably on the team's AE version (Brandkick MCP suggests yes); (c) whether `Layer.comment` tagging survives duplicate/precompose.

---

## Sources
- Collabify observations (local): `research/tiktok-collabify-observations.md`
- Adobe developer blog, UXP/CEP (Sept 2026) [opened]: https://blog.developer.adobe.com/en/publish/2026/09/investing-in-the-future-of-creative-cloud-extensibility-uxp-comes-to-our-flagship-applications
- AE scripting guide: overview [opened] https://ae-scripting.docsforadobe.dev/introduction/overview/ ; Application [opened] https://ae-scripting.docsforadobe.dev/general/application/ ; PropertyBase [opened] https://ae-scripting.docsforadobe.dev/property/propertybase/
- AE SDK guide [snippet-only]: https://ae-plugin-sdk-guide.readthedocs.io/aegps/aegp-suites.html ; https://ae-plugin-sdk-guide.readthedocs.io/aegps/implementation.html
- Adobe community threads [snippet-only]: https://community.adobe.com/questions-529/how-to-detect-if-project-has-unsaved-changes-27155 ; https://community.adobe.com/questions-529/sdk-detecting-when-a-effect-is-removed-52192 ; https://community.adobe.com/questions-529/making-a-script-that-dynamically-checks-if-property-value-have-changed-53525 ; https://community.adobe.com/questions-606/teams-projects-lost-when-subscription-ends
- .aep format [snippet-only]: https://pronom.nationalarchives.gov.uk/fmt/796.xml ; https://pypi.org/project/aep-parser/0.0.1/ ; https://docs.fileformat.com/video/aep
- aerender/network rendering (403, not opened): https://helpx.adobe.com/after-effects/using/automated-rendering-network-rendering.html
- Frame.io / AE [snippet-only; Adobe page 403]: https://helpx.adobe.com/after-effects/desktop/collaboration-with-others/frame-io/collaborate-using-frame-io.html ; https://help.frame.io/en/articles/15291379-adobe-after-effects-frame-io-v4-panel-overview ; https://blog.adobe.com/en/publish/2025/12/19/get-your-creative-team-same-page-frameio-now-available-adobe
- Team Projects / Productions [snippet-only]: https://appleinsider.com/articles/20/04/14/adobe-improves-remote-collaboration-with-productions-and-team-projects ; https://blog.adobe.com/en/publish/2020/04/14/adobe-offers-team-projects-to-premiere-pro-and-after-effects-users-with-a-creative-cloud-individual-license ; https://helpx.adobe.com/enterprise/kb/eol-cc-synced-files-for-business-plans.html
- Evercast on AE collaboration [snippet-only]: https://www.evercast.us/blog/how-to-collaborate-adobe-after-effects
- AE MCP servers [snippet-only]: https://mcpservers.org/servers/p10q/ae-mcp ; https://enterprisedna.co/directories/mcp/a-y-ibrahim-after-effects-mcp ; https://glama.ai/mcp/servers/shibin0/mcp-ae
- Figma [opened]: https://www.figma.com/blog/how-figmas-multiplayer-technology-works/ ; [snippet-only] https://www.figma.com/blog/multiplayer-editing-in-figma/
- DaVinci Resolve [opened]: https://www.blackmagicdesign.com/products/davinciresolve/collaboration ; [snippet-only] https://www.qnap.com/en/how-to/tutorial/con_show.php?cid=362
- Blender Multi-User [opened]: https://multi-user.readthedocs.io/en/latest/about/features.html ; [snippet-only] https://extensions.blender.org/add-ons/multi-user/ ; https://mixer-github.readthedocs.io
- Unreal Multi-User [opened, high level]: https://dev.epicgames.com/documentation/en-us/unreal-engine/multi-user-editing-in-unreal-engine ; [snippet-only] https://dev.epicgames.com/documentation/unreal-engine/multi-user-replication-in-unreal-engine
- tldraw sync [opened]: https://tldraw.dev/docs/sync
- Liveblocks / PartyKit / Yjs comparisons [snippet-only, secondary]: https://www.pkgpulse.com/guides/liveblocks-vs-partykit-vs-hocuspocus-realtime-2026 ; https://apiscout.dev/guides/liveblocks-vs-partykit-realtime-collab-api-2026
- Parsec [snippet-only]: https://jonnyelwyn.co.uk/film-and-video-editing/using-parsec-remote-desktop-for-video-editing/ ; https://broadcastbeat.com/news/remote-editing-on-a-budget-with-parsec
- Not researched / unverified: Miro architecture, Unity multi-user, Premiere Productions official docs, Adobe's AE UXP API surface.

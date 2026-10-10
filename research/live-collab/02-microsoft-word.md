# Microsoft Word collaboration: how it works, and what it means for a live After Effects session

Research date: 2026-10-10. Scope: Word web vs desktop co-authoring, AutoSave, OneDrive/SharePoint as coordinator, the file sync protocol, locking vs merging, presence, Fluid Framework, version history, conflicts, and a comparison with Google Docs.

**Legend**
- **[documented]**: stated in a primary source I opened.
- **[inferred]**: my reasoning from documented pieces. Microsoft does not say it.
- **[uncertain]**: sources conflict or are weak.
- **[snippet-only]**: I saw it only in a search snippet and could not open the page.

---

## 1. TL;DR

1. Word's collaboration is **server-centric**. The document lives in OneDrive or SharePoint, and every client (desktop, web, mobile) syncs to that one copy. There is no peer-to-peer or "one editor hosts" mode. [documented: co-authoring requires online storage, see 3.1]
2. The classic Word protocol is **file-level sync with merging** (MS-FSSHTTP plus MS-FSSHTTPB). It is not a character-by-character op stream. Clients upload incremental changes. If two uploads collide, the loser gets a "coherency error", downloads the latest, merges locally, and retries. [documented]
3. Until 2026, Word avoided character-level conflicts with **paragraph-level locks**. In May 2026 Microsoft started rolling out **"lock-free coauthoring"**, so several people can edit the *same paragraph* when all clients are up to date. [documented via Message Center MC1304289, mirrored third-party, see 3.4]
4. **Fluid Framework** is a *separate* Microsoft technology: a client-merge, server-orders-only model (total-order broadcast). It powers Loop and Teams components. Whether Word's text editing runs on it is **not documented** by what I found. [documented for Fluid, inferred for Word]
5. Google Docs uses **operational transformation with a central server** (Jupiter lineage). Word historically used **lock plus file-merge**. Fluid uses **client-side merge over a dumb ordering server**. All three have a server that sequences or merges. None is host-peer.

---

## 2. System-design diagram

```
                       ┌───────────────────────────────────────────┐
                       │          Microsoft 365 cloud              │
                       │                                           │
  Word desktop ──────► │  Auth (Entra ID / MSA)                    │
  (Win/Mac)  FSSHTTP   │        │                                  │
       ▲   (SOAP+MTOM  │        ▼                                  │
       │    over HTTPS) │  SharePoint Online / OneDrive             │
       │               │   ├─ file store (blob + revision tree)    │
       │               │   ├─ co-authoring service: shared locks,  │
  Word for web ───────►│   │   who-is-editing status, merge        │
  (browser)            │   ├─ version history (per-save versions)  │
       │               │   └─ permissions / sharing links          │
       │               │        │                                  │
       │ presence /    │        ▼                                  │
       │ real-time     │  Real-time channel (name/protocol not     │
       └──────────────►│  documented in what I found) [uncertain]  │
        (WebSocket?)   └───────────────────────────────────────────┘

  Separate product line (Loop, Teams, 3rd-party apps):
  Fluid client (DDSes + merge logic) ──WebSocket/socket.io──► ordering service
        │                                                     (assigns sequence #,
        └─ loads state from summary + replays later ops ◄──── broadcasts ops,
                                                              stores ops + summaries)
```

The top box is the documented FSSHTTP path. The real-time channel is shown only because live cursors and instant text updates must travel somewhere. The transport is **[uncertain]**, since I found no primary document naming it. The Fluid path at the bottom is documented as its own stack.

### Component list

| Component | Role | Evidence |
|---|---|---|
| Word desktop client | Edits locally and uploads/downloads incremental changes. Merges on coherency failure. | [documented] MS-FSSHTTP overview |
| Word for the web | Browser editor for the same file. | [documented] support page: shared docs open in the browser, with "Open in Desktop" to switch |
| SharePoint Online / OneDrive | Stores the file, enforces permissions, tracks co-authors, keeps versions. | [documented] AutoSave and co-authoring support pages. Version history [snippet-only]. |
| MS-FSSHTTP | SOAP/HTTP request protocol: upload, download, shared/exclusive lock. | [documented] |
| MS-FSSHTTPB | Binary data model for incremental sync: cells, revision manifests, object groups, knowledge. | [documented] |
| Shared lock service | Tells each client who else is editing; guards regions. | [documented] MS-FSSHTTP overview |
| Presence | Shows other authors' cursors/avatars. | [documented] support page: "see their presence and the changes they're making" |
| Version history | Restore earlier versions. | [snippet-only] Microsoft "Collaborate with others" page |
| Fluid ordering service | Total-order broadcast for Fluid apps. | [documented] fluidframework.com |

---

## 3. How Word collaboration works

### 3.1 Storage as the prerequisite
- Co-authoring requires saving the document to OneDrive, OneDrive for Business, or SharePoint Online. [snippet-only: Microsoft Word team blog and CustomGuide via search]
- AutoSave is the mechanism that sends changes continuously when the file is online. [snippet-only: Microsoft Support and VentureBeat 2017]
- Real-time co-authoring needs a Microsoft 365 subscription. Users on older Word versions, or without a subscription, can still edit at the same time, but "won't have real-time collaboration" and must save to see others' changes. [documented: https://support.microsoft.com/topic/7dd3040c-3f30-4fdd-bab0-8586492a1f1d]
- Documents with macros (.docm) can be co-edited. Changing macro code requires check-out/check-in. [documented, same page]
- Reported limits include "marked as final" and IRM/encryption. These come from an AI-generated Microsoft Q&A answer, so treat them as [uncertain].

### 3.2 Word web vs desktop
- Both open the same file from the same service. A recipient opens a link in the browser, and can switch to the desktop app with "Open in Desktop". [documented]
- The same file format serves both, and the desktop and web clients interoperate through the server, not directly. [documented for the shared server model, inferred that no direct channel exists]
- How the *web* client talks to the server (Word Online internals, whether it uses WOPI, whether it uses FSSHTTP or a different channel) is **not documented in what I opened**. [uncertain]

### 3.3 The sync protocol (documented, primary source)
Source: [MS-FSSHTTP overview](https://learn.microsoft.com/en-us/openspecs/sharepoint_protocols/ms-fsshttp/6d078cbe-2651-43a0-b460-685ac3f14c45) (page updated 2025-02-18), and [MS-FSSHTTPB data model](https://learn.microsoft.com/en-us/openspecs/sharepoint_protocols/ms-fsshttpb/6c7e4447-6ccd-4764-8dbc-17a382fb631d) (rev 24.0, 2024-08-20).

- **Transport:** "a request/response stateless message exchange protocol based on SOAP that uses HTTP 1.1 for its transport and SOAP MTOM encoding." There is no persistent socket in this layer.
- **Files and partitions:** The server stores files addressable by URL. Each file has partitions holding binary contents, co-authoring information, or format-specific content. Each partition syncs independently.
- **Requests:** download, upload (changed data plus metadata), and lock operations bundled into upload/download requests.
- **Locks:** **exclusive** (one editor) or **shared** (multiple clients may edit a "coauthorable" file). With shared locks the server also tracks which clients are editing and reports co-authoring status to each client.
- **Incremental sync:** MS-FSSHTTPB lets the client avoid fetching the whole file each time. The server keeps a tree: File → Storage Index → Storage Manifest → Cells → Revision Manifests (a linked list of revisions) → Object Groups → Objects/Data Blobs. "All data elements are immutable." Cells are "major divisions of the file that have limited interdependency", and object groups hold objects "that tend to be modified together".
- **Conflict handling (verbatim logic):** "if two or more clients sent an upload request simultaneously, all requests except the first one fail with a coherency error." The client then downloads the latest changes, "automatically merges the latest changes with its local version", and if it cannot, "exposes the merge conflict to the user and lets the user do a manual merge". It then re-uploads. The upload succeeds if the file has not changed since that client's last download.
- **Codename "Cobalt":** the task brief mentions it. I could not tie the name to these specs in anything I opened. A search for it returned nothing. My memory says it is the internal name for the MS-FSSHTTPB implementation, but that is **[uncertain]**.

**Takeaway:** the server is a *versioned, immutable-chunk store with optimistic concurrency* (compare-and-swap on the file's latest revision), and merging happens in the client. The server never needs to understand document content beyond the schema GUID. [partly documented, partly inferred]

### 3.4 Paragraph locking vs character-level merging
- **Original model (2010 to roughly 2025):** typing locks the paragraph (or section) for other authors. Microsoft's 2011 announcement, as quoted by TheNextWeb: as soon as you begin typing, the corresponding section is locked and others are notified. PCWorld noted Microsoft deliberately avoided character-by-character display. [snippet-only, 2011 press]
- The active paragraph shows as locked to others (lock icon) until you move away. [snippet-only: CustomGuide, WiseChecker]
- **2026 change: lock-free coauthoring.** Message Center item MC1304289, published 2026-05-08, says multiple users can edit the same paragraph at the same time in supported Word sessions on desktop and web. Rollout was mid-May to early June 2026 in Worldwide, GCC, GCC High, and DoD. It is on by default, with no admin configuration and no change to storage or sharing. If a session isn't supported (older client or unsupported content), Word falls back to the old behavior, where users may be unable to edit the same paragraph concurrently. [documented via https://mc.merill.net/message/MC1304289, a third-party mirror of the Message Center post, which has since expired]
- Microsoft's own support article for it (https://support.microsoft.com/en-gb/office/about-lock-free-coauthoring-in-word-c349bae5-2d8f-4775-aa1f-f6bfc3375157) returned "article no longer available" when I opened it. Search snippets say it covers Word for Microsoft 365, 2024, and 2021, with a compatibility-mode icon in the status bar on fallback. [snippet-only]
- **How lock-free merging works is not documented.** Concurrent same-paragraph edits require an algorithm such as OT or a CRDT, or a character-range merge. I found no source saying which. [uncertain]

### 3.5 Presence
- Other authors' presence and changes appear live for Microsoft 365 subscribers. [documented]
- Cursor visibility, name flags, and selection color are standard behavior, but I have no primary-source description of the presence channel or its transport. [uncertain]

### 3.6 AutoSave and version history
- AutoSave pushes changes to the cloud copy continuously. [snippet-only]
- Version history: when a file is in OneDrive or SharePoint, users can open Version History, pick a version, compare changes, and Restore. [snippet-only: https://prod.support.services.microsoft.com/en-us/topic/b85eef71-e96b-4325-9501-228588728bc9]
- Whether versions are created per save, per interval, or per session is not in what I opened. [uncertain]
- The immutable-revision design in MS-FSSHTTPB (revision manifests as a linked list) is a natural foundation for history. That Word's version history uses it directly is **[inferred]**.

---

## 4. Fluid Framework

Source: [fluidframework.com architecture](https://fluidframework.com/docs/concepts/architecture) and [DDS overview](https://fluidframework.com/docs/data-structures/overview), plus the Azure docs below.

- **What it is:** a client-side library plus a thin service for building real-time collaborative apps. Announced at Build 2019 and open-sourced in 2020 (press coverage: [PCWorld](https://www.pcworld.com/article/397392/microsoft-launches-fluid-framework-to-transform-the-traditional-office-document.html) and [InfoQ](https://www.infoq.com/news/2020/12/fluid-framework-open-source-msft), snippet-only).
- **Three parts:** loader (connects and loads), container (holds state and app logic; made of shared objects and DDSes), and service. [documented]
- **The service is a total-order broadcast:** a client sends an op, the service assigns it a sequence number, broadcasts it, and acks the sender. The service "doesn't parse any of these ops". It stores old ops and **summaries** (snapshots) so a late joiner doesn't replay everything. [documented]
- **Merging happens on clients.** Design principles: keep the server simple, move logic to the client, mimic the web. All clients must load the same merge code to converge. [documented]
- **Distributed data structures:**
  - SharedTree: hierarchical, recommended for new development.
  - SharedMap: key/value, "optimistic and uses a last-writer-wins merge policy".
  - SharedString: collaborative unstructured text, optimistic.
  - TaskManager (experimental): consensus-style queue for exclusive tasks. Consensus DDSes are not optimistic, because clients wait for acknowledgement.
  - [documented: DDS overview]
- **Transport:** HTTP plus WebSockets via socket.io, with long-polling fallback. [documented: Azure Fluid Relay FAQ]
- **Offline:** the client accumulates ops locally and resends on reconnect. Azure Fluid Relay doesn't support offline beyond about 1 minute. [documented: FAQ]
- **Service options:** [Available Fluid services](https://fluidframework.com/docs/deployment/service-options) lists Azure Fluid Relay (hosted), Tinylicious (dev-only), and self-hosted Routerlicious (the original open-source service, "not formally supported" for production).
- **Azure Fluid Relay status [uncertain, sources conflict]:** Microsoft Learn pages (last updated 2026-08-02) still describe it as generally available, with no retirement banner. One third-party page (innfactory.de) claims it "was retired on September 30, 2025" and recommends Web PubSub or SignalR. I found no Microsoft source confirming the retirement and it is absent from Microsoft's "Ending Support in 2025" list. Verify before depending on it. Hosting your own Routerlicious or Tinylicious avoids the question.
- **Does Word use Fluid?** Fluid was "partially based on" Microsoft 365 apps and demoed with live tables shared between Word and Teams (2019 press, snippet-only). I found **no primary source saying Word's core text co-authoring runs on Fluid**. Treat Word's engine as separate from the Fluid Framework. [inferred, uncertain]

---

## 5. Comparison with Google Docs

| | Word (classic) | Word (lock-free, 2026) | Fluid Framework | Google Docs |
|---|---|---|---|---|
| Unit of sync | File chunks (cells/object groups) | Not documented [uncertain] | Ops on DDSes | Operations on the doc model |
| Conflict strategy | Lock paragraph, plus optimistic upload with client merge and manual fallback | Concurrent same-paragraph edits, mechanism undocumented | Client-side DDS merge (LWW for maps, sequence merge for strings) | Operational transformation, server resolves order |
| Server smarts | Stores revisions, manages locks, does not merge content [inferred] | Unknown | Almost none: sequences and stores | Central server transforms and rebroadcasts |
| Latency feel | Section-level, seconds | Closer to live | Instant local apply, then ordered | Instant local apply, then transformed |
| Transport | SOAP/HTTP request-response | Not documented | WebSocket (socket.io) | Not in sources I could open |

**Google Docs details:** Google's 2010 posts "What's different about the new Google Docs: Conflict resolution" (2010-09-22) and "Making collaboration fast" (2010-09-23) are on the Drive blog. Search snippets say they describe edits being sent to a server, relayed to other editors, and adjusted against each recipient's local state via operational transformation. The page bodies would not load in my fetch, so the content is [snippet-only]. Primary-source lineage: the [Jupiter paper (Nichols, Curtis, Dixon, Lamping, UIST 1995)](https://uist.acm.org/uist1995/abstracts/Nichols.html) adapts Ellis and Gibbs' distributed OT to a *centralized* server, which "substantially simplif[ies]" it. That is the OT-with-central-server ancestor of Docs and Wave. Claims that Docs today uses X microservices or Y latency numbers come from interview-prep blogs and are unreliable. I ignored them.

**Key contrast:** OT and Fluid both let the client apply edits instantly and reconcile after server ordering, so they feel live. Classic Word's file-sync model is coarser, which is why it needed locks. All three need a *central sequencer or store*.

---

## 6. Documented vs inferred summary

**Documented (opened primary source):** FSSHTTP/FSSHTTPB behavior, lock types, coherency-error merge flow, data model; real-time co-authoring needs a subscription; Fluid architecture, DDS list and merge policies; Fluid Relay FAQ; lock-free coauthoring rollout (via mirror of Message Center text).

**Inferred:** server doesn't merge content; version history rides on revision manifests; no direct desktop to web channel; Word's core isn't Fluid.

**Uncertain / not found:** the real-time presence transport; Word web's internal protocol; the lock-free merge algorithm; Azure Fluid Relay's retirement; the meaning of "Cobalt".

---

## 7. Implications for our After Effects live-session idea

1. **Word's architecture is server-hosted, so it doesn't answer our host-vs-server question directly.** Everything runs through OneDrive/SharePoint, and no user's machine is authoritative. Our "fastest GPU hosts" idea is a different shape: closer to screen-sharing plus remote control than to document sync. Word is evidence for the server-based option, not the host-based one.

2. **AE project files aren't text, but the *concept* transfers: sync a structured project tree, not pixels.** An .aep is a hierarchical project (comps, layers, properties, keyframes). Word's lesson is to split the file into independently syncable chunks (cells/object groups) with immutable revisions, then upload deltas. For a hackathon, that means modeling a *subset* (layer transforms and keyframes) as a JSON tree rather than syncing the binary project. [inferred design]

3. **Locking beats merging at hackathon speed.** Word shipped with paragraph locks for about 15 years and only moved to lock-free in 2026. An AE equivalent is to **lock a layer or composition per person** with a visible "Alex is editing Layer 3" badge, which avoids writing merge logic. This is the cheapest viable collaboration model.

4. **Use optimistic concurrency with a version number, not a clever merge.** MS-FSSHTTP's rule is simple: upload succeeds only if the file hasn't changed since your last download, otherwise download, merge, retry. For the demo, a monotonically increasing revision on the host/server, plus reject-and-rebase for conflicting property edits, is a few dozen lines.

5. **If we want live-feeling edits, copy the Fluid shape, not Word's.** Fluid's server is only a sequencer and relay: assign a sequence number, broadcast, ack. SharedMap-style last-writer-wins on per-property keys (e.g., `layer3.position`) is a good fit for scrubbing and dragging, and is trivial to build. A host machine can play that sequencer role: the host runs the tiny ordering service locally, which keeps the "host" idea alive while borrowing Fluid's design. Fluid's own self-hostable pieces (Tinylicious, Routerlicious) are available, but Routerlicious is not formally supported for production, and Azure Fluid Relay's status is unclear (see section 4).

6. **Presence is cheap and high-value.** Cursors, selected layers, and the playhead position of each collaborator are small messages over a WebSocket. This makes the demo feel real without touching the sync model.

7. **Don't sync rendered frames through the collaboration channel.** Word never ships pixels, since the document *is* the data. For AE, the "host renders, guests watch" mode is a separate video stream (WebRTC), distinct from the project-state channel. Treat these as two channels: low-bandwidth project ops, and an optional high-bandwidth preview stream from the host.

8. **Version history is a feature we get nearly free** if we keep immutable revisions as Word's data model does: append-only op log plus periodic snapshots (Fluid's "summaries"). That gives undo, restore, and "late joiner catches up" with the same mechanism.

9. **Ruled out or deferred:** character-level or sub-property concurrent merging (OT/CRDT for keyframe curves is real work and Word needed 15 years); offline editing for long periods (Fluid Relay itself caps this at about a minute); relying on a hosted Microsoft service (uncertain availability).

10. **Desktop vs web interop lesson:** Word's clients stay in sync because the *file format is the contract*. For AE, if the guest uses a lightweight web client while the host runs real After Effects, define a small shared schema first. Then both sides speak it, and a single adapter (ExtendScript/CEP/UXP plugin on the host) translates to real AE calls. That adapter is the real engineering risk, and this research does not cover it.

**Recommended pick from this angle:** host runs a small ordering/relay service (Fluid-style) plus the AE adapter; guests connect over WebSocket; per-layer locks plus per-property LWW; presence broadcast; optional WebRTC preview stream. Move to a hosted server only if the demo needs it to survive the host leaving.

---

## Sources

Opened and used (primary):
- MS-FSSHTTP overview: https://learn.microsoft.com/en-us/openspecs/sharepoint_protocols/ms-fsshttp/6d078cbe-2651-43a0-b460-685ac3f14c45 (updated 2025-02-18)
- MS-FSSHTTPB landing: https://learn.microsoft.com/en-us/openspecs/sharepoint_protocols/ms-fsshttpb/f59fc37d-2232-4b14-baac-25f98e9e7b5a (rev 24.0, 2024-08-20)
- MS-FSSHTTPB abstract data model: https://learn.microsoft.com/en-us/openspecs/sharepoint_protocols/ms-fsshttpb/6c7e4447-6ccd-4764-8dbc-17a382fb631d
- Word real-time co-authoring (Microsoft Support): https://support.microsoft.com/topic/7dd3040c-3f30-4fdd-bab0-8586492a1f1d
- Fluid architecture: https://fluidframework.com/docs/concepts/architecture
- Fluid DDS overview: https://fluidframework.com/docs/data-structures/overview
- Fluid service options: https://fluidframework.com/docs/deployment/service-options
- Azure Fluid Relay landing: https://learn.microsoft.com/azure/azure-fluid-relay (updated 2026-08-02)
- Azure Fluid Relay architecture: https://learn.microsoft.com/en-us/azure/azure-fluid-relay/concepts/architecture
- Azure Fluid Relay FAQ: https://learn.microsoft.com/en-us/azure/azure-fluid-relay/resources/faq
- Message Center MC1304289 (third-party mirror, published 2026-05-08, expired 2026-07-04): https://mc.merill.net/message/MC1304289
- Jupiter paper abstract (UIST 1995): https://uist.acm.org/uist1995/abstracts/Nichols.html

Snippet-only (could not open body or only saw search summaries):
- Microsoft lock-free coauthoring support article (page retired when opened): https://support.microsoft.com/en-gb/office/about-lock-free-coauthoring-in-word-c349bae5-2d8f-4775-aa1f-f6bfc3375157
- Microsoft "Collaborate with others" (version history): https://prod.support.services.microsoft.com/en-us/topic/b85eef71-e96b-4325-9501-228588728bc9
- Google Drive Blog, Conflict resolution (2010-09-22), body not rendered: https://drive.googleblog.com/2010/09/whats-different-about-new-google-docs_22.html
- Google Drive Blog, Making collaboration fast (2010-09-23), body not rendered: https://drive.googleblog.com/2010/09/whats-different-about-new-google-docs.html
- TheNextWeb, 2011-07-07, co-authoring in Word Web App: https://thenextweb.com/news/microsoft-brings-co-authoring-to-its-word-web-app
- PCWorld 2011, Word Web App co-authoring: https://www.pcworld.com/article/487025/microsoft_adds_coauthoring_feature_to_word_web_app.html
- VentureBeat 2017-03-28, AutoSave: https://venturebeat.com/2017/03/28/word-excel-and-powerpoint-get-autosave-for-onedrive-and-sharepoint-files
- Fluid launch coverage: https://www.pcworld.com/article/397392/microsoft-launches-fluid-framework-to-transform-the-traditional-office-document.html and https://www.infoq.com/news/2020/12/fluid-framework-open-source-msft
- Lock-free coauthoring write-up (403 on fetch): https://m365admin.handsontek.net/lock-free-coauthoring-microsoft-word/
- Azure Fluid Relay "retired" claim (third-party, unverified): https://innfactory.de/en/cloud/azure/products/fluid-relay/

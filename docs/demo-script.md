# Demo Recording Script (v2)

Scene-by-scene test cases for recording a demo video, covering the full
arc: **Memory → Skills → Actions, all governed**. Each scene lists the
exact action, the words/questions to use, and the expected on-screen
result. `docs/demo-checklist.md` is the operational setup; this file is
the camera-ready script.

## Pre-flight (off camera)

1. Live appliance up (`just prod-ps`), Slack app connected, bot invited to
   one public test channel (e.g. `#demo-general`).
2. Keys on the box for the full arc: `OPENAI_API_KEY` (model answers,
   collection proposals, drafts, chunk situating) and `PERPLEXITY_API_KEY`
   (deep research). Without them the memory scenes still work
   deterministically; research/write fail honestly.
3. Reset memory so the story is deterministic:

   ```sh
   just prod-demo-reset   # live appliance
   just demo-reset        # local stack
   ```

4. Have the 37signals-style handbook folder zipped on your desktop
   (`company-handbook.zip` — the folder name becomes the proposed
   collection name), plus `priv/fixtures/skills/cold-email/SKILL.md`.
5. Windows side by side: Slack left, admin UI right
   (`just prod-open` opens the control plane).

## Scene 1 — The empty appliance (30s)

- Open `/admin/control-plane`.
- Say: "This is a governed AI operator. Right now it knows nothing, and
  everything it ever does will land on this timeline."
- Expected: Memory card shows 0 chunks and the embeddings mode label;
  Approval gates card says `armed`; the timeline shows the teaching empty
  state.

## Scene 2 — A corpus becomes a collection (75s)

- Sources → **New collection** → upload `company-handbook.zip`.
- Expected: files stage as they upload ("N documents staged"); click
  **Review collection** → the classifier proposes *Company handbook /
  handbook* with a description.
- Edit the description slightly (show the human is in charge), click
  **Confirm & ingest**.
- Expected: collection appears with document counts; the timeline records
  `Collection confirmed` (governance) plus per-file ingest events; the
  Memory map (`/admin/memory`) now shows the collection with kind badge,
  description, and expandable chunks.
- Say: "The system proposed what this corpus is; a human confirmed it.
  From now on every answer can say *per the employee handbook*."

## Scene 3 — A cited answer in Slack (60s)

- In the test channel:

  > @andnative-ai When do reimbursements need manager approval?

- Expected in Slack: an answer with the handbook fact and a citation link.
- Control plane: `Slack mention → Memory searched → Answer generated →
  Citation attached → Response posted` stream in live under one request
  id; click one and walk the trace in the inspector.

## Scene 4 — Governed forgetting (60s, the trust moment)

- Delete the handbook **collection** in Sources (one click removes the
  whole corpus).
- Expected: `Collection deleted` + per-source `Source deleted` events; the
  memory map shows every handbook file struck through.
- Re-ask the exact same question in Slack → "could not find a relevant
  source."
- Say: "Deleted means deleted — at corpus granularity, with evidence for
  both moments." (Re-upload the collection off camera if later scenes need
  it.)

## Scene 5 — The agent does work: deep research (2-3 min real time)

- In the test channel:

  > @andnative-ai research: what are SME buyers saying about governed AI assistants in 2026?

- Expected: threaded ack — "this needs a human approval first."
- Control plane: the **Awaiting your approval** panel shows the action;
  click **Approve & run**.
- Say: "Anything that spends money or leaves the building pauses for a
  human. The click itself is evidence."
- Expected: `Action approved → started` on the timeline; a few minutes
  later a summary message plus a markdown **research dossier with a
  Sources section** lands in the thread; `Action completed` records
  provider, citation count, and actual cost.
- (While waiting, film Scene 6.)

## Scene 6 — Skills: teach the agent HOW (60s)

- Open `/admin/skills`, upload `cold-email/SKILL.md`, install.
- Expected: skill listed with version hash and MIT license; toggle it on
  for the demo agent → `Skill installed` / `Skill enabled` governance
  events.
- Optional flex: try installing a bundle containing a `scripts/` folder →
  rejected with a clear reason, and even the rejection is on the timeline.
- Say: "Skills are the open standard the whole ecosystem ships — we run
  the prompt-only kind, version-pinned, per-agent, and fully audited."

## Scene 7 — Skills × memory: a grounded draft (90s)

- In the test channel:

  > @andnative-ai write: cold-email for ops leads at manufacturing SMEs

- Approve it on the control plane.
- Expected: a draft document in the thread — skill + version stamped in
  the header, a Sources section citing the company memory it used; the
  trace shows `Skill used (cold-email vXXXX)` alongside the action events.
- Say: "The skill said HOW to write it; our governed memory said WHAT is
  true. And the audit trail shows exactly which skill and which sources
  shaped this draft."

## Scene 8 — Close on the timeline (30s)

- Control plane, filter chips: click **Governance** — collection
  confirmations, deletions, skill installs, approvals. Click **Actions** —
  the research and write lifecycles.
- Say: "Memory, skills, actions — one appliance, one audit trail. That's
  what governed means."

## Bonus scenes (if time)

- **Per-channel app-post policy**: Sources → toggle "App & bot posts" →
  `Policy changed` event; a Linear notification becomes citable memory.
- **Weekly digest**: `@andnative-ai digest: this week` → the weekly
  governed-memory digest posts on demand (it also runs Monday 08:00 UTC).
- **Echo (rehearsal)**: `@andnative-ai echo: hello` — the fastest way to
  show the mention → job → document → trace loop with zero spend.

## Reset between takes

```sh
just prod-demo-reset                  # live appliance
just prod-demo-backfill C0123456789   # re-ingest the demo channel
```

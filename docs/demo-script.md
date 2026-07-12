# Demo Recording Script

Scene-by-scene test cases for recording a demo video. Each scene lists the
exact action, the words/questions to use, and the expected on-screen result.
`docs/demo-checklist.md` remains the full setup checklist; this file is the
camera-ready script.

Scenes 4-6 use the control plane, memory map, and channel policy toggle from
PRs #12-#14; record on a build where those are merged.

## Pre-flight (off camera)

1. Server running (local `docker compose up` or the Hetzner demo), Slack app
   connected, bot invited to one public test channel (e.g. `#demo-general`).
2. Reset memory so the story is deterministic:

   ```sh
   docker compose exec -T control-panel mix run scripts/reset-demo-memory.exs
   ```

3. Have `priv/fixtures/demo/handbook.md` (or any short policy Markdown file
   with one memorable, falsifiable fact) on your desktop, e.g.:

   > Reimbursements above 500 EUR require manager approval.

4. Log in to the admin UI. Keep two windows side by side: Slack on the left,
   admin UI on the right.
5. Without `OPENAI_API_KEY` the deterministic fallback answers with the top
   memory chunk and citations; with a key the answer is model-written. Both
   demo fine — the citations and audit trail are the story.

## Scene 1 — The empty appliance (30s)

- Open `/admin/control-plane`.
- Say: "This is a governed AI operator. Right now it knows nothing."
- Expected: Memory service card shows 0 chunks; the Governed activity
  timeline shows the teaching empty state ("No evidence yet...").

## Scene 2 — Knowledge with provenance (60s)

- Go to Sources, upload the handbook file, click Ingest.
- Switch to `/admin/control-plane` (or have it open in a second tab —
  events stream in live without refresh).
- Expected: `Source ingested` and `Memory indexed` events appear at the top
  of the timeline; Memory service card counts the new chunks.
- Click the `Source ingested` row.
- Expected: inspector opens with actor, component, sanitized Evidence
  (chunk counts, source ids — never file contents), and citation link.
- Say: "Every change to what the agent knows is recorded as evidence."

## Scene 3 — A cited answer in Slack (60s)

- In the test channel, ask:

  > @andnative-ai When do reimbursements need manager approval?

- Expected in Slack: an answer containing "above 500 ... manager approval"
  with a citation link back to the handbook source.
- Switch to the control plane.
- Expected: a burst of new events — `Slack mention`, `Memory searched`,
  `Answer generated`, `Citation attached`, `Slack response posted` — all
  sharing one request id.
- Click any of them; walk the Request trace in the inspector (relative
  offsets show the whole answer took ~a second).
- Say: "One question, five pieces of evidence, one request id. This is what
  'not freewheeling through your company data' looks like."

## Scene 4 — What is it allowed to know? (45s)

- Open `/admin/memory`.
- Expected: Slack channels and Documents groups with chunk counts; the
  handbook expands to show its chunks, each with retention, visibility, and
  a citation link. The "Function & person scope" card is explicitly labeled
  *planned* — nothing pretends ACLs exist.
- Say: "The memory map is the honest answer to 'what does it know and
  where did that come from'."

## Scene 5 — Governed forgetting (90s, the money shot)

- Say: "Now the part every buyer asks about: deletion."
- In Sources, delete the handbook (confirm the dialog).
- Expected: control plane records `Source deleted`; the memory map now
  shows the handbook struck through, "deleted — excluded from retrieval",
  with 0 chunks in retrieval.
- Back in Slack, ask the exact same question again:

  > @andnative-ai When do reimbursements need manager approval?

- Expected: the bot answers that it could not find a relevant source — no
  citation, no half-remembered answer.
- Say: "Same question, sixty seconds later. Deleted means deleted, and the
  audit trail proves both moments."
- (This exact cycle is also enforced in CI:
  `test/andnative_ai/demo/acceptance_test.exs`.)

## Scene 6 — Policy, not vibes (45s, optional)

- In Sources → Slack channels, flip "App & bot posts" ON for the test
  channel.
- Expected: a `Policy changed` governance event appears on the timeline
  with the changed setting in Evidence.
- Have a Linear notification post into the channel (or paste one from a
  connected Linear workspace), then ask:

  > @andnative-ai did we add MiniMax?

- Expected: the answer cites the Slack permalink of the Linear
  notification.
- Say: "Even which machine messages become memory is an explicit,
  audited policy decision."

## Scene 7 — Close (15s)

- Return to the control plane, top of page.
- Say: "Sources connected, answers with citations, evidence for every
  action, and honest labels on everything we estimate. This is the
  appliance we install inside your company."

## Reset between takes

```sh
docker compose exec -T control-panel mix run scripts/reset-demo-memory.exs
```

Then re-invite/backfill the Slack channel if needed:

```sh
docker compose exec -T control-panel mix run scripts/backfill-slack-channel.exs C0123456789
```

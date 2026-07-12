# Playbook: Memory → Skills → Actions

Status: proposal (2026-07-12), researched with three deep-dive passes
(taxonomy patterns in RAG products, the Agent Skills standard, deep-research
provider APIs). Companion tickets: AAI-23..AAI-28.

The through-line: the appliance today proves **Memory** (what the company
knows, governed). The next two layers are **Skills** (how to do things well)
and **Actions** (actually doing them) — on the same audit timeline, the same
policy toggles, the same citations. Nothing about the governance story
changes; its surface area grows from answers to work.

---

## Part 1 — Collections: how the system knows "this is the handbook"

### Problem

A pile of markdown files (e.g. the 37signals handbook corpus in `../data`)
carries no machine-readable statement of what it *is*. Retrieval treats
"Benefits and Perks.md" like any text; answers can't say "per the employee
handbook" and admins can't scope or reason about the corpus as a unit.

### What the research says

- Every mature product converges on the same primitive: a **named container
  with a human-written description** — Glean Collections, Onyx Document
  Sets, Dust Spaces/Folders, Claude/ChatGPT Projects, NotebookLM notebooks.
  The description both scopes retrieval and frames generation.
- The strongest evidenced retrieval technique is **contextual chunk
  situating** (Anthropic "Contextual Retrieval"): prepend a short context
  line to each chunk before embedding/BM25 — 49% fewer retrieval failures
  (67% with reranking), ~$1 per million document tokens with prompt caching.
- Folder paths are free metadata: path-augmented chunking measurably lifts
  retrieval accuracy. NotebookLM's auto-labeling shows "LLM proposes,
  human confirms" works at consumer scale.
- No industry-standard "collection manifest" file exists yet (llms.txt and
  AGENTS.md are the nearest cousins) — we can define a light convention.

### Design (v1 — AAI-23)

**Primitive**: `collections` table — `tenant_id`, `name` ("Company
handbook"), `kind` (handbook | policies | product | meeting_notes |
research | conversation | custom), `description` (1–2 sentences, required),
`slug`. `memory_sources.collection_id` (nullable FK). Slack channels get a
collection of kind `conversation` automatically — one mental model on the
memory map.

**Context derivation — three intuitive inputs, least magic wins:**

1. **Folder/zip upload**: drag a folder (`webkitdirectory` + LiveView
   uploads) or a zip; the folder name proposes the collection name; each
   file becomes a source inside it.
2. **Propose-and-confirm**: at ingest a cheap LLM pass proposes kind +
   description ("This looks like an employee handbook covering onboarding,
   benefits, titles…"). The admin confirms or edits before it takes effect.
   The confirmation writes a governance audit event — suggestion by machine,
   decision by human, on the timeline.
3. **Manifest convention (optional, power users)**: a `_collection.md` with
   YAML frontmatter (`name`, `kind`, `description`) at the folder root wins
   over inference. Per-file frontmatter (`title`, `doc_type`) is honored
   when present.

**How it feeds retrieval (the part that matters):**

- Static context line prepended to every chunk at embedding time:
  `[{collection.name} — {kind}: {source.name}] {chunk}`. Near-zero cost, no
  LLM call, and the retrieval + rerank layers finally know what a chunk is.
- Scope filters: search within a collection (API `scope`, UI filter, and
  later per-agent allowed collections — the memory map's "scope layers"
  card stops being aspirational).
- Citation labels: answers cite `Company handbook › Benefits and Perks`.
- Memory map groups by collection instead of raw source type.

**v1.1 upgrade (AAI-24)**: swap the static prefix for LLM-generated chunk
situating (full doc + collection description in a prompt-cached call) and
replace the deterministic hash embeddings with provider embeddings at the
same time — the two changes multiply, and the schema/UI from v1 carry over
unchanged.

**Demo acceptance**: upload the 37signals handbook folder from `../data` →
confirm "Employee handbook" proposal → ask a benefits question in Slack →
answer cites `Employee handbook › Benefits and Perks` → delete the
collection → same question is honestly unanswerable.

---

## Part 2 — Actions: the agent does work, governed

### Runner (AAI-25)

Long-running work needs a job spine. **Oban** (Postgres-backed) fits the
appliance: no new infra, jobs survive restarts, retries/backoff built in.

- `agent_actions` table: tenant, agent, kind, status (queued → running →
  awaiting_approval → completed | failed), input summary, result file path,
  Slack channel/thread, request_id, cost fields (provider, tokens/price
  where known).
- **Slack UX**: mention with an intent prefix (v1 routing is deliberately
  dumb: `@agent research: <topic>` / `@agent write: <task>`) → immediate
  threaded ack ("On it — this takes a few minutes") → progress edits on the
  ack message → deliverable posted in-thread.
- **Delivery**: Slack **Canvas** for the rendered document (canvases render
  markdown properly; raw `.md` files show as plain text) + the `.md` file
  attached via `files.getUploadURLExternal` → `files.completeUploadExternal`
  (`files.upload` is retired since Nov 2025; there is no Elixir SDK for
  this — implement the 3-call flow in our Slack client).
- **Governance**: new audit kinds `action_requested`, `action_started`,
  `action_completed`, `action_failed`, `action_approved` — one request_id
  from mention to deliverable, visible as a trace in the control plane.
  Actions that spend real money or produce outbound-facing content can
  require approval: the **Approval gates card on the control plane finally
  goes live** — a pending action shows up, a human clicks approve, the
  approval is evidence.
- **Memory loop**: every deliverable can be ingested back as a source in a
  `research`/`writing` collection (provenance: the action + its citations).
  The appliance gets smarter with every action it performs.

### First action: deep research (AAI-26)

`@agent research: <topic>` → provider researches for minutes → cited
markdown dossier lands in the thread (Canvas + downloadable .md).

Provider landscape (researched, mid-2026):

| Provider | Shape | Cost/query | Notes |
|---|---|---|---|
| Perplexity `sonar-deep-research` | async submit + poll | ~$0.30–1.30 | simplest call, stable, poll-only |
| Gemini Deep Research (Interactions API) | background + poll | ~$1–3 (Max $3–7) | native markdown+citations, still `-preview-` snapshots |
| Exa Deep / Research tasks | async task + poll | $12–15/1k | field-level citations, schema-shaped output |
| OpenAI o3/o4-mini-deep-research | background + **webhook** | ~$0.40–8 | best async ergonomics, but models flagged deprecated — verify before building on them |
| Anthropic web_search tool | you orchestrate | $10/1k searches + tokens | no turnkey dossier; precise quoted citations |

**Decision**: a `ResearchProvider` behaviour with the lowest common
denominator — `submit/2` → `poll/1` (covers Perplexity, Gemini, Exa; a
webhook variant can short-circuit polling later). **Ship Perplexity first**
(stable + cheapest + simplest), **Gemini second** (best native markdown).
Oban makes polling trivial.

### Skill-powered writing actions (AAI-28)

`@agent write: launch email for the new onboarding feature` → agent loads
the relevant skill (see Part 3) + relevant collections (product docs,
positioning) → drafts → delivers as Canvas + file, cited where memory was
used. Outbound-facing outputs can sit behind an approval gate.

---

## Part 3 — Skills: the open standard, governed (AAI-27)

### What the research says

- The **Agent Skills** spec (SKILL.md) lives at agentskills.io — an open
  standard since Dec 2025, governed separately from MCP. Frontmatter
  (`name`, `description`, optional `license`, `compatibility`, `metadata`,
  experimental `allowed-tools`), optional `references/`, `scripts/`,
  `assets/`. **Progressive disclosure**: only name+description (~100
  tokens/skill) load at startup; the body (<5k tokens) loads on activation;
  references on demand.
- Adoption is genuinely cross-vendor: ~32 runtimes including Codex CLI,
  Gemini CLI, Cursor, Copilot/VS Code, opencode, Goose, Letta. Prompt-only
  skills (no scripts) require nothing but file reads — perfect for a
  runtime like ours.
- **Security is the catch**: one registry audit found 36.8% of skills had
  flaws, 13.4% critical; the `` !`command` `` dynamic-injection syntax
  executes *before* any model review. Anthropic's own guidance: only trusted
  sources. Mitigations that matter: no script execution, version pinning,
  content scanning, per-skill capability grants, human approval on install.
- **Corey Haines' marketing skills**: `coreyhaines31/marketingskills`, MIT,
  50+ skills (CRO, copywriting, SEO, email, launch, pricing…), with a
  clever convention — a `product-marketing` foundation skill that every
  other skill consults for product/audience/positioning context.

### Design — phase 1: prompt-pack skills

- `skills` table: tenant_id, name, description, body, version (content
  hash), source_url, license, installed_at; `agent_skills` join for
  per-agent enablement.
- Importer parses SKILL.md (+ `references/*.md`), **rejects anything with
  `scripts/` or dynamic-injection syntax in v1** — prompt-pack skills only.
  That single constraint removes the entire malicious-code class while
  keeping most of the ecosystem usable (all of the marketing pack is
  prompt-only).
- Runtime: enabled skills' name+description go into the agent's system
  prompt (progressive disclosure, exactly per spec); the responder loads a
  skill's body when the action/intent names it or the model asks.
- **Governance is our differentiator**: install/enable/disable are audit
  events (`skill_installed`, `skill_enabled`…) with version hash; the
  request trace shows *which skill and version shaped the output*. No other
  runtime shows that today.
- The 37signals-style pairing: the `product-marketing` foundation context
  becomes a **collection** (Part 1) rather than a file — skills say *how*,
  memory says *what*. That composition is the whole product in one line.
- Phase 2 (separate, later): scripted skills in a sandboxed executor with
  allow-listed egress — explicitly out of scope until there's a real need.

---

## Part 4 — Action catalog (brainstorm, prioritized)

| Action | Trigger | Uses | Impact / Effort |
|---|---|---|---|
| Deep research dossier | `research:` mention | provider adapter | High / Med — AAI-26 |
| Marketing writing pack | `write:` mention | skills + collections | High / Med — AAI-28 |
| Weekly memory digest | schedule (Oban cron) | memory only | High / Low — decisions, commitments, new sources → Monday post; pure retention feature |
| Meeting transcript distillation | file upload or `distill:` | memory ingest | Med / Low — transcript → decisions/open loops into a `meeting_notes` collection |
| Draft reply with policy citations | `draft:` mention | handbook collections | High / Low — "answer this customer per our policy," citations attached |
| Competitor watch | scheduled research | research adapter | Med / Low once AAI-26 exists — a monitor that files dossiers |
| Onboarding pack generator | `onboard:` | handbook collection | Med / Low — personalized first-week doc from the handbook |
| Commitment extraction | `commitments:` | Slack collections | Med / Low — "everything we promised in #project-x this week" |

Sequencing principle: everything read-only ships without gates; anything
that spends money (research providers) or faces outward (marketing copy)
goes through the approval gate from day one. The gates make the demo
*better*, not slower — a human click is evidence.

---

## Rollout

1. **AAI-23** Collections + folder upload + propose-and-confirm (unlocks the
   handbook demo properly)
2. **AAI-25** Action runner + Slack thread UX + Canvas/file delivery +
   action audit kinds + approval gates
3. **AAI-26** Deep research action (Perplexity first, adapter for Gemini/Exa)
4. **AAI-27** Agent Skills phase 1 (prompt-pack, governed)
5. **AAI-28** Marketing writing actions (skills × collections)
6. **AAI-24** Retrieval quality upgrade (provider embeddings + contextual
   chunk situating) — any time after AAI-23

Dependencies: AAI-26 and AAI-28 need AAI-25; AAI-28 needs AAI-27.

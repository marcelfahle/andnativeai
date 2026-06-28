# Agent Setup

The current PoC supports a small number of OpenClaw-backed agents for the demo
tenant. Slack answering still uses one default responder; multiple-agent routing
is not productized yet.

## Recommended Demo Agent

Create one primary agent in `/admin/agents`:

- Name: `Albert` or the customer-facing assistant name.
- Model: `gpt-4.1-mini`.
- Status: `active`.
- Identity:

```text
Answer from governed memory with concise citations.
If memory does not contain the answer, say that you could not find a relevant source.
Do not invent policy, owners, dates, approvals, or customer facts.
Keep Slack answers short.
```

Optional behavior demo:

```text
Answer from governed memory with concise citations. Start every conversation with "Yo!"
```

After saving, click **Sync**. Sync writes the OpenClaw config under
`OPENCLAW_WORKSPACE_PATH` and changes the agent status to `synced`.

## How Slack Chooses An Agent

Current behavior:

- Slack mentions call `AndnativeAi.Runtime.Responder`.
- If an explicit agent is passed by code, that agent is used.
- Socket Mode does not yet pass a channel-specific or workspace-specific agent.
- The default responder chooses from tenant agents.

Operational rule for the PoC:

- Keep one synced primary agent for Slack demos.
- Use a second agent only for behavior experiments.
- When testing the second agent, edit/sync it and avoid ambiguity by keeping the
  primary agent clearly named and current.

## Multiple Agents Today

The UI currently enforces a demo limit of two agents.

Use the second slot for:

- comparing identity prompts,
- testing a different model,
- showing that behavior changes after edit + sync.

Do not use it yet for:

- separate Slack channels,
- separate customer workspaces,
- different data-source policies,
- approval-policy ownership.

Those require explicit routing and policy fields that do not exist yet.

## Future Multi-Agent Shape

The next durable design should add an assignment layer, for example:

- workspace default agent,
- channel default agent,
- source or skill policy,
- fallback agent when no route matches.

That route should be resolved before `Responder.respond_to_slack/3` dispatches
to OpenClaw. The selected route should also be written to the runtime audit
timeline so demos can show why a specific agent answered.

## Testing Agent Behavior

1. Open `/admin/agents`.
2. Create or edit the primary agent.
3. Click **Sync**.
4. Upload or backfill a source.
5. Ask the bot a question in Slack.
6. Confirm:
   - answer follows the identity,
   - answer only uses governed memory,
   - citations point to Slack or document sources,
   - unrelated questions return "could not find a relevant source."

If the answer ignores the identity, confirm `OPENAI_API_KEY` is set. Without an
API key, deterministic fallback behavior still works but only supports a narrow
subset of identity instructions such as `Start every conversation with "Yo!"`.

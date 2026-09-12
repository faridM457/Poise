# Conversation Engine — Local Test Site

A local, text-only test harness for validating the workplace-conversation trainer's
Conversation Engine (scenario generation → NPC dialogue loop → grading → feedback)
before any mobile/voice integration. See `spec/conversation-engine-spec.md` for the full
spec this implements.

## Setup

```bash
npm install
claude login   # if you haven't already logged Claude Code into your account
cp .env.example .env
npm start
```

Open http://localhost:3000.

No `ANTHROPIC_API_KEY` needed: the backend calls Claude through the **Claude Agent SDK**
(`@anthropic-ai/claude-agent-sdk`), which shells out to your local Claude Code CLI and reuses
whatever account it's logged into. If that's a Claude Pro/Max subscription, calls count
against your plan's usage instead of per-token API billing — same mechanism the `manifold`
repo uses. Model defaults to `haiku` to go easy on plan usage; override with
`CLAUDE_ENGINE_MODEL=sonnet` (or `opus`, or a full model ID) in `.env`.

Because it drives an actual Claude Code subprocess per call, each engine stage is slower than
a direct Messages API call and consumes your plan's rate-limit window rather than dollars —
worth keeping in mind if you hit "rate_limit" errors mid-testing.

## Structure

- `server/lessons.js` — hardcoded lesson definitions (title, character, scenario template,
  guide criteria, persona behavior notes).
- `server/llm.js` — wraps `@anthropic-ai/claude-agent-sdk`'s `query()`, using
  `outputFormat: {type: "json_schema"}` to force each call to end in structured JSON matching
  the stage's schema.
- `server/engine.js` — the engine stages from the spec:
  - `generateScenario` (Stage 1)
  - `generateOpeningLine` (Stage 3)
  - `runTurn` (Stage 4 — one turn of the loop, including the exit-condition and
    resolution logic, applied locally rather than trusted to the LLM)
  - `generateFeedback` (Stage 6)
- `server/index.js` — Express API exposing those stages (`/api/scenario`, `/api/opening`,
  `/api/turn`, `/api/feedback`), plus `/api/lessons` to list hardcoded lessons.
- `public/` — plain HTML/CSS/JS chat interface. Conversation state (history, met criteria,
  turn count, deductions) lives client-side and is sent back to the server each turn, so
  the server stays stateless and a lesson can be reset and re-run freely.

## Notes

- Delivery scoring is stubbed out in the feedback panel per the spec (out of scope this
  milestone).
- Checkpoint lessons hide the guide criteria in the UI but still track them server-side.
- Use the "Reset & run again" button to re-run the same lesson and compare scenario
  variety and grading consistency across attempts.

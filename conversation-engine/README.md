# Conversation Engine — Local Test Site

A local, text-only test harness for validating the workplace-conversation trainer's
Conversation Engine (scenario generation → NPC dialogue loop → grading → feedback)
before any mobile/voice integration. See `spec/conversation-engine-spec.md` for the full
spec this implements.

## Setup

```bash
npm install
cp .env.example .env   # then add your ANTHROPIC_API_KEY
npm start
```

Open http://localhost:3000.

## Structure

- `server/lessons.js` — hardcoded lesson definitions (title, character, scenario template,
  guide criteria, persona behavior notes).
- `server/llm.js` — thin Anthropic client wrapper that forces structured (tool-call) JSON
  output for each engine stage.
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

# Conversation Engine Spec — Workplace Conversation Trainer

## App Context

This is a Duolingo-style mobile app for practicing hard workplace conversations. Users go through **Lessons** organized into **Units** (e.g., Unit C: Managing Down, Unit E: Everyday Workplace Friction). Each lesson presents a realistic workplace scenario, and the user has a spoken (eventually) or typed (for now) conversation with an AI-driven character (NPC) who plays the other party in the conversation — a direct report, a coworker, a manager, etc.

The core value proposition: realistic, dynamic roleplay (not scripted dialogue trees) that teaches specific communication skills — naming issues directly, staying neutral, holding boundaries, delivering hard news with empathy — through repeated, varied practice.

This spec covers the **Conversation Engine**: the backend logic that generates scenarios, runs the turn-by-turn dialogue with the NPC, tracks whether the user is demonstrating the target skills, and produces feedback at the end.

## Validation Goal (Current Milestone)

Build a **local test website** to validate the conversation engine's logic before any mobile/voice integration. Scope for this milestone:
- **Text-only input/output.** User types responses; NPC dialogue is displayed as text. No STT, no TTS, no character animation yet.
- **Content grading only.** Voice/delivery analysis (pace, filler words, pauses) is a separate, later feature — not part of this milestone. Only the content-criteria grading described below needs to work now.
- Goal: prove the full scenario-generation → dialogue-loop → grading pipeline works end-to-end and produces sensible, varied, well-graded conversations before investing in voice/animation integration.

## Lesson Input Format

Each lesson provides the Conversation Engine with:
- **Lesson title** (e.g., "Giving Critical Feedback")
- **Character(s) involved** — name, role, relationship to the user (e.g., "Marcus, direct report, 8 months on the team")
- **Scenario template** — a description of the situation type, used to generate unique specifics per attempt (not a fixed scenario — see Stage 1 below)
- **Guide criteria** — a fixed list of 2-4 skill criteria the user should demonstrate (e.g., "Named the specific behavior," "Stated the impact," "Asked for their perspective before concluding")
- **Persona behavior notes** — how the NPC should react dynamically (e.g., "starts wary, becomes defensive if criticized bluntly, becomes open if the user acknowledges their situation before addressing the issue")

Note: existing lesson docs (Unit C, Unit E) contain illustrative example scenarios and dialogue paths — these are references for tone and structure, not scripts to reproduce literally. The engine should generate fresh scenario specifics each time, per Stage 1 below.

## Global Rules

- **Max 5 user turns per scenario.** A "turn" = one user response. This is a hard cap, not a target length.
- **Early exit is allowed** — if all criteria are met before turn 5, the scenario resolves immediately. Don't force additional turns once criteria are satisfied.
- **Criteria lock in once met** — once a criterion is marked satisfied, it stays satisfied for the rest of the conversation, even if later turns don't reference it again.
- **Criteria can be met in any order, and multiple criteria can be satisfied in a single turn** if the user's response covers more than one (e.g., naming the issue and stating its impact in one sentence).
- **Appropriateness is checked separately from content criteria, every turn** — see Stage 4 below.

## The Conversation Flow

### Stage 1 — Scenario Generation
Given the lesson's scenario template and guide criteria, generate a unique scenario instance:
- Specific names, incidents, numbers/data points (concrete, not vague)
- A briefing text (2-4 sentences) summarizing the situation for the user
- The same fixed guide criteria from the lesson (not regenerated — these stay constant per lesson)

Output format (structured):
```json
{
  "briefing": "string",
  "data_point": "string",
  "criteria": ["string", "string", "string"]
}
```

### Stage 2 — Present Scenario to User
Display: briefing text, data point, and guide criteria (guide is hidden for checkpoint-type lessons — see "Checkpoints" below).

### Stage 3 — Opening NPC Line
Generate a natural opening line from the NPC, consistent with the persona behavior notes. This does not depend on user input yet.

### Stage 4 — Turn Loop (repeats until an exit condition is hit)

On each user turn, the engine sends the LLM: the scenario, full conversation history so far, the criteria list with current met/unmet status, and the new user response. The LLM returns, in one structured call:

```json
{
  "npc_reply": "string",
  "newly_met_criteria": ["string", ...],
  "appropriateness": "normal | mild_flag | severe_flag"
}
```

**Processing this response:**
1. Merge `newly_met_criteria` into the running "met" set (criteria already met stay met, regardless of this turn's content).
2. Check `appropriateness`:
   - `severe_flag` → end the conversation immediately. Resolution = **negative**, regardless of how many criteria are currently met. NPC's `npc_reply` for this case should react realistically in-character (discomfort, shutting the conversation down) — do not skip straight to a generic system message.
   - `mild_flag` → do not end the conversation. Record a professionalism deduction (see Grading below). Continue the loop normally otherwise.
   - `normal` → continue the loop normally.
3. If not ended by a severe flag, check exit conditions in this order:
   - **All criteria now met** → end conversation. Resolution = **approving**.
   - **This was turn 5 (the cap) and criteria are still incomplete** → end conversation. Resolution = **scaled**, based on the proportion of criteria met (see Grading below).
   - **Otherwise** → display `npc_reply`, loop continues to the next user turn.

### Stage 5 — Resolution
The NPC's final line (already generated as part of the last `npc_reply` in Stage 4, for the turn that triggered the exit) should reflect the outcome naturally and in-character:
- **Approving:** NPC's tone reflects the conversation landing well (specifics depend on persona — e.g., relieved, appreciative, cooperative).
- **Scaled (partial):** NPC's tone is proportionally lukewarm/unresolved — better than a full miss, not as good as full success.
- **Negative (cap hit with low/no criteria met, or severe flag):** NPC's tone is flat, unresolved, or shut-down, depending on persona.

Important: the NPC should never explicitly state which criteria were or weren't met ("you didn't ask my perspective") — that information belongs only in the Stage 6 feedback screen, not in-character dialogue. The NPC reacts like a real person would, not like a grading rubric.

### Stage 6 — Feedback
After resolution, generate and display:
- **Content checklist:** each criterion, marked met/unmet
- **Professionalism deductions:** if any mild flags occurred during the conversation, note them
- **Delivery score:** *(not part of this milestone — stub this out or omit entirely for the local test site)*
- **Feedback line:** a short, human-readable summary (1-2 sentences) of what went well and what to improve next time, generated by the LLM based on the full conversation + criteria results

## Checkpoints

Checkpoint-type lessons (one per unit, testing combined skills) follow the same engine logic, with two differences:
- The Guide is **not shown** to the user in Stage 2 (they apply skills independently)
- Hints (a separate, related feature — see note below) are disabled

**Note on hints:** hints are a related but separate feature from this spec — a UI element that surfaces a relevant (unmet) criterion as guidance if the user pauses for 5+ seconds before responding. This is a voice/timing-dependent feature and is out of scope for the text-only local test site milestone, but the engine's criteria-tracking (which criteria are currently unmet) should be exposed in a way that a future hint system can consume.

## What This Local Test Site Needs To Do

1. Let a developer select a lesson (from a small set of hardcoded lesson definitions matching the Input Format above).
2. Run Stage 1 (generate scenario) and display the briefing/data point/criteria.
3. Run Stage 3 (opening NPC line) and display it.
4. Provide a text input for the "user" to type responses, simulating the turn loop (Stage 4) with real LLM calls.
5. Display the NPC's replies turn by turn as a simple chat interface.
6. On resolution, display the Stage 6 feedback (checklist, deductions, feedback line).
7. Ideally, allow a developer to reset and re-run the same lesson multiple times to observe scenario variety and grading consistency across attempts.

This does not need polish — it's a debugging/validation tool for the conversation engine logic, not a user-facing product. Plain HTML/simple frontend is fine; the focus should be on getting the LLM prompting and state-tracking logic right.

## Explicitly Out of Scope for This Milestone

- Speech-to-text / text-to-speech
- Character animation / any visual character system
- Delivery/voice analysis (pace, filler words, pauses)
- Hints UI (pause-detection dependent)
- Mobile app integration
- Persistent user progress, XP, streaks, or any gamification

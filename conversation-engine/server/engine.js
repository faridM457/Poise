import { structuredCall } from "./llm.js";

export const MAX_USER_TURNS = 5;

function formatCharacter(lesson) {
  const { name, role, relationship } = lesson.character;
  return `${name} (${role} — ${relationship})`;
}

function formatHistory(history) {
  if (history.length === 0) return "(no messages yet)";
  return history
    .map((turn) => `${turn.role === "npc" ? lessonCharacterLabel(turn) : "User"}: ${turn.text}`)
    .join("\n");
}

// history entries carry the character name for npc turns so multi-character
// lessons stay readable; falls back to a generic label otherwise.
function lessonCharacterLabel(turn) {
  return turn.character ?? "NPC";
}

// Applied to every system prompt so all generated text — scenarios, dialogue,
// feedback — reads as something a real person from any industry would say,
// not corporate-speak or AI-flavored prose.
const WRITING_STYLE =
  "Writing style rules (apply to everything you write):\n" +
  '- Plain, universal language. No corporate jargon, acronyms, or insider shorthand ("COB", "EOD", ' +
  '"KPI", "circle back", "synergy", "bandwidth", "1:1", etc.) — spell things out in plain words anyone, ' +
  'in any industry, would immediately understand on first read, with nothing that could be misread. ' +
  'Say "by the end of the day Friday", not "COB Friday". Say "one-on-one meeting", not "1:1". If you\'re ' +
  "not sure a term is universally clear, spell it out instead.\n" +
  "- Never use an em dash or a semicolon. Use a period, comma, or a word like \"and\" or \"but\" instead.\n" +
  '- Avoid AI-sounding phrasing: no "it\'s not just X, it\'s Y" constructions, no "dive into" / "delve ' +
  'into", no "leverage" / "robust" / "seamless" / "testament to" / "boasts", no stacked adjective ' +
  "triplets, no overly polished or formal sentence structure. Write the way a real person would " +
  "actually say or type it: plain, a little imperfect, natural rhythm.";

// Stage 1 — Scenario Generation
export async function generateScenario(lesson) {
  const system =
    "You generate fresh, concrete scenario specifics for a workplace-conversation training app. " +
    "The scenario must be realistic, specific (real-sounding names, numbers, incidents), and different " +
    "each time it's generated for the same lesson. Do not restate the guide criteria in your prose — " +
    "those are supplied separately by the app.\n\n" +
    WRITING_STYLE;

  const userMessage =
    `Lesson: ${lesson.title} (${lesson.unit})\n` +
    `Other party: ${formatCharacter(lesson)}\n` +
    `Scenario template: ${lesson.scenarioTemplate}\n` +
    `Persona behavior notes: ${lesson.personaNotes}\n\n` +
    "Generate a unique instance of this scenario: a short briefing (2-4 sentences) for the user " +
    "describing the situation, and a single concrete data point (a number, date, or specific detail) " +
    "that grounds the scenario.";

  const schema = {
    type: "object",
    properties: {
      briefing: {
        type: "string",
        description: "2-4 sentence briefing summarizing the situation for the user.",
      },
      data_point: {
        type: "string",
        description: "One concrete, specific detail (number, date, incident) grounding the scenario.",
      },
    },
    required: ["briefing", "data_point"],
  };

  const result = await structuredCall({
    system,
    messages: [{ role: "user", content: userMessage }],
    schema,
    toolName: "submit_scenario",
    maxTokens: 512,
  });

  return {
    briefing: result.briefing,
    data_point: result.data_point,
    criteria: lesson.criteria,
  };
}

// Stage 3 — Opening NPC Line
export async function generateOpeningLine(lesson, scenario) {
  const system =
    `You are roleplaying as ${formatCharacter(lesson)} in a workplace conversation training app. ` +
    "Stay fully in character. Do not break the fourth wall, do not reference criteria or grading, " +
    "and do not resolve the conversation yet, this is the opening line only.\n\n" +
    WRITING_STYLE;

  const userMessage =
    `Scenario briefing: ${scenario.briefing}\n` +
    `Relevant detail: ${scenario.data_point}\n` +
    `Persona behavior notes: ${lesson.personaNotes}\n\n` +
    "Generate a natural opening line for the NPC to start this conversation with the user. " +
    "It should not depend on anything the user has said yet.";

  const schema = {
    type: "object",
    properties: {
      opening_line: { type: "string", description: "The NPC's opening line of dialogue." },
    },
    required: ["opening_line"],
  };

  const result = await structuredCall({
    system,
    messages: [{ role: "user", content: userMessage }],
    schema,
    toolName: "submit_opening_line",
    maxTokens: 256,
  });

  return result.opening_line;
}

// Stage 4 — one iteration of the turn loop. Calls the LLM for npc_reply /
// newly_met_criteria / appropriateness, then applies the exit-condition
// rules from the spec (severe flag, all-criteria-met, turn cap) locally
// rather than trusting the LLM to decide resolution.
export async function runTurn({ lesson, scenario, history, metCriteria, turnNumber, userResponse }) {
  const unmetCriteria = lesson.criteria.filter((c) => !metCriteria.includes(c));

  const system =
    `You are roleplaying as ${formatCharacter(lesson)} in a workplace conversation training app, and ` +
    "you also grade the user's latest response against fixed skill criteria. Stay fully in character " +
    "for npc_reply — never mention criteria, grading, or appropriateness in the dialogue itself. " +
    "Persona behavior notes: " +
    lesson.personaNotes +
    "\n\n" +
    "Appropriateness grading (applies to the user's latest message only, independent of criteria):\n" +
    '- "normal": professional, on-topic.\n' +
    '- "mild_flag": unprofessional but not severe (e.g. dismissive, mildly rude, off-topic) — the ' +
    "conversation continues, but this is logged as a deduction.\n" +
    '- "severe_flag": abusive, harassing, discriminatory, or otherwise conversation-ending. If severe, ' +
    "npc_reply must react realistically in-character (discomfort, shutting the conversation down) — " +
    "do not skip to a generic system message.\n\n" +
    "Criteria grading rules:\n" +
    "- Only include a criterion in newly_met_criteria if the user's LATEST message satisfies it — " +
    "criteria already met are tracked by the app, not by you.\n" +
    "- A single message can satisfy multiple criteria at once.\n" +
    "- Never have the NPC state out loud which criteria were or weren't met.\n\n" +
    WRITING_STYLE;

  const userMessage =
    `Scenario briefing: ${scenario.briefing}\n` +
    `Relevant detail: ${scenario.data_point}\n\n` +
    `All guide criteria: ${lesson.criteria.join(" | ")}\n` +
    `Already met: ${metCriteria.length ? metCriteria.join(" | ") : "(none yet)"}\n` +
    `Still unmet: ${unmetCriteria.length ? unmetCriteria.join(" | ") : "(none)"}\n\n` +
    `Conversation so far:\n${formatHistory(history)}\n\n` +
    `This is user turn ${turnNumber} of a maximum of ${MAX_USER_TURNS}.\n` +
    `User's latest response: "${userResponse}"\n\n` +
    "Generate the NPC's reply and grade this response.";

  const schema = {
    type: "object",
    properties: {
      npc_reply: { type: "string", description: "The NPC's in-character reply to the user's latest message." },
      newly_met_criteria: {
        type: "array",
        items: { type: "string", enum: unmetCriteria.length ? unmetCriteria : lesson.criteria },
        description: "Criteria (from the unmet list) newly satisfied by this message. Empty array if none.",
      },
      appropriateness: {
        type: "string",
        enum: ["normal", "mild_flag", "severe_flag"],
      },
    },
    required: ["npc_reply", "newly_met_criteria", "appropriateness"],
  };

  const result = await structuredCall({
    system,
    messages: [{ role: "user", content: userMessage }],
    schema,
    toolName: "submit_turn",
    maxTokens: 512,
  });

  // Merge newly met criteria into the running set (criteria lock in once met).
  const updatedMetCriteria = Array.from(new Set([...metCriteria, ...result.newly_met_criteria]));
  const deduction = result.appropriateness === "mild_flag";

  let ended = false;
  let resolution = null;

  if (result.appropriateness === "severe_flag") {
    ended = true;
    resolution = "negative";
  } else {
    const allMet = lesson.criteria.every((c) => updatedMetCriteria.includes(c));
    if (allMet) {
      ended = true;
      resolution = "approving";
    } else if (turnNumber >= MAX_USER_TURNS) {
      ended = true;
      resolution = "scaled";
    }
  }

  return {
    npc_reply: result.npc_reply,
    appropriateness: result.appropriateness,
    newly_met_criteria: result.newly_met_criteria,
    updated_met_criteria: updatedMetCriteria,
    deduction,
    ended,
    resolution,
  };
}

// Stage 6 — Feedback
export async function generateFeedback({ lesson, scenario, history, metCriteria, deductionCount, resolution }) {
  const checklist = lesson.criteria.map((criterion) => ({
    criterion,
    met: metCriteria.includes(criterion),
  }));

  const system =
    "You write brief, constructive feedback for a workplace-conversation training app, based on a " +
    "completed practice conversation. Be specific and human, not generic. 1-2 sentences only.\n\n" +
    WRITING_STYLE;

  const userMessage =
    `Lesson: ${lesson.title}\n` +
    `Scenario briefing: ${scenario.briefing}\n\n` +
    `Conversation:\n${formatHistory(history)}\n\n` +
    `Criteria results:\n${checklist
      .map((c) => `- ${c.criterion}: ${c.met ? "met" : "not met"}`)
      .join("\n")}\n` +
    `Professionalism deductions: ${deductionCount}\n` +
    `Overall resolution: ${resolution}\n\n` +
    "Write a 1-2 sentence feedback summary covering what went well and what to improve next time.";

  const schema = {
    type: "object",
    properties: {
      feedback_line: { type: "string", description: "1-2 sentence feedback summary." },
    },
    required: ["feedback_line"],
  };

  const result = await structuredCall({
    system,
    messages: [{ role: "user", content: userMessage }],
    schema,
    toolName: "submit_feedback",
    maxTokens: 256,
  });

  return {
    checklist,
    deductionCount,
    resolution,
    feedbackLine: result.feedback_line,
  };
}

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
  "- Never use an em dash, a semicolon, an ellipsis (...), or a dash/hyphen used to separate clauses " +
  '(e.g. not "I mean - it\'s fine"). A hyphen is only okay inside a single compound word like ' +
  '"one-on-one", never with spaces around it. Use a period, comma, or a word like "and" or "but" ' +
  "instead.\n" +
  '- Avoid AI-sounding phrasing: no "it\'s not just X, it\'s Y" constructions, no "dive into" / "delve ' +
  'into", no "leverage" / "robust" / "seamless" / "testament to" / "boasts", no stacked adjective ' +
  "triplets, no overly polished or formal sentence structure. Write the way a real person would " +
  "actually say or type it: plain, a little imperfect, natural rhythm.\n" +
  "- This text renders as plain words directly on screen, so any dialogue field (an opening line or " +
  "an in-character reply) must contain ONLY the literal words the person says out loud. Never include " +
  "stage directions, action descriptions, or narration of physical behavior, in asterisks, brackets, " +
  "parentheses, or otherwise (no \"*slouches in chair*\", no \"(sighs)\", no \"[pause]\"). If you want " +
  "to convey tone or body language, do it through the word choice and phrasing itself, not narration.";

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
    "describing the situation. The briefing must include at least one concrete, specific detail " +
    "(a number, date, or incident) grounding it, not just a general description.";

  const schema = {
    type: "object",
    properties: {
      briefing: {
        type: "string",
        description:
          "2-4 sentence briefing summarizing the situation for the user, including at least one " +
          "concrete, specific detail (a number, date, or incident) grounding it.",
      },
    },
    required: ["briefing"],
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
    criteria: lesson.criteria,
  };
}

// Stage 3 — Opening NPC Line
export async function generateOpeningLine(lesson, scenario) {
  // Most lessons need the NPC to stay neutral so the user is the one who
  // surfaces the specifics the criteria grade them on. But in a handful of
  // lessons (flagged with npcInitiatesWithKnownRequest) the NPC already made
  // a specific request before this conversation started — the request is
  // mutual common knowledge, not something the user needs to introduce, so
  // forcing the NPC to stay vague about it would be unrealistic (a real
  // person waiting on something they asked for would just ask about it).
  const openingRules = lesson.npcInitiatesWithKnownRequest
    ? "This conversation is happening because you already made a specific request that both people " +
      "know about (see the scenario briefing) — it's realistic, and fine, for your opening line to " +
      "reference or check in about that known request directly (e.g. \"hey, were you able to look at " +
      "that thing I asked about?\"). This doesn't hand the user a free pass on the graded skills below: " +
      "the request itself isn't something they need to introduce, their job is to respond to it " +
      "(decline, renegotiate, propose an alternative). Do not react to a response yet, and do not " +
      "sound like you already expect to be told no, this is just you raising or checking in on the " +
      "request.\n\n"
    : "The app is grading the user on specific skills they're supposed to practice during this " +
      "conversation (listed below). Your opening line must not hand the user a free pass on any of " +
      "them. Concretely, do not:\n" +
      "- Name the specific incident, report, client, number, or date from the scenario (e.g. don't say " +
      "\"this is about the Morrison report\", that's the specific detail the user is supposed to bring " +
      "up, not you).\n" +
      "- Explain your reasoning, give your excuse, or offer your side of the story.\n" +
      "- Presuppose you already know what this is about, or sound resigned, guilty, or like you're " +
      "bracing for bad news. Open neutrally, the way you'd start any ordinary check-in, for example a " +
      "plain greeting or a simple question like \"What did you want to talk about?\" Any wariness or " +
      "defensiveness from the persona notes should only show up in how you respond after the user " +
      "actually raises the topic, not in this first line. The user should be the one who introduces " +
      "every specific, not you.\n\n";

  const system =
    `You are roleplaying as ${formatCharacter(lesson)} in a workplace conversation training app. ` +
    "Stay fully in character. Do not break the fourth wall, do not reference criteria or grading, " +
    "and do not resolve the conversation yet, this is the opening line only.\n\n" +
    openingRules +
    WRITING_STYLE;

  const userMessage =
    `Scenario briefing: ${scenario.briefing}\n` +
    `Persona behavior notes: ${lesson.personaNotes}\n` +
    `Skills the user is being graded on this conversation: ${lesson.criteria.join(" | ")}\n\n` +
    (lesson.npcInitiatesWithKnownRequest
      ? "Generate a natural opening line where the NPC raises or checks in on the request they already " +
        "made (per the scenario briefing). It should not depend on anything the user has said yet, and " +
        "should not react to a decline/negotiation that hasn't happened yet."
      : "Generate a natural, neutral opening line for the NPC to start this conversation with the user. " +
        "It should not depend on anything the user has said yet, should not presuppose the topic or " +
        "sound guarded or resigned, and must not name the specific incident/detail above or explain " +
        "their own reasoning, those are what the graded skills above are meant to draw out of the user.");

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

  const demoBlock = lesson.demoExchange
    ? "Example of the tone and resistance level for this lesson's difficulty tier " +
      `(${lesson.difficultyLabel ?? "this tier"}) — match this LEVEL of pushback, not the literal ` +
      "wording or specifics, since the actual scenario will be different:\n" +
      `User: "${lesson.demoExchange.user}"\n` +
      `NPC: "${lesson.demoExchange.npc}"\n\n`
    : "";

  const system =
    `You are roleplaying as ${formatCharacter(lesson)} in a workplace conversation training app, and ` +
    "you also grade the user's latest response against fixed skill criteria. Stay fully in character " +
    "for npc_reply — never mention criteria, grading, or appropriateness in the dialogue itself. " +
    "Persona behavior notes: " +
    lesson.personaNotes +
    "\n\n" +
    demoBlock +
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
    "Respect and empathy grading (applies to the user's latest message only, independent of criteria, " +
    "appropriateness, and resolution — this never ends the conversation or blocks a criterion, it's a " +
    "separate coaching signal):\n" +
    '- "strong": genuinely warm or empathetic given the moment, e.g. acknowledges the NPC\'s feelings ' +
    "or situation skillfully, especially when the NPC has expressed hardship or vulnerability.\n" +
    '- "adequate": fine and businesslike. This is a perfectly reasonable grade for a low-stakes, ' +
    "logistics-only moment where no particular warmth is called for.\n" +
    '- "minimal": flat, perfunctory, or cold given the moment, e.g. brushing past something the NPC ' +
    "just expressed real hardship or vulnerability about without acknowledging it, even if the message " +
    "isn't rude enough to be a mild_flag.\n" +
    "Judge this relative to how emotionally loaded the moment is, not on an absolute scale.\n\n" +
    "Settled check (independent of criteria and appropriateness):\n" +
    "- Set conversation_settled to true only if the core issue has been explicitly resolved by both " +
    "sides, e.g. a concrete next step was agreed to and both people consider it settled, such that " +
    "another turn would just repeat the same agreement.\n" +
    "- Set it to false if there's still unresolved tension, open questions, or room for the " +
    "conversation to productively continue.\n\n" +
    WRITING_STYLE;

  const userMessage =
    `Scenario briefing: ${scenario.briefing}\n\n` +
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
      respect_and_empathy: {
        type: "string",
        enum: ["minimal", "adequate", "strong"],
        description:
          "How warmly/empathetically the user's latest message came across given the moment, " +
          "independent of criteria and appropriateness.",
      },
      conversation_settled: {
        type: "boolean",
        description:
          "True only if the core issue has been explicitly resolved by both sides and another turn " +
          "would just repeat the same agreement. False if there's still unresolved tension or room to " +
          "continue productively.",
      },
    },
    required: ["npc_reply", "newly_met_criteria", "appropriateness", "respect_and_empathy", "conversation_settled"],
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
    } else if (result.conversation_settled && turnNumber >= 2) {
      // The conversation has clearly wound down before the turn cap — end
      // here with the same partial-credit outcome the cap would've reached,
      // instead of padding out turns that won't teach anything new. This
      // doesn't change what counts as "met", only when the loop stops.
      ended = true;
      resolution = "scaled";
    }
  }

  return {
    npc_reply: result.npc_reply,
    appropriateness: result.appropriateness,
    respect_and_empathy: result.respect_and_empathy,
    newly_met_criteria: result.newly_met_criteria,
    updated_met_criteria: updatedMetCriteria,
    deduction,
    ended,
    resolution,
  };
}

// Stage 6 — Feedback
export async function generateFeedback({
  lesson,
  scenario,
  history,
  metCriteria,
  deductionCount,
  resolution,
  empathyLevels = [],
}) {
  const checklist = lesson.criteria.map((criterion) => ({
    criterion,
    met: metCriteria.includes(criterion),
  }));

  const empathySummary = {
    strong: empathyLevels.filter((l) => l === "strong").length,
    adequate: empathyLevels.filter((l) => l === "adequate").length,
    minimal: empathyLevels.filter((l) => l === "minimal").length,
  };

  const system =
    "You write brief, constructive feedback for a workplace-conversation training app, based on a " +
    "completed practice conversation. Be specific and human, not generic. If the " +
    "user's respect/empathy grades were mixed or trended low (see below), work that into the feedback " +
    "specifically, not just the content checklist.\n\n" +
    "You also grade the conversation on three skills, judging the WHOLE transcript rather than any " +
    "single turn:\n" +
    "- clarity: did they say what they meant, plainly and with specifics, rather than hinting or " +
    "generalising?\n" +
    "- empathy: did they make room for how the other person saw it, proportionate to how loaded the " +
    "moment was?\n" +
    "- resolution: did the conversation land somewhere concrete, rather than trailing off or ending " +
    "on vague agreement?\n\n" +
    "For each, give a level and a note. The note is the part the user actually reads, so it must " +
    "point at something that happened in THIS conversation -- quote or paraphrase what they did or " +
    "failed to do. One sentence, max ~15 words. Never write a generic line that would fit any " +
    "conversation, and never name or restate the guide criteria.\n\n" +
    WRITING_STYLE;

  const userMessage =
    `Lesson: ${lesson.title}\n` +
    `Scenario briefing: ${scenario.briefing}\n\n` +
    `Conversation:\n${formatHistory(history)}\n\n` +
    `Criteria results:\n${checklist
      .map((c) => `- ${c.criterion}: ${c.met ? "met" : "not met"}`)
      .join("\n")}\n` +
    `Professionalism deductions: ${deductionCount}\n` +
    `Respect/empathy grades across the conversation, in order: ${empathyLevels.length ? empathyLevels.join(" | ") : "(none)"}\n` +
    `Overall resolution: ${resolution}\n\n` +
    "Write a 1-2 sentence feedback summary covering what went well and what to improve next time.";

  const skillProperty = (name, what) => ({
    type: "object",
    description: `How the conversation went on ${name}: ${what}`,
    properties: {
      level: {
        type: "string",
        enum: ["needs_work", "developing", "solid", "strong"],
        description: "Judged over the whole conversation, not a single turn.",
      },
      note: {
        type: "string",
        description:
          "One sentence, max ~15 words, pointing at something specific that happened in this " +
          "conversation. Not a restatement of the level or of the guide criteria.",
      },
    },
    required: ["level", "note"],
  });

  const schema = {
    type: "object",
    properties: {
      feedback_line: { type: "string", description: "1-2 sentence feedback summary." },
      skills: {
        type: "object",
        properties: {
          clarity: skillProperty("clarity", "saying what they meant, plainly and with specifics"),
          empathy: skillProperty("empathy", "making room for how the other person saw it"),
          resolution: skillProperty("resolution", "landing somewhere concrete"),
        },
        required: ["clarity", "empathy", "resolution"],
      },
    },
    required: ["feedback_line", "skills"],
  };

  const result = await structuredCall({
    system,
    messages: [{ role: "user", content: userMessage }],
    schema,
    toolName: "submit_feedback",
    // The response carries feedback_line plus three skill notes. 256 was the
    // budget from when it returned the line alone.
    maxTokens: 700,
  });

  return {
    checklist,
    deductionCount,
    empathySummary,
    resolution,
    skills: result.skills,
    feedbackLine: result.feedback_line,
  };
}

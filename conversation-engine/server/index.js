import "dotenv/config";
import express from "express";
import path from "node:path";
import { randomUUID } from "node:crypto";
import { fileURLToPath } from "node:url";
import { lessons, getLessonById } from "./lessons.js";
import { generateScenario, generateOpeningLine, runTurn, generateFeedback, generateCustomLesson } from "./engine.js";
import { transcribeWithWhisper, STT_MODES } from "./stt.js";
import { requireAuth, requireConversation, issueToken, verifyToken } from "./auth.js";
import { rateLimit } from "./ratelimit.js";
import { getState, spend, publicState, redeemJudgeCode } from "./energy.js";
import { verifyPro } from "./entitlement.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const app = express();
// Trust exactly one hop (the Apache reverse proxy this server always runs
// behind) so req.ip reads the real client address from X-Forwarded-For
// instead of Apache's own localhost connection -- needed for rateLimit's
// keyBy: "ip" to actually distinguish callers.
app.set("trust proxy", 1);
app.use(express.json());
app.use(express.static(path.join(__dirname, "..", "public")));

function requireConversationReason(req, lessonId) {
  const reason = verifyToken(req.get("X-Poise-Conversation"), req.poiseUser, lessonId);
  return reason ? `Conversation token ${reason}. Start the conversation again.` : null;
}

function lessonSummary(lesson) {
  const { id, unit, title, isCheckpoint, character } = lesson;
  return { id, unit, title, isCheckpoint, character };
}

// Loose but real bounds on a client-supplied custom lesson (see
// resolveLesson below) -- not a curriculum shape to enforce meaning, just
// enough to stop a malformed or hostile payload from riding along on every
// turn of a conversation it can otherwise run for as long as MAX_USER_TURNS
// allows, at this user's own energy cost.
const CUSTOM_LESSON_FIELD_LIMIT = 2000;
const CUSTOM_LESSON_MAX_CRITERIA = 6;

function isValidCustomLesson(lesson) {
  if (!lesson || typeof lesson !== "object") return false;
  if (typeof lesson.id !== "string" || !lesson.id) return false;
  if (typeof lesson.title !== "string" || lesson.title.length > CUSTOM_LESSON_FIELD_LIMIT) return false;
  if (typeof lesson.personaNotes !== "string" || lesson.personaNotes.length > CUSTOM_LESSON_FIELD_LIMIT) return false;
  if (
    !Array.isArray(lesson.criteria) ||
    lesson.criteria.length === 0 ||
    lesson.criteria.length > CUSTOM_LESSON_MAX_CRITERIA ||
    !lesson.criteria.every((c) => typeof c === "string" && c.length > 0 && c.length <= CUSTOM_LESSON_FIELD_LIMIT)
  ) {
    return false;
  }
  const character = lesson.character;
  if (!character || typeof character !== "object") return false;
  if (typeof character.name !== "string" || !character.name || character.name.length > 200) return false;
  if (typeof character.role !== "string" || !character.role || character.role.length > CUSTOM_LESSON_FIELD_LIMIT) return false;
  if (
    character.relationship != null &&
    (typeof character.relationship !== "string" || character.relationship.length > CUSTOM_LESSON_FIELD_LIMIT)
  ) {
    return false;
  }
  return true;
}

// Built-in lessons are looked up by id, same as always. A custom scenario
// (see /api/custom-scenario) isn't in that static list, so the client
// carries the full lesson object it was handed at generation time on every
// later call instead -- the server stays stateless either way, it just
// doesn't have anywhere else to keep a one-off lesson between requests.
function resolveLesson(req) {
  if (req.body.lessonId) return getLessonById(req.body.lessonId);
  return isValidCustomLesson(req.body.lesson) ? req.body.lesson : null;
}

app.get("/api/lessons", (req, res) => {
  res.json(lessons.map(lessonSummary));
});

// The lesson list above is public catalogue data. Everything below either
// costs a model call or reads a user's energy, and requires both headers.
app.use("/api", requireAuth);

// Read-only energy state, so the app can show the server's number on launch
// without having to start a conversation to find out.
app.get("/api/energy", async (req, res) => {
  try {
    const row = await getState(req.poiseUser, { verifyPro });
    res.json({ energy: publicState(row) });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// Redeems a Shipaton-judge code, granting the caller a large standing energy
// cap so they can play through every lesson (with repeats) in one sitting.
// See energy.js: redeemJudgeCode for the full mechanism. The code itself is
// a long random string, not something memorable, precisely because it's a
// guessing target -- judges get it handed to them directly, they never need
// to recall it. Rate-limited on two independent keys (X-Poise-User AND
// source IP) so rotating the client-supplied header alone can't reset the
// attempt counter; a few tries survive a mistyped paste, nowhere near enough
// to brute-force a long random string either way.
app.post(
  "/api/redeem",
  rateLimit("redeem", { limit: 5 }),
  rateLimit("redeem-ip", { limit: 5, keyBy: "ip" }),
  async (req, res) => {
    try {
      const { code } = req.body;
      if (typeof code !== "string" || !code) {
        return res.status(400).json({ error: "Missing code." });
      }
      const result = redeemJudgeCode(req.poiseUser, code);
      if (!result.ok) return res.status(400).json({ error: "Invalid code." });
      res.json({ energy: publicState(result.row) });
    } catch (err) {
      console.error(err);
      res.status(500).json({ error: err.message });
    }
  }
);

app.post("/api/scenario", rateLimit("scenario"), async (req, res) => {
  try {
    const lesson = getLessonById(req.body.lessonId);
    if (!lesson) return res.status(404).json({ error: "Unknown lessonId" });

    const scenario = await generateScenario(lesson);
    res.json({ lesson: lessonSummary(lesson), scenario });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

const CUSTOM_SCENARIO_PROMPT_LIMIT = 500;

// Builds a one-off lesson (title, character, goals, persona notes) and its
// first scenario from the user's own free-text description -- the entry
// point for Poise Pro's custom-scenario builder. Pro-gated server-side, not
// just in the app: the client is never trusted on entitlement, same
// reasoning as spend()'s verifyPro check below. Unlike /api/scenario, the
// resulting lesson isn't in the static list, so it's returned in full (see
// resolveLesson) for the client to carry through opening/turn/feedback.
app.post("/api/custom-scenario", rateLimit("scenario"), async (req, res) => {
  try {
    const prompt = typeof req.body.prompt === "string" ? req.body.prompt.trim() : "";
    if (!prompt) return res.status(400).json({ error: "Missing prompt" });
    if (prompt.length > CUSTOM_SCENARIO_PROMPT_LIMIT) {
      return res.status(400).json({ error: `Prompt must be ${CUSTOM_SCENARIO_PROMPT_LIMIT} characters or fewer.` });
    }
    if (!(await verifyPro(req.poiseUser))) {
      return res.status(403).json({ error: "Custom scenarios are a Poise Pro feature." });
    }

    const generated = await generateCustomLesson(prompt);
    const lesson = {
      id: `custom-${randomUUID()}`,
      unit: "Custom",
      title: generated.title,
      isCheckpoint: false,
      character: generated.character,
      criteria: generated.criteria,
      personaNotes: generated.personaNotes,
    };
    const scenario = { briefing: generated.briefing, criteria: generated.criteria };
    res.json({
      lesson: { ...lessonSummary(lesson), personaNotes: lesson.personaNotes, criteria: lesson.criteria },
      scenario,
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

app.post("/api/opening", rateLimit("opening"), async (req, res) => {
  try {
    const lesson = resolveLesson(req);
    if (!lesson) return res.status(404).json({ error: "Unknown or invalid lesson" });
    const { scenario } = req.body;

    const openingLine = await generateOpeningLine(lesson, scenario);
    res.json({ openingLine, character: lesson.character.name });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// Every turn is a real model call, win or lose a valid conversation token
// (only turn 1 also charges energy). Once a token is issued, turns 2+ are
// gated on nothing else, so a fast replay loop against a live token is free
// to hammer this endpoint -- rate limit it same as scenario/opening. The
// limit is higher than theirs because one lesson is up to MAX_USER_TURNS (5)
// calls here against one scenario/opening pair, not one.
app.post("/api/turn", rateLimit("turn", { limit: 50 }), async (req, res) => {
  try {
    const lesson = resolveLesson(req);
    if (!lesson) return res.status(404).json({ error: "Unknown or invalid lesson" });
    const { scenario, history, metCriteria, turnNumber, userResponse } = req.body;

    // Energy is charged when the conversation starts -- turn 1 -- because
    // that is the moment tokens begin to be spent, whether or not the user
    // sees it through. Later turns ride on the token issued here.
    let conversationToken;
    let energyRow;
    if (turnNumber === 1) {
      const charge = await spend(req.poiseUser, { verifyPro });
      energyRow = charge.row;
      if (!charge.ok) {
        return res.status(402).json({
          error: "Not enough energy to start a conversation.",
          energy: publicState(charge.row),
        });
      }
      conversationToken = issueToken(req.poiseUser, lesson.id);
    } else {
      const reason = requireConversationReason(req, lesson.id);
      if (reason) return res.status(401).json({ error: reason });
      energyRow = await getState(req.poiseUser, { verifyPro });
    }

    const result = await runTurn({
      lesson,
      scenario,
      history,
      metCriteria,
      turnNumber,
      userResponse,
    });

    res.json({
      ...result,
      character: lesson.character.name,
      energy: publicState(energyRow),
      ...(conversationToken ? { conversationToken } : {}),
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// Same real-model-call exposure as scenario/opening, gated only by a valid
// conversation token rather than a fresh energy charge -- add the same class
// of limit, with a bit of headroom over their default for a redone lesson.
app.post("/api/feedback", rateLimit("feedback", { limit: 15 }), requireConversation, async (req, res) => {
  try {
    const lesson = resolveLesson(req);
    if (!lesson) return res.status(404).json({ error: "Unknown or invalid lesson" });
    const { scenario, history, metCriteria, deductionCount, resolution, empathyLevels } = req.body;

    const feedback = await generateFeedback({
      lesson,
      scenario,
      history,
      metCriteria,
      deductionCount,
      resolution,
      empathyLevels,
    });

    const energyRow = await getState(req.poiseUser, { verifyPro });
    res.json({ ...feedback, energy: publicState(energyRow) });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

app.get("/api/stt-test/modes", (req, res) => {
  res.json(
    Object.fromEntries(Object.entries(STT_MODES).map(([key, { label }]) => [key, label]))
  );
});

// No shipping-app call site hits this -- it's the local whisper.cpp harness
// public/stt-test.js drives (see stt.js: on-device, no vendor API, no paid
// call). Still worth guarding: it accepts up to 25MB and spawns a whisper.cpp
// subprocess per request, so it gets the same scenario/opening-class limit as
// a resource-exhaustion guard rather than being left unguarded.
app.post("/api/stt-test", rateLimit("stt-test"), express.raw({ type: "audio/wav", limit: "25mb" }), async (req, res) => {
  try {
    if (!Buffer.isBuffer(req.body) || req.body.length === 0) {
      return res.status(400).json({ error: "Request body must be a WAV audio clip (Content-Type: audio/wav)" });
    }

    const mode = typeof req.query.mode === "string" ? req.query.mode : "default";
    const transcripts = await transcribeWithWhisper(req.body, mode);
    res.json(transcripts);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

const port = process.env.PORT || 3000;
app.listen(port, () => {
  console.log(`Conversation engine test site running at http://localhost:${port}`);
});

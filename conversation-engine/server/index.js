import "dotenv/config";
import express from "express";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { lessons, getLessonById } from "./lessons.js";
import { generateScenario, generateOpeningLine, runTurn, generateFeedback } from "./engine.js";
import { transcribeWithWhisper, STT_MODES } from "./stt.js";
import { requireAuth, requireConversation, issueToken, verifyToken } from "./auth.js";
import { rateLimit } from "./ratelimit.js";
import { getState, spend, publicState, redeemJudgeCode } from "./energy.js";
import { verifyPro } from "./entitlement.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const app = express();
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
// See energy.js: redeemJudgeCode for the full mechanism. The code is short
// and memorable by design (it's handed to judges), which makes it a guessing
// target -- so this gets a much tighter cap than the generation endpoints
// below: a few tries survive a fat-fingered code, nowhere near enough to
// brute-force one.
app.post("/api/redeem", rateLimit("redeem", { limit: 5 }), async (req, res) => {
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
});

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

app.post("/api/opening", rateLimit("opening"), async (req, res) => {
  try {
    const lesson = getLessonById(req.body.lessonId);
    if (!lesson) return res.status(404).json({ error: "Unknown lessonId" });
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
    const lesson = getLessonById(req.body.lessonId);
    if (!lesson) return res.status(404).json({ error: "Unknown lessonId" });
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
    const lesson = getLessonById(req.body.lessonId);
    if (!lesson) return res.status(404).json({ error: "Unknown lessonId" });
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

import "dotenv/config";
import express from "express";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { lessons, getLessonById } from "./lessons.js";
import { generateScenario, generateOpeningLine, runTurn, generateFeedback } from "./engine.js";
import { generateSpeech } from "./tts.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const app = express();
app.use(express.json());
app.use(express.static(path.join(__dirname, "..", "public")));

function lessonSummary(lesson) {
  const { id, unit, title, isCheckpoint, character } = lesson;
  return { id, unit, title, isCheckpoint, character };
}

app.get("/api/lessons", (req, res) => {
  res.json(lessons.map(lessonSummary));
});

app.post("/api/scenario", async (req, res) => {
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

app.post("/api/opening", async (req, res) => {
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

app.post("/api/turn", async (req, res) => {
  try {
    const lesson = getLessonById(req.body.lessonId);
    if (!lesson) return res.status(404).json({ error: "Unknown lessonId" });
    const { scenario, history, metCriteria, turnNumber, userResponse } = req.body;

    const result = await runTurn({
      lesson,
      scenario,
      history,
      metCriteria,
      turnNumber,
      userResponse,
    });

    res.json({ ...result, character: lesson.character.name });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

app.post("/api/feedback", async (req, res) => {
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

    res.json(feedback);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

app.post("/api/tts", async (req, res) => {
  try {
    const { text, character } = req.body;
    if (!text || !character) {
      return res.status(400).json({ error: "Both 'text' and 'character' are required" });
    }

    const audio = await generateSpeech(text, character);
    res.set("Content-Type", "audio/mpeg");
    res.send(audio);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

const port = process.env.PORT || 3000;
app.listen(port, () => {
  console.log(`Conversation engine test site running at http://localhost:${port}`);
});

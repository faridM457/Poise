const MAX_USER_TURNS = 5;

const state = {
  lessonId: null,
  lesson: null,
  scenario: null,
  history: [], // { role: "npc" | "user", text, character? }
  metCriteria: [],
  deductionCount: 0,
  empathyLevels: [], // "minimal" | "adequate" | "strong" per turn
  turnNumber: 0,
  ended: false,
};

const el = {
  lessonList: document.getElementById("lesson-list"),
  scenarioPanel: document.getElementById("scenario-panel"),
  scenarioContent: document.getElementById("scenario-content"),
  guidePanel: document.getElementById("guide-panel"),
  criteriaList: document.getElementById("criteria-list"),
  startBtn: document.getElementById("start-btn"),
  conversationPanel: document.getElementById("conversation-panel"),
  chatLog: document.getElementById("chat-log"),
  turnForm: document.getElementById("turn-form"),
  turnInput: document.getElementById("turn-input"),
  micBtn: document.getElementById("mic-btn"),
  turnCounter: document.getElementById("turn-counter"),
  feedbackPanel: document.getElementById("feedback-panel"),
  feedbackContent: document.getElementById("feedback-content"),
  resetBtn: document.getElementById("reset-btn"),
};

async function api(path, body) {
  const res = await fetch(path, {
    method: body ? "POST" : "GET",
    headers: body ? { "Content-Type": "application/json" } : undefined,
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({ error: res.statusText }));
    throw new Error(err.error || "Request failed");
  }
  return res.json();
}

function resetState() {
  state.lessonId = null;
  state.lesson = null;
  state.scenario = null;
  state.history = [];
  state.metCriteria = [];
  state.deductionCount = 0;
  state.empathyLevels = [];
  state.turnNumber = 0;
  state.ended = false;
}

async function loadLessons() {
  const lessons = await api("/api/lessons");
  el.lessonList.innerHTML = "";
  lessons.forEach((lesson) => {
    const btn = document.createElement("button");
    btn.className = "lesson-btn";
    btn.innerHTML = `
      <span class="lesson-unit">${lesson.unit}${lesson.isCheckpoint ? ' · <span class="lesson-checkpoint">Checkpoint</span>' : ""}</span>
      <strong>${lesson.title}</strong> — with ${lesson.character.name} (${lesson.character.role})
    `;
    btn.addEventListener("click", () => selectLesson(lesson.id));
    el.lessonList.appendChild(btn);
  });
}

async function selectLesson(lessonId) {
  resetState();
  hidePanel(el.conversationPanel);
  hidePanel(el.feedbackPanel);
  el.chatLog.innerHTML = "";
  el.turnInput.disabled = false;

  el.scenarioContent.innerHTML = "<p><em>Generating scenario…</em></p>";
  showPanel(el.scenarioPanel);

  const { lesson, scenario } = await api("/api/scenario", { lessonId });
  state.lessonId = lessonId;
  state.lesson = lesson;
  state.scenario = scenario;

  el.scenarioContent.innerHTML = `
    <p><strong>${lesson.title}</strong> (${lesson.unit})</p>
    <p>${scenario.briefing}</p>
  `;

  if (lesson.isCheckpoint) {
    el.guidePanel.classList.add("hidden");
    const note = document.createElement("p");
    note.innerHTML = "<em>Guide hidden — checkpoint lesson.</em>";
    el.scenarioContent.appendChild(note);
  } else {
    el.guidePanel.classList.remove("hidden");
    el.criteriaList.innerHTML = "";
    scenario.criteria.forEach((criterion) => {
      const li = document.createElement("li");
      li.textContent = criterion;
      li.dataset.criterion = criterion;
      el.criteriaList.appendChild(li);
    });
  }
}

el.startBtn.addEventListener("click", startConversation);

async function startConversation() {
  el.startBtn.disabled = true;
  showPanel(el.conversationPanel);
  el.chatLog.innerHTML = "<p><em>Loading opening line…</em></p>";

  const { openingLine, character } = await api("/api/opening", {
    lessonId: state.lessonId,
    scenario: state.scenario,
  });

  el.chatLog.innerHTML = "";
  state.history.push({ role: "npc", text: openingLine, character });
  renderChatLog();
  updateTurnCounter();
  el.startBtn.disabled = false;
}

el.turnForm.addEventListener("submit", async (e) => {
  e.preventDefault();
  const text = el.turnInput.value.trim();
  if (!text || state.ended) return;

  el.turnInput.value = "";
  el.turnInput.disabled = true;

  state.history.push({ role: "user", text });
  renderChatLog();
  state.turnNumber += 1;

  try {
    const result = await api("/api/turn", {
      lessonId: state.lessonId,
      scenario: state.scenario,
      history: state.history.slice(0, -1), // history before this user message
      metCriteria: state.metCriteria,
      turnNumber: state.turnNumber,
      userResponse: text,
    });

    state.history.push({
      role: "npc",
      text: result.npc_reply,
      character: result.character,
      flag: result.appropriateness,
    });
    state.metCriteria = result.updated_met_criteria;
    if (result.deduction) state.deductionCount += 1;
    if (result.respect_and_empathy) state.empathyLevels.push(result.respect_and_empathy);

    renderChatLog();
    updateCriteriaDisplay();
    updateTurnCounter();

    if (result.ended) {
      state.ended = true;
      await finalize(result.resolution);
    } else {
      el.turnInput.disabled = false;
      el.turnInput.focus();
    }
  } catch (err) {
    console.error(err);
    alert(`Error: ${err.message}`);
    el.turnInput.disabled = false;
  }
});

// Speech-to-text for the turn input, using the browser's built-in Web Speech
// API. Purely additive: it only fills el.turnInput.value so the user can
// review (and edit) the transcript before hitting the existing Send button —
// it never auto-submits. This also makes it easy to check whether the
// browser's recognizer keeps filler words ("um", "uh") in the transcript.
const SpeechRecognitionCtor = window.SpeechRecognition || window.webkitSpeechRecognition;
let recognition = null;
let isListening = false;

if (!SpeechRecognitionCtor) {
  // Unsupported browser: hide the mic button instead of wiring up handlers.
  if (el.micBtn) el.micBtn.classList.add("hidden");
} else {
  recognition = new SpeechRecognitionCtor();
  recognition.continuous = false;
  recognition.interimResults = false;
  recognition.lang = "en-US";

  recognition.addEventListener("result", (e) => {
    const transcript = e.results[0][0].transcript;
    el.turnInput.value = transcript;
    el.turnInput.focus();
  });

  recognition.addEventListener("error", (e) => {
    console.error("Speech recognition error", e);
    alert(`Speech recognition error: ${e.error || "unknown error"}`);
  });

  recognition.addEventListener("end", () => {
    isListening = false;
    el.micBtn.classList.remove("listening");
    el.micBtn.textContent = "🎤";
  });

  el.micBtn.addEventListener("click", () => {
    if (isListening) return; // prevent double-starts
    try {
      recognition.start();
      isListening = true;
      el.micBtn.classList.add("listening");
      el.micBtn.textContent = "🔴";
    } catch (err) {
      console.error(err);
      alert(`Couldn't start speech recognition: ${err.message}`);
      isListening = false;
      el.micBtn.classList.remove("listening");
      el.micBtn.textContent = "🎤";
    }
  });
}

async function finalize(resolution) {
  el.feedbackContent.innerHTML = "<p><em>Generating feedback…</em></p>";
  showPanel(el.feedbackPanel);

  const feedback = await api("/api/feedback", {
    lessonId: state.lessonId,
    scenario: state.scenario,
    history: state.history,
    metCriteria: state.metCriteria,
    deductionCount: state.deductionCount,
    empathyLevels: state.empathyLevels,
    resolution,
  });

  const checklistHtml = feedback.checklist
    .map(
      (item) =>
        `<div class="checklist-item"><span class="${item.met ? "met" : "unmet"}">${item.met ? "✓" : "✗"}</span> ${item.criterion}</div>`
    )
    .join("");

  el.feedbackContent.innerHTML = `
    <span class="resolution-badge resolution-${resolution}">${resolution.toUpperCase()}</span>
    <h3>Content checklist</h3>
    ${checklistHtml}
    <h3>Professionalism deductions</h3>
    <p>${feedback.deductionCount} mild flag(s) recorded during this conversation.</p>
    <h3>Empathy and respect</h3>
    <p>${feedback.empathySummary.strong} strong, ${feedback.empathySummary.adequate} adequate, ${feedback.empathySummary.minimal} minimal (across ${
      feedback.empathySummary.strong + feedback.empathySummary.adequate + feedback.empathySummary.minimal
    } graded turns).</p>
    <h3>Delivery score</h3>
    <p><em>Not part of this milestone.</em></p>
    <h3>Feedback</h3>
    <p>${feedback.feedbackLine}</p>
  `;
}

el.resetBtn.addEventListener("click", () => {
  if (!state.lessonId) return;
  selectLesson(state.lessonId);
  hidePanel(el.feedbackPanel);
});

function renderChatLog() {
  el.chatLog.innerHTML = "";
  state.history.forEach((turn) => {
    const div = document.createElement("div");
    div.className = `chat-msg ${turn.role}`;
    if (turn.flag === "mild_flag") div.classList.add("flag-mild");
    if (turn.flag === "severe_flag") div.classList.add("flag-severe");
    const speaker = turn.role === "npc" ? turn.character || "NPC" : "You";
    div.innerHTML = `<span class="speaker">${speaker}</span>${turn.text}`;
    el.chatLog.appendChild(div);
  });
  el.chatLog.scrollTop = el.chatLog.scrollHeight;
}

function updateCriteriaDisplay() {
  if (state.lesson.isCheckpoint) return;
  [...el.criteriaList.children].forEach((li) => {
    li.classList.toggle("criterion-met", state.metCriteria.includes(li.dataset.criterion));
  });
}

function updateTurnCounter() {
  el.turnCounter.textContent = `Turn ${state.turnNumber} of ${MAX_USER_TURNS} · ${state.metCriteria.length}/${state.scenario.criteria.length} criteria met · ${state.deductionCount} deduction(s)`;
}

function showPanel(panel) {
  panel.classList.remove("hidden");
}

function hidePanel(panel) {
  panel.classList.add("hidden");
}

loadLessons();

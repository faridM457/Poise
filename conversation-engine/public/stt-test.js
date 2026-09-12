// Standalone test harness: record real speech in the browser, transcribe it
// locally with whisper.cpp (tiny.en and base.en side by side), and check
// whether natural filler words ("um", "uh") survive. Answers a question the
// existing turn-input mic button (public/app.js, browser SpeechRecognition)
// couldn't: that API strips fillers. This is purely additive -- it doesn't
// touch app.js or the turn-input mic flow at all.
import { decodeAudioBlob } from "./audio-analysis.js";

const el = {
  recordBtn: document.getElementById("stt-record-btn"),
  status: document.getElementById("stt-test-status"),
  tiny: document.getElementById("stt-result-tiny"),
  base: document.getElementById("stt-result-base"),
  modeSelect: document.getElementById("stt-mode-select"),
};

if (!el.recordBtn) {
  // Section not present on this page; nothing to wire up.
} else {
  let mediaRecorder = null;
  let chunks = [];
  let isRecording = false;

  fetch("/api/stt-test/modes")
    .then((res) => res.json())
    .then((modes) => {
      el.modeSelect.innerHTML = "";
      for (const [key, label] of Object.entries(modes)) {
        const opt = document.createElement("option");
        opt.value = key;
        opt.textContent = label;
        el.modeSelect.appendChild(opt);
      }
    })
    .catch((err) => console.error("Couldn't load STT modes", err));

  el.recordBtn.addEventListener("click", async () => {
    if (isRecording) {
      mediaRecorder.stop();
      return;
    }

    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      chunks = [];
      mediaRecorder = new MediaRecorder(stream);

      mediaRecorder.addEventListener("dataavailable", (e) => {
        if (e.data.size > 0) chunks.push(e.data);
      });

      mediaRecorder.addEventListener("stop", async () => {
        stream.getTracks().forEach((track) => track.stop());
        isRecording = false;
        el.recordBtn.textContent = "🎤 Record";
        el.recordBtn.classList.remove("listening");
        await transcribe(new Blob(chunks, { type: mediaRecorder.mimeType }));
      });

      mediaRecorder.start();
      isRecording = true;
      el.recordBtn.textContent = "⏹ Stop";
      el.recordBtn.classList.add("listening");
      el.status.textContent = "Recording… speak naturally, then click Stop.";
    } catch (err) {
      console.error(err);
      el.status.textContent = `Couldn't access microphone: ${err.message}`;
    }
  });

  async function transcribe(blob) {
    el.status.textContent = "Decoding and resampling audio…";
    el.tiny.textContent = "";
    el.base.textContent = "";

    try {
      const { samples, sampleRate } = await decodeAudioBlob(blob);
      const resampled = resampleLinear(samples, sampleRate, 16000);
      const wavBlob = encodeWav16(resampled, 16000);

      const mode = el.modeSelect.value || "default";
      el.status.textContent = `Transcribing with whisper.cpp (tiny.en and base.en, mode: ${mode})…`;

      const res = await fetch(`/api/stt-test?mode=${encodeURIComponent(mode)}`, {
        method: "POST",
        headers: { "Content-Type": "audio/wav" },
        body: wavBlob,
      });
      if (!res.ok) {
        const err = await res.json().catch(() => ({ error: res.statusText }));
        throw new Error(err.error || "Request failed");
      }

      const { tiny, base } = await res.json();
      el.tiny.textContent = tiny || "(empty transcript)";
      el.base.textContent = base || "(empty transcript)";
      el.status.textContent = "Done. Compare both transcripts for retained filler words.";
    } catch (err) {
      console.error(err);
      el.status.textContent = `Error: ${err.message}`;
    }
  }
}

function resampleLinear(samples, fromRate, toRate) {
  if (fromRate === toRate) return samples;
  const ratio = fromRate / toRate;
  const outLength = Math.round(samples.length / ratio);
  const out = new Float32Array(outLength);
  for (let i = 0; i < outLength; i++) {
    const srcPos = i * ratio;
    const srcIndex = Math.floor(srcPos);
    const frac = srcPos - srcIndex;
    const a = samples[srcIndex] || 0;
    const b = samples[srcIndex + 1] || a;
    out[i] = a + (b - a) * frac;
  }
  return out;
}

function encodeWav16(samples, sampleRate) {
  const dataSize = samples.length * 2;
  const buffer = new ArrayBuffer(44 + dataSize);
  const view = new DataView(buffer);

  writeString(view, 0, "RIFF");
  view.setUint32(4, 36 + dataSize, true);
  writeString(view, 8, "WAVE");
  writeString(view, 12, "fmt ");
  view.setUint32(16, 16, true); // fmt chunk size
  view.setUint16(20, 1, true); // PCM
  view.setUint16(22, 1, true); // mono
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, sampleRate * 2, true); // byte rate
  view.setUint16(32, 2, true); // block align
  view.setUint16(34, 16, true); // bits per sample
  writeString(view, 36, "data");
  view.setUint32(40, dataSize, true);

  let offset = 44;
  for (let i = 0; i < samples.length; i++, offset += 2) {
    const clamped = Math.max(-1, Math.min(1, samples[i]));
    view.setInt16(offset, clamped < 0 ? clamped * 0x8000 : clamped * 0x7fff, true);
  }

  return new Blob([buffer], { type: "audio/wav" });
}

function writeString(view, offset, str) {
  for (let i = 0; i < str.length; i++) view.setUint8(offset + i, str.charCodeAt(i));
}

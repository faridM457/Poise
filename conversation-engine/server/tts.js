// NPC text-to-speech via Deepgram Aura-2 (managed API). Chosen over the
// earlier self-hosted OmniVoice-on-Modal approach for dev/testing and near-
// term production: no cold starts, simple flat per-character billing, no
// infrastructure to run. See tts-modal/ for the parked self-hosting path,
// worth revisiting only once real usage volume justifies it (see the
// cost math in project notes: an always-warm self-hosted GPU only beats
// Deepgram's metered rate at very high sustained volume).
// All American English (en-us) -- verified against Deepgram's docs, which
// only flag a handful of voices as non-American (draco and pandora are
// en-gb, hyperion and theia are en-au, amalthea is en-ph); everything else,
// including all 4 below, defaults to en-us.
const VOICE_MODELS = {
  marcus: "aura-2-mars-en", // masculine, smooth, patient, trustworthy, baritone
  priya: "aura-2-athena-en", // feminine, calm, smooth, professional
  dana: "aura-2-phoebe-en", // feminine, energetic, warm, casual
  alex: "aura-2-apollo-en", // masculine, confident, comfortable, casual
};
const VOICE_KEYS = Object.keys(VOICE_MODELS);

function mapCharacterToVoice(characterName) {
  const name = (characterName || "").toLowerCase();
  if (VOICE_MODELS[name]) return name;

  let hash = 0;
  for (const char of name) hash = (hash * 31 + char.charCodeAt(0)) >>> 0;
  return VOICE_KEYS[hash % VOICE_KEYS.length];
}

export async function generateSpeech(text, characterName) {
  const apiKey = process.env.DEEPGRAM_API_KEY;
  if (!apiKey) {
    throw new Error("DEEPGRAM_API_KEY is not set. Add it to .env (sign up at deepgram.com for a free-credit key).");
  }

  const voice = mapCharacterToVoice(characterName);
  const model = VOICE_MODELS[voice];

  const res = await fetch(`https://api.deepgram.com/v1/speak?model=${model}&encoding=mp3`, {
    method: "POST",
    headers: {
      Authorization: `Token ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ text }),
  });

  if (!res.ok) {
    const detail = await res.text().catch(() => res.statusText);
    throw new Error(`Deepgram TTS failed (${res.status}): ${detail}`);
  }

  return Buffer.from(await res.arrayBuffer());
}

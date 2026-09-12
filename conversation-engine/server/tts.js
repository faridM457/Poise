// Calls the self-hosted OmniVoice endpoint on Modal (see tts-modal/app.py).
// Only 4 designed voices exist right now (see DESIGNED_VOICES in that file),
// but the curriculum has many more character names, so any character name
// is deterministically mapped onto one of the 4 -- same character always
// gets the same voice within a run, without needing an exact name match.
const VOICE_KEYS = ["marcus", "priya", "dana", "alex"];

function mapCharacterToVoice(characterName) {
  const name = (characterName || "").toLowerCase();
  const exact = VOICE_KEYS.find((key) => name === key);
  if (exact) return exact;

  let hash = 0;
  for (const char of name) hash = (hash * 31 + char.charCodeAt(0)) >>> 0;
  return VOICE_KEYS[hash % VOICE_KEYS.length];
}

export async function generateSpeech(text, characterName) {
  const endpoint = process.env.TTS_ENDPOINT_URL;
  if (!endpoint) {
    throw new Error("TTS_ENDPOINT_URL is not set. Deploy tts-modal/app.py and add the URL to .env.");
  }

  const voice = mapCharacterToVoice(characterName);
  const res = await fetch(endpoint, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ text, voice }),
  });

  if (!res.ok) {
    const detail = await res.text().catch(() => res.statusText);
    throw new Error(`TTS endpoint failed (${res.status}): ${detail}`);
  }

  return Buffer.from(await res.arrayBuffer());
}

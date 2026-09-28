import test from 'node:test';
import assert from 'node:assert/strict';
import { lexicalWords, parseWhisperJSON } from '../src/transcript.js';

const token = (text, from, to) => ({ text, offsets: { from, to } });
test('groups subword tokens and excludes punctuation and special tokens', () => {
  const result = parseWhisperJSON({ transcription: [{
    text: ' Um, understanding matters.', tokens: [
      { text: '[_BEG_]' }, token(' Um', 100, 200), token(',', 200, 210),
      token(' under', 300, 500), token('standing', 500, 800), token(' matters', 900, 1200), token('.', 1200, 1210),
    ],
  }] }, 2);
  assert.deepEqual(result.words.map((w) => w.text), ['um', 'understanding', 'matters']);
  assert.deepEqual(result.words[1], { text: 'understanding', start: 0.3, end: 0.8 });
  assert.equal(result.timingsValid, true);
});

test('single-word segments support timing fallback but multiword segments do not', () => {
  const single = parseWhisperJSON({ transcription: [{ text: 'Hello.', offsets: { from: 200, to: 600 } }] }, 1);
  assert.equal(single.words[0].start, 0.2);
  const many = parseWhisperJSON({ transcription: [{ text: 'Hello there.', offsets: { from: 200, to: 600 } }] }, 1);
  assert.equal(many.timingsValid, false);
  assert.equal(many.words[0].start, null);
});

test('invalid, overlapping or out-of-bounds timing does not become evidence', () => {
  for (const offsets of [{ from: -10, to: 100 }, { from: 0, to: 3000 }, { from: 100, to: 100 }]) {
    assert.equal(parseWhisperJSON({ transcription: [{ text: 'um', offsets }] }, 1).timingsValid, false);
  }
  const result = parseWhisperJSON({ transcription: [
    { text: 'Hello', offsets: { from: 100, to: 800 } },
    { text: 'there', offsets: { from: 700, to: 900 } },
  ] }, 1);
  assert.equal(result.timingsValid, false);
  assert.ok(result.words.every((w) => w.start === null));
});

test('one token spanning two words cannot provide exact word boundaries', () => {
  const result = parseWhisperJSON({ transcription: [{ text: 'I agree', tokens: [token('I agree', 0, 900)] }] }, 1);
  assert.equal(result.timingsValid, false);
});

test('English lexical count preserves repetitions and contractions', () => {
  assert.deepEqual(lexicalWords("Um, I I don't think so. Uh!"), ['um', 'i', 'i', "don't", 'think', 'so', 'uh']);
  assert.throws(() => parseWhisperJSON({}, 1), /transcription/);
});

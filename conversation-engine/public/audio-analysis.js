// Client-side delivery analysis: pauses/silence and pitch, computed directly
// from the raw microphone buffer via the Web Audio API. No server call, no
// vendor -- this runs entirely in the browser, alongside SpeechRecognition
// (which handles the transcript/pace/filler-word side separately).
//
// SKETCH / DRAFT: this hasn't been wired into the recording flow yet, and
// the thresholds below (SILENCE_RMS_THRESHOLD, MIN_PAUSE_MS) are starting
// guesses, not tuned against real speech. Treat every number here as a
// first guess to validate against real recordings, not a finished constant.

/**
 * Decodes a recorded audio Blob into raw PCM samples we can analyze.
 * @param {Blob} blob - audio captured via MediaRecorder
 * @returns {Promise<{samples: Float32Array, sampleRate: number}>}
 */
export async function decodeAudioBlob(blob) {
  const arrayBuffer = await blob.arrayBuffer();
  const audioCtx = new (window.AudioContext || window.webkitAudioContext)();
  const audioBuffer = await audioCtx.decodeAudioData(arrayBuffer);
  // Mono is enough for delivery analysis; average channels if stereo.
  const channelData = audioBuffer.numberOfChannels > 1
    ? averageChannels(audioBuffer)
    : audioBuffer.getChannelData(0);
  await audioCtx.close();
  return { samples: channelData, sampleRate: audioBuffer.sampleRate };
}

function averageChannels(audioBuffer) {
  const length = audioBuffer.length;
  const out = new Float32Array(length);
  for (let ch = 0; ch < audioBuffer.numberOfChannels; ch++) {
    const data = audioBuffer.getChannelData(ch);
    for (let i = 0; i < length; i++) out[i] += data[i] / audioBuffer.numberOfChannels;
  }
  return out;
}

const SILENCE_RMS_THRESHOLD = 0.02; // guess: below this RMS amplitude counts as silence
const FRAME_MS = 20; // analysis frame size
const MIN_PAUSE_MS = 300; // ignore gaps shorter than this (natural word gaps, not real pauses)

/**
 * Finds pauses (stretches of near-silence) in the recording.
 * @returns {{pauses: {startMs: number, durationMs: number}[], totalPauseMs: number, longestPauseMs: number}}
 */
export function detectPauses(samples, sampleRate) {
  const frameSize = Math.round((FRAME_MS / 1000) * sampleRate);
  const frameCount = Math.floor(samples.length / frameSize);

  const isSilent = new Array(frameCount);
  for (let f = 0; f < frameCount; f++) {
    let sumSquares = 0;
    const start = f * frameSize;
    for (let i = 0; i < frameSize; i++) {
      const s = samples[start + i];
      sumSquares += s * s;
    }
    const rms = Math.sqrt(sumSquares / frameSize);
    isSilent[f] = rms < SILENCE_RMS_THRESHOLD;
  }

  const pauses = [];
  let runStart = null;
  for (let f = 0; f <= frameCount; f++) {
    const silent = f < frameCount && isSilent[f];
    if (silent && runStart === null) {
      runStart = f;
    } else if (!silent && runStart !== null) {
      const durationMs = (f - runStart) * FRAME_MS;
      if (durationMs >= MIN_PAUSE_MS) {
        pauses.push({ startMs: runStart * FRAME_MS, durationMs });
      }
      runStart = null;
    }
  }

  const totalPauseMs = pauses.reduce((sum, p) => sum + p.durationMs, 0);
  const longestPauseMs = pauses.reduce((max, p) => Math.max(max, p.durationMs), 0);
  return { pauses, totalPauseMs, longestPauseMs };
}

const PITCH_FRAME_MS = 40;
const MIN_PITCH_HZ = 75; // roughly the low end of human speech
const MAX_PITCH_HZ = 400; // roughly the high end of human speech

/**
 * Rough pitch-over-time estimate via autocorrelation, frame by frame.
 * Returns null for frames judged too quiet/unvoiced to estimate reliably.
 * @returns {(number|null)[]} one pitch estimate (Hz) per frame, in order
 */
export function estimatePitchTrack(samples, sampleRate) {
  const frameSize = Math.round((PITCH_FRAME_MS / 1000) * sampleRate);
  const frameCount = Math.floor(samples.length / frameSize);
  const minLag = Math.floor(sampleRate / MAX_PITCH_HZ);
  const maxLag = Math.floor(sampleRate / MIN_PITCH_HZ);

  const pitches = [];
  for (let f = 0; f < frameCount; f++) {
    const start = f * frameSize;
    const frame = samples.subarray(start, start + frameSize);

    let energy = 0;
    for (let i = 0; i < frame.length; i++) energy += frame[i] * frame[i];
    if (Math.sqrt(energy / frame.length) < SILENCE_RMS_THRESHOLD) {
      pitches.push(null); // too quiet to trust a pitch estimate
      continue;
    }

    pitches.push(autocorrelationPitch(frame, sampleRate, minLag, maxLag));
  }
  return pitches;
}

function autocorrelationPitch(frame, sampleRate, minLag, maxLag) {
  let bestLag = -1;
  let bestCorrelation = 0;

  for (let lag = minLag; lag <= maxLag && lag < frame.length; lag++) {
    let correlation = 0;
    for (let i = 0; i < frame.length - lag; i++) {
      correlation += frame[i] * frame[i + lag];
    }
    if (correlation > bestCorrelation) {
      bestCorrelation = correlation;
      bestLag = lag;
    }
  }

  return bestLag > 0 ? sampleRate / bestLag : null;
}

/**
 * Coarse "monotone vs. expressive" signal: standard deviation of the
 * non-null pitch estimates. Low = flatter/more monotone. This is a proxy,
 * not a calibrated score -- needs comparing against real flat vs.
 * expressive recordings before trusting it for a user-facing label.
 */
export function pitchVariance(pitchTrack) {
  const voiced = pitchTrack.filter((p) => p !== null);
  if (voiced.length < 2) return null;

  const mean = voiced.reduce((sum, p) => sum + p, 0) / voiced.length;
  const variance = voiced.reduce((sum, p) => sum + (p - mean) ** 2, 0) / voiced.length;
  return { meanHz: mean, stdDevHz: Math.sqrt(variance), voicedFrameCount: voiced.length };
}

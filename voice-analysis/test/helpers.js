import wavefile from 'wavefile';
const { WaveFile } = wavefile;

export function signal(seconds = 15, regions = [{ start: 1, end: 6 }, { start: 7, end: 14 }], { hz = 220, amplitude = 0.2 } = {}) {
  const samples = new Float32Array(Math.round(seconds * 16000));
  for (const region of regions) {
    for (let i = Math.round(region.start * 16000); i < Math.min(samples.length, Math.round(region.end * 16000)); i++) {
      const frequency = typeof hz === 'function' ? hz(i / 16000) : hz;
      samples[i] = amplitude * Math.sin(2 * Math.PI * frequency * i / 16000);
    }
  }
  return samples;
}

export function wavBytes(samples) {
  const wav = new WaveFile();
  wav.fromScratch(1, 16000, '16', Int16Array.from(samples, (x) => Math.round(Math.max(-1, Math.min(0.9999, x)) * 32767)));
  return wav.toBuffer();
}

export function transcript(text) {
  return {
    status: 'available', text, timingsValid: false,
    words: text.toLowerCase().split(/\s+/).filter(Boolean).map((text) => ({ text, start: null, end: null })),
    source: 'test-fixture', warnings: [],
  };
}

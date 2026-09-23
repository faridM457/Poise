import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { build } from 'esbuild';
import { fileURLToPath } from 'node:url';

test('Shipping device bundle matches current source and has no external runtime imports', async () => {
  const root = fileURLToPath(new URL('../', import.meta.url));
  const result = await build({ absWorkingDir: root, entryPoints: ['src/device-entry.js'], bundle: true,
    platform: 'neutral', format: 'iife', globalName: 'PoiseVoice', target: 'safari18', mainFields: ['module', 'main'],
    outfile: 'apple/Resources/voice-analysis.js', metafile: true, write: false });
  assert.equal(result.outputFiles[0].text, await readFile(new URL('../apple/Resources/voice-analysis.js', import.meta.url), 'utf8'),
    'Run npm run build:device after changing the shared analysis source');
  for (const output of Object.values(result.metafile.outputs)) assert.deepEqual(output.imports, []);
  assert.equal(Object.keys(result.metafile.inputs).some((name) => name.startsWith('node:')), false);
});

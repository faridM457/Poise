import { build } from 'esbuild';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = fileURLToPath(new URL('../', import.meta.url));
const output = path.join(root, 'apple/Resources');
await mkdir(output, { recursive: true });
const result = await build({
  absWorkingDir: root, entryPoints: ['src/device-entry.js'], bundle: true, platform: 'neutral',
  format: 'iife', globalName: 'PoiseVoice', target: 'safari18', mainFields: ['module', 'main'],
  outfile: path.join(output, 'voice-analysis.js'), metafile: true,
});
// Neutral bundling rejects Node built-ins; only the pure calculation graph ships.
if (Object.values(result.metafile.outputs).some((entry) => entry.imports.length)) {
  throw new Error('Device bundle must not have external imports');
}
const licenses = await Promise.all([['pitchy', 'LICENSE'], ['fft.js', 'README.md']].map(async ([name, file]) => {
  const source = await readFile(path.join(root, 'node_modules', name, file), 'utf8');
  const license = file === 'README.md' ? source.slice(source.indexOf('#### LICENSE')) : source;
  if (!license.includes('Permission is hereby granted')) throw new Error(`Missing license for ${name}`);
  return `${name}\n${license}`;
}));
await writeFile(path.join(output, 'ThirdPartyLicenses.txt'), licenses.join('\n\n'));

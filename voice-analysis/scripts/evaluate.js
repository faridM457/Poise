import { parseArgs } from 'node:util';
import { readFile } from 'node:fs/promises';
import { evaluateReport } from '../src/evaluation.js';

try {
  const { values } = parseArgs({ options: { report: { type: 'string' }, labels: { type: 'string' } } });
  if (!values.report || !values.labels) throw new Error('Usage: npm run evaluate -- --report report.json --labels labels.json');
  const [report, labels] = await Promise.all([values.report, values.labels].map(async (file) => JSON.parse(await readFile(file, 'utf8'))));
  process.stdout.write(`${JSON.stringify(evaluateReport(report, labels), null, 2)}\n`);
} catch (error) {
  process.stderr.write(`${error.message}\n`);
  process.exitCode = 2;
}

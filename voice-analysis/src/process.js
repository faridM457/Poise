import { spawn } from 'node:child_process';

export function runProcess(command, args, { timeoutMs = 180000, maxOutputBytes = 2 * 1024 * 1024, signal } = {}) {
  signal?.throwIfAborted();
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { shell: false, stdio: ['ignore', 'pipe', 'pipe'] });
    let stdout = '';
    let stderr = '';
    let bytes = 0;
    let failure;
    const stop = (error) => {
      failure ??= error;
      child.kill('SIGKILL');
    };
    const timer = setTimeout(() => stop(new Error(`Process timed out after ${timeoutMs}ms`)), timeoutMs);
    const abort = () => stop(signal.reason ?? new Error('Analysis aborted'));
    signal?.addEventListener('abort', abort, { once: true });
    const capture = (chunk, stream) => {
      bytes += chunk.length;
      if (bytes > maxOutputBytes) {
        stop(new Error('Process output exceeded safety limit'));
      } else if (stream === 'stdout') stdout += chunk.toString();
      else stderr += chunk.toString();
    };
    child.stdout.on('data', (chunk) => capture(chunk, 'stdout'));
    child.stderr.on('data', (chunk) => capture(chunk, 'stderr'));
    child.on('error', (error) => { failure ??= error; });
    child.on('close', (code) => {
      clearTimeout(timer);
      signal?.removeEventListener('abort', abort);
      if (failure) return reject(failure);
      if (code !== 0) return reject(new Error(`Process exited ${code}: ${stderr.trim().slice(-1000)}`));
      resolve({ stdout, stderr });
    });
    if (signal?.aborted) abort();
  });
}

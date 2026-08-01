// Minimal structured JSON logger so logs are machine-parseable (LOG_LEVEL gated).
const LEVELS = { debug: 10, info: 20, warn: 30, error: 40 };
const threshold = LEVELS[process.env.LOG_LEVEL || 'info'] ?? 20;

function emit(level, message, context = {}) {
  if (LEVELS[level] < threshold) return;
  process.stdout.write(JSON.stringify({
    ts: new Date().toISOString(),
    service: 'playwright-service',
    level,
    message,
    ...context,
  }) + '\n');
}

export const log = {
  debug: (m, c) => emit('debug', m, c),
  info: (m, c) => emit('info', m, c),
  warn: (m, c) => emit('warn', m, c),
  error: (m, c) => emit('error', m, c),
};

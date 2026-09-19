/*
 * Structured logging. One JSON object per line.
 *
 * The audit record is the "审计" third of AI-SEC-001's recommendation. What it
 * deliberately does **not** contain is equally important: no request bodies, no
 * message text, no keys, no tokens. A log that captured student questions would
 * turn a security feature into a privacy liability — the same mistake the app's
 * test report already flags on the client side.
 *
 * The output target is swappable so that "never logs content or keys" can be
 * asserted by a test rather than merely asserted in a comment. A guarantee
 * nobody can check is a guarantee that decays.
 */

const LEVEL_INFO = 'info';
const LEVEL_WARN = 'warn';
const LEVEL_ERROR = 'error';

function writeTo(stream, line) {
  stream.write(line);
}

const defaultTarget = {
  info(line) {
    writeTo(process.stdout, line);
  },
  warn(line) {
    writeTo(process.stderr, line);
  },
  error(line) {
    writeTo(process.stderr, line);
  },
};

let target = defaultTarget;

/** Redirects log output. Pass null to restore the defaults. */
export function setLogTarget(next) {
  target = next || defaultTarget;
}

export function resetLogTarget() {
  target = defaultTarget;
}

export function buildRecord(level, message, fields) {
  const record = { level, time: new Date().toISOString(), message };
  if (fields) {
    for (const key of Object.keys(fields)) {
      if (fields[key] !== undefined) {
        record[key] = fields[key];
      }
    }
  }
  return record;
}

function emit(level, message, fields) {
  target[level](`${JSON.stringify(buildRecord(level, message, fields))}\n`);
}

export const logger = {
  info(message, fields) {
    emit(LEVEL_INFO, message, fields);
  },
  warn(message, fields) {
    emit(LEVEL_WARN, message, fields);
  },
  error(message, fields) {
    emit(LEVEL_ERROR, message, fields);
  },
};

/**
 * Per-request audit line, written once the response is finished.
 *
 * `upstreamStatus` (added by the handlers) is the field that actually explains
 * a failure: a 502 from us plus a 402 from upstream says "the account is out of
 * balance", while a bare 502 says nothing.
 */
export function audit(fields) {
  emit(LEVEL_INFO, 'request', fields);
}

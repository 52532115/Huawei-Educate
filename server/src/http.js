/*
 * Minimal HTTP plumbing.
 *
 * Node's built-in server hands us a raw byte stream, so every response is
 * written out explicitly instead of through a framework. That keeps this
 * package dependency-free: nothing here needs to be installed, audited or
 * kept up to date, which matters for a component that is the only thing
 * holding vendor credentials.
 */

/** Raised by the body readers; the router turns it into that status. */
export class BodyError extends Error {
  constructor(status, code, message) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

function byteLength(text) {
  return Buffer.byteLength(text, 'utf8');
}

export function sendJson(res, status, payload, extraHeaders = {}) {
  const body = JSON.stringify(payload);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': byteLength(body),
    'Cache-Control': 'no-store',
    ...extraHeaders,
  });
  res.end(body);
}

/**
 * Writes a structured error.
 *
 * `extras.headers` adds response headers; `extras.details` merges extra fields
 * into the error object. Keeping the two apart matters: an upstream status
 * belongs in the body where the client can read it, not in a header.
 */
export function sendError(res, status, code, message, extras = {}) {
  const error = { code, message };
  if (extras.details) {
    for (const key of Object.keys(extras.details)) {
      if (extras.details[key] !== undefined) {
        error[key] = extras.details[key];
      }
    }
  }
  sendJson(res, status, { error }, extras.headers || {});
}

/**
 * Reads and parses a JSON request body.
 *
 * An oversized body is drained before reporting rather than abandoned
 * mid-stream: answering 413 while the client is still uploading leaves the
 * socket in a state where the client may never see the response at all.
 */
export async function readJsonBody(req, maxBytes) {
  const chunks = [];
  let size = 0;
  let overflowed = false;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > maxBytes) {
      overflowed = true;
      continue;
    }
    chunks.push(chunk);
  }
  if (overflowed) {
    throw new BodyError(413, 'body_too_large', `请求体超过 ${maxBytes} 字节上限`);
  }
  if (chunks.length === 0) {
    return {};
  }
  const text = Buffer.concat(chunks).toString('utf8');
  if (text.trim().length === 0) {
    return {};
  }
  try {
    return JSON.parse(text);
  } catch (e) {
    throw new BodyError(400, 'invalid_json', '请求体不是合法 JSON');
  }
}

/**
 * Writes one chunk, waiting for `drain` when the socket buffer is full.
 *
 * Resolves false when the response went away mid-write, which is the caller's
 * signal to stop pulling from the upstream — a client that hung up should not
 * keep costing us tokens.
 */
export function writeChunk(res, buffer) {
  if (res.writableEnded || res.destroyed) {
    return Promise.resolve(false);
  }
  let flushed = false;
  try {
    flushed = res.write(buffer);
  } catch (e) {
    // The socket can vanish between the check above and the write.
    return Promise.resolve(false);
  }
  if (flushed) {
    return Promise.resolve(true);
  }
  return new Promise((resolve) => {
    const onDrain = () => {
      res.removeListener('close', onClose);
      resolve(true);
    };
    const onClose = () => {
      res.removeListener('drain', onDrain);
      resolve(false);
    };
    res.once('drain', onDrain);
    res.once('close', onClose);
  });
}

/** Best-effort client identity, used for rate limiting and audit correlation. */
export function clientKeyOf(req) {
  const socket = req.socket;
  const address = socket && typeof socket.remoteAddress === 'string' ? socket.remoteAddress : '';
  return address.length > 0 ? address : 'unknown';
}

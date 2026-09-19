/*
 * Test fixtures.
 *
 * The integration tests start **the real server** and point it at a stub vendor
 * that speaks the OpenAI wire protocol. That combination matters: the routing,
 * auth, rate limiting, batching, validation and SSE relay under test are the
 * production code paths, not re-implementations of them. The only thing faked
 * is the vendor, and it is faked at the socket level rather than by stubbing
 * `fetch`, so framing, status codes and stream termination are all exercised.
 *
 * Everything here runs with no network access and no real credentials.
 */

import { createServer } from 'node:http';
import { createApp } from '../src/app.js';
import { ServerConfig } from '../src/config.js';

export const APP_TOKEN = 'app-token-for-tests';
export const STUB_CHAT_KEY = 'sk-stub-chat-secret';
export const STUB_EMBED_KEY = 'sk-stub-embed-secret';
export const STUB_EMBEDDING_MODEL = 'test-embed-model';
export const STUB_CHAT_MODEL = 'test-chat-model';

/** Deterministic vector, so assertions can name exact numbers. */
export function vectorFor(text, dimension) {
  const vector = [];
  for (let i = 0; i < dimension; i++) {
    vector.push(Math.round(((text.length + i) % 89) * 1000) / 1000000);
  }
  return vector;
}

function listen(server) {
  return new Promise((resolve) => {
    server.listen(0, '127.0.0.1', () => {
      resolve(server.address().port);
    });
  });
}

function close(server) {
  return new Promise((resolve) => {
    if (!server.listening) {
      resolve();
      return;
    }
    server.close(() => {
      resolve();
    });
    if (typeof server.closeAllConnections === 'function') {
      server.closeAllConnections();
    }
  });
}

function readBody(req) {
  return new Promise((resolve) => {
    const chunks = [];
    req.on('data', (chunk) => {
      chunks.push(chunk);
    });
    req.on('end', () => {
      resolve(Buffer.concat(chunks).toString('utf8'));
    });
    req.on('error', () => {
      resolve('');
    });
  });
}

function defaultEmbeddings(res, body) {
  const dimension = Number.isInteger(body.dimensions) && body.dimensions > 0 ? body.dimensions : 1024;
  const input = Array.isArray(body.input) ? body.input : [body.input];
  const data = input.map((text, index) => ({
    object: 'embedding',
    index,
    embedding: vectorFor(String(text), dimension),
  }));
  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ object: 'list', data, model: body.model }));
}

function defaultChat(res, body) {
  if (body.stream === true) {
    res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache' });
    for (const part of ['你好', '，', '世界']) {
      res.write(`data: ${JSON.stringify({ choices: [{ delta: { content: part } }] })}\n\n`);
    }
    res.write('data: [DONE]\n\n');
    res.end();
    return;
  }
  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({
    id: 'stub-completion',
    choices: [{
      index: 0,
      message: { role: 'assistant', content: '完整回答' },
      finish_reason: 'stop',
    }],
    usage: { total_tokens: 7 },
  }));
}

/**
 * Starts the fake vendor.
 *
 * `state.embeddings` / `state.chat` replace the default handler for a single
 * test, which is how failure modes (bad payload, 429, slow stream) are produced
 * without a single line of mocking library.
 */
export async function startStubUpstream() {
  const state = {
    requests: [],
    embeddings: null,
    chat: null,
    streamAborted: false,
    streamClosedCleanly: false,
  };

  const server = createServer(async (req, res) => {
    const raw = await readBody(req);
    let body = null;
    try {
      body = JSON.parse(raw);
    } catch (e) {
      body = null;
    }
    state.requests.push({
      path: req.url,
      method: req.method,
      headers: req.headers,
      body,
      raw,
    });

    if (req.url.indexOf('/embeddings') >= 0) {
      if (state.embeddings) {
        await state.embeddings(req, res, body, state);
        return;
      }
      defaultEmbeddings(res, body || {});
      return;
    }
    if (req.url.indexOf('/chat/completions') >= 0) {
      if (state.chat) {
        await state.chat(req, res, body, state);
        return;
      }
      defaultChat(res, body || {});
      return;
    }
    res.writeHead(404, { 'Content-Type': 'application/json' });
    res.end('{}');
  });

  const port = await listen(server);
  return {
    server,
    state,
    origin: `http://127.0.0.1:${port}`,
    baseUrl: `http://127.0.0.1:${port}/v1`,
    close: () => close(server),
  };
}

/**
 * Starts the server under test, wired to `upstream` when one is supplied.
 * Passing no upstream produces the "operator has not configured keys yet" case.
 */
export async function startApp(options = {}) {
  const { upstream, ...overrides } = options;
  const config = new ServerConfig({
    port: 0,
    appToken: APP_TOKEN,
    chatBaseUrl: upstream ? upstream.baseUrl : '',
    chatApiKey: upstream ? STUB_CHAT_KEY : '',
    chatModel: STUB_CHAT_MODEL,
    embeddingBaseUrl: upstream ? upstream.baseUrl : '',
    embeddingApiKey: upstream ? STUB_EMBED_KEY : '',
    embeddingModel: STUB_EMBEDDING_MODEL,
    embeddingDimension: 8,
    embeddingBatchSize: 2,
    rateLimitPerMinute: 10000,
    upstreamTimeoutMs: 5000,
    ...overrides,
  });
  const app = createApp(config, options.appOptions || {});
  const port = await listen(app.server);
  return {
    app,
    config,
    origin: `http://127.0.0.1:${port}`,
    close: () => close(app.server),
  };
}

export function parseJson(text) {
  try {
    return JSON.parse(text);
  } catch (e) {
    return null;
  }
}

/** POSTs JSON with the app token by default; pass `token: ''` to omit it. */
export async function post(origin, path, options = {}) {
  const headers = { 'Content-Type': 'application/json' };
  if (options.token !== null) {
    const token = options.token === undefined ? APP_TOKEN : options.token;
    if (token.length > 0) {
      headers['Authorization'] = `Bearer ${token}`;
    }
  }
  if (options.extraHeaders) {
    for (const key of Object.keys(options.extraHeaders)) {
      headers[key] = options.extraHeaders[key];
    }
  }
  const response = await fetch(`${origin}${path}`, {
    method: options.method || 'POST',
    headers,
    body: options.raw !== undefined ? options.raw : JSON.stringify(options.body || {}),
  });
  const text = await response.text();
  return {
    status: response.status,
    headers: response.headers,
    contentType: response.headers.get('content-type') || '',
    text,
    json: parseJson(text),
  };
}

export async function get(origin, path, options = {}) {
  const headers = {};
  if (options.token !== null && options.token !== '') {
    headers['Authorization'] = `Bearer ${options.token === undefined ? APP_TOKEN : options.token}`;
  }
  const response = await fetch(`${origin}${path}`, { headers });
  const text = await response.text();
  return { status: response.status, text, json: parseJson(text), headers: response.headers };
}

/** Polls until `predicate` holds, so timing-dependent tests do not race. */
export async function waitFor(predicate, timeoutMs = 3000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (predicate()) {
      return true;
    }
    await new Promise((resolve) => {
      setTimeout(resolve, 10);
    });
  }
  return predicate();
}

/** A config whose upstreams are unreachable, for transport-failure tests. */
export async function startAppWithFetch(options = {}) {
  const failingFetch = () => Promise.reject(new Error('simulated transport failure'));
  return await startApp({ ...options, appOptions: { fetchImpl: failingFetch } });
}

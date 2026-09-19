/*
 * End-to-end tests.
 *
 * Each block starts the real server pointed at a stub vendor, then drives it
 * over HTTP. What is under test is therefore the production stack — routing,
 * auth, rate limiting, batching, upstream validation and the SSE relay — with
 * only the vendor replaced.
 *
 * The privacy block is the one worth reading twice: it asserts that a student's
 * question never reaches a log line, which is the property that makes it safe
 * to keep an audit trail at all.
 */

import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import { resetLogTarget, setLogTarget } from '../src/log.js';
import {
  APP_TOKEN,
  STUB_CHAT_KEY,
  STUB_CHAT_MODEL,
  STUB_EMBED_KEY,
  STUB_EMBEDDING_MODEL,
  get,
  post,
  startApp,
  startStubUpstream,
  vectorFor,
  waitFor,
} from '../testlib/support.js';

const EMBED_DIMENSION = 8;

/** A shared happy-path pair, so the common cases do not each pay for a boot. */
async function withStack(overrides, body) {
  const upstream = await startStubUpstream();
  const app = await startApp({ upstream, ...overrides });
  try {
    await body({ upstream, app, origin: app.origin });
  } finally {
    await app.close();
    await upstream.close();
  }
}

describe('GET /health', () => {
  it('reports capabilities without requiring auth and without leaking secrets', async () => {
    await withStack({}, async ({ origin }) => {
      const response = await get(origin, '/health');
      assert.equal(response.status, 200);
      assert.equal(response.json.ok, true);
      assert.equal(response.json.authRequired, true);
      assert.equal(response.json.embedding.configured, true);
      assert.equal(response.json.embedding.model, STUB_EMBEDDING_MODEL);
      assert.equal(response.json.chat.configured, true);

      assert.equal(response.text.includes(APP_TOKEN), false);
      assert.equal(response.text.includes(STUB_EMBED_KEY), false);
      assert.equal(response.text.includes(STUB_CHAT_KEY), false);
      // The vendor's own host is not an unauthenticated caller's business.
      assert.equal(response.text.includes('127.0.0.1'), false);
    });
  });

  it('rejects a non-GET method', async () => {
    await withStack({}, async ({ origin }) => {
      const response = await post(origin, '/health', { body: {} });
      assert.equal(response.status, 405);
      assert.equal(response.json.error.code, 'method_not_allowed');
    });
  });
});

describe('authentication', () => {
  it('refuses a request with no token', async () => {
    await withStack({}, async ({ origin }) => {
      const response = await post(origin, '/embed', { token: '', body: { inputs: ['a'] } });
      assert.equal(response.status, 401);
      assert.equal(response.json.error.code, 'unauthorized');
    });
  });

  it('refuses a wrong token', async () => {
    await withStack({}, async ({ origin }) => {
      const response = await post(origin, '/embed', { token: 'not-the-token', body: { inputs: ['a'] } });
      assert.equal(response.status, 401);
    });
  });

  it('accepts the token as a Bearer header or as x-app-token', async () => {
    await withStack({}, async ({ origin }) => {
      const bearer = await post(origin, '/embed', { body: { inputs: ['a'] } });
      assert.equal(bearer.status, 200);

      const header = await post(origin, '/embed', {
        token: null,
        extraHeaders: { 'x-app-token': APP_TOKEN },
        body: { inputs: ['a'] },
      });
      assert.equal(header.status, 200);
    });
  });

  it('lets everything through when the operator has not set a token', async () => {
    await withStack({ appToken: '' }, async ({ origin }) => {
      const health = await get(origin, '/health');
      assert.equal(health.json.authRequired, false);
      const response = await post(origin, '/embed', { token: '', body: { inputs: ['a'] } });
      assert.equal(response.status, 200);
    });
  });

  it('never asks the app for a vendor key — only for the app token', async () => {
    await withStack({}, async ({ origin }) => {
      // A request carrying nothing but the app token succeeds, and the vendor
      // key shows up only on the hop the server makes on the app's behalf.
      const response = await post(origin, '/embed', { body: { inputs: ['一次检索'] } });
      assert.equal(response.status, 200);
      assert.equal(response.text.includes(STUB_EMBED_KEY), false);
    });
  });
});

describe('POST /embed', () => {
  it('embeds a batch, splitting it into provider-sized calls', async () => {
    await withStack({}, async ({ upstream, origin }) => {
      const inputs = ['a', 'bb', 'ccc', 'dddd', 'eeeee'];
      const response = await post(origin, '/embed', { body: { model: '', inputs } });

      assert.equal(response.status, 200);
      assert.equal(response.json.dimension, EMBED_DIMENSION);
      assert.equal(response.json.vectors.length, inputs.length);
      assert.equal(response.json.model, STUB_EMBEDDING_MODEL);

      // batchSize is 2, so five inputs become three upstream calls.
      const calls = upstream.state.requests;
      assert.equal(calls.length, 3);
      assert.deepEqual(calls.map((c) => c.body.input.length), [2, 2, 1]);
      assert.deepEqual(calls.map((c) => c.body.input).flat(), inputs);
    });
  });

  it('returns vectors in input order, matching the provider exactly', async () => {
    await withStack({}, async ({ origin }) => {
      const inputs = ['a', 'bb', 'ccc'];
      const response = await post(origin, '/embed', { body: { inputs } });
      assert.deepEqual(response.json.vectors[0], vectorFor('a', EMBED_DIMENSION));
      assert.deepEqual(response.json.vectors[1], vectorFor('bb', EMBED_DIMENSION));
      assert.deepEqual(response.json.vectors[2], vectorFor('ccc', EMBED_DIMENSION));
    });
  });

  it('keeps the right vectors attached when the provider shuffles their order', async () => {
    await withStack({}, async ({ upstream, origin }) => {
      upstream.state.embeddings = (req, res, body) => {
        const data = body.input
          .map((text, index) => ({ index, embedding: vectorFor(text, body.dimensions || 1024) }))
          .reverse();
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ data, model: body.model }));
      };
      const inputs = ['a', 'bb', 'ccc'];
      const response = await post(origin, '/embed', { body: { inputs } });
      assert.deepEqual(response.json.vectors[1], vectorFor('bb', EMBED_DIMENSION));
    });
  });

  it('uses the configured model when the app sends an empty or absent one', async () => {
    await withStack({}, async ({ upstream, origin }) => {
      await post(origin, '/embed', { body: { model: '', inputs: ['a'] } });
      assert.equal(upstream.state.requests[0].body.model, STUB_EMBEDDING_MODEL);
      upstream.state.requests.length = 0;
      await post(origin, '/embed', { body: { inputs: ['a'] } });
      assert.equal(upstream.state.requests[0].body.model, STUB_EMBEDDING_MODEL);
    });
  });

  it('honours an explicit model from the caller', async () => {
    await withStack({}, async ({ upstream, origin }) => {
      await post(origin, '/embed', { body: { model: 'bge-large-zh-v1.5', inputs: ['a'] } });
      assert.equal(upstream.state.requests[0].body.model, 'bge-large-zh-v1.5');
    });
  });

  it('tells the provider which width to produce', async () => {
    await withStack({}, async ({ upstream, origin }) => {
      await post(origin, '/embed', { body: { inputs: ['a'] } });
      assert.equal(upstream.state.requests[0].body.dimensions, EMBED_DIMENSION);
    });
  });

  it('attaches the vendor key only on the server-to-vendor hop', async () => {
    await withStack({}, async ({ upstream, origin }) => {
      await post(origin, '/embed', { body: { inputs: ['a'] } });
      assert.equal(upstream.state.requests[0].headers.authorization, `Bearer ${STUB_EMBED_KEY}`);
    });
  });

  it('rejects a short provider answer instead of returning misaligned vectors', async () => {
    await withStack({}, async ({ upstream, origin }) => {
      upstream.state.embeddings = (req, res, body) => {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ data: [], model: body.model }));
      };
      const response = await post(origin, '/embed', { body: { inputs: ['a', 'b'] } });
      assert.equal(response.status, 502);
      assert.equal(response.json.error.code, 'upstream_error');
    });
  });

  it('rejects a provider answer whose width contradicts the configuration', async () => {
    await withStack({}, async ({ upstream, origin }) => {
      upstream.state.embeddings = (req, res, body) => {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({
          data: body.input.map((text, index) => ({ index, embedding: [1, 2, 3] })),
          model: body.model,
        }));
      };
      const response = await post(origin, '/embed', { body: { inputs: ['a'] } });
      assert.equal(response.status, 502);
    });
  });

  it('passes an upstream 429 through so the app can back off', async () => {
    await withStack({}, async ({ upstream, origin }) => {
      upstream.state.embeddings = (req, res) => {
        res.writeHead(429, { 'Content-Type': 'application/json' });
        res.end('{"error":{"message":"rate limited"}}');
      };
      const response = await post(origin, '/embed', { body: { inputs: ['a'] } });
      assert.equal(response.status, 429);
      assert.equal(response.json.error.upstreamStatus, 429);
    });
  });

  it('reports an upstream 5xx as 502 rather than echoing it', async () => {
    await withStack({}, async ({ upstream, origin }) => {
      upstream.state.embeddings = (req, res) => {
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end('{"error":"boom"}');
      };
      const response = await post(origin, '/embed', { body: { inputs: ['a'] } });
      assert.equal(response.status, 502);
      assert.equal(response.json.error.upstreamStatus, 500);
    });
  });

  it('answers 503 when the operator has not configured an embedding key', async () => {
    await withStack({ embeddingApiKey: '' }, async ({ origin }) => {
      const response = await post(origin, '/embed', { body: { inputs: ['a'] } });
      assert.equal(response.status, 503);
      assert.equal(response.json.error.code, 'unavailable');
    });
  });

  it('rejects a malformed request body', async () => {
    await withStack({}, async ({ origin }) => {
      for (const body of [{}, { inputs: [] }, { inputs: [1, 2] }]) {
        const response = await post(origin, '/embed', { body });
        assert.equal(response.status, 400, JSON.stringify(body));
        assert.equal(response.json.error.code, 'bad_request');
      }
    });
  });

  it('rejects an oversized body with 413', async () => {
    await withStack({}, async ({ origin }) => {
      const response = await post(origin, '/embed', { raw: 'x'.repeat(1024 * 1024 + 64) });
      assert.equal(response.status, 413);
      assert.equal(response.json.error.code, 'body_too_large');
    });
  });
});

describe('POST /chat/completions', () => {
  it('relays a buffered answer unchanged', async () => {
    await withStack({}, async ({ upstream, origin }) => {
      const response = await post(origin, '/chat/completions', {
        body: { model: 'deepseek-v4-flash', messages: [{ role: 'user', content: '你好' }] },
      });
      assert.equal(response.status, 200);
      assert.equal(response.json.choices[0].message.content, '完整回答');
      // Round-tripping the whole body keeps tool_calls and usage intact.
      assert.deepEqual(response.json.usage, { total_tokens: 7 });
      assert.equal(upstream.state.requests[0].body.model, STUB_CHAT_MODEL);
    });
  });

  it('streams SSE deltas through in order', async () => {
    await withStack({}, async ({ upstream, origin }) => {
      const response = await post(origin, '/chat/completions', {
        body: { messages: [{ role: 'user', content: '你好' }], stream: true },
      });
      assert.equal(response.status, 200);
      assert.match(response.contentType, /text\/event-stream/);
      assert.match(response.text, /data: /);
      const bodies = response.text
        .split('\n')
        .filter((line) => line.startsWith('data: '))
        .map((line) => line.slice(6).trim())
        .filter((payload) => payload !== '[DONE]')
        .map((payload) => JSON.parse(payload).choices[0].delta.content);
      assert.deepEqual(bodies, ['你好', '，', '世界']);
      assert.match(response.text, /data: \[DONE\]/);
      // The `stream` flag has to reach the vendor, or the app silently loses
      // streaming and falls back to buffering without any visible error.
      assert.equal(upstream.state.requests[0].body.stream, true);
    });
  });

  it('is reachable at the OpenAI path and at the short alias', async () => {
    await withStack({}, async ({ origin }) => {
      for (const path of ['/v1/chat/completions', '/chat']) {
        const response = await post(origin, path, {
          body: { messages: [{ role: 'user', content: 'hi' }] },
        });
        assert.equal(response.status, 200, path);
      }
    });
  });

  it('forwards only the fields the app is allowed to send', async () => {
    await withStack({}, async ({ upstream, origin }) => {
      await post(origin, '/chat/completions', {
        body: {
          messages: [{ role: 'user', content: 'hi' }],
          tools: [{ type: 'function' }],
          api_key: 'smuggled',
          evil: true,
        },
      });
      const forwarded = upstream.state.requests[0].body;
      assert.deepEqual(forwarded.tools, [{ type: 'function' }]);
      assert.equal(forwarded.api_key, undefined);
      assert.equal(forwarded.evil, undefined);
    });
  });

  it('reports an upstream failure as JSON, never as a broken stream', async () => {
    await withStack({}, async ({ upstream, origin }) => {
      upstream.state.chat = (req, res) => {
        res.writeHead(402, { 'Content-Type': 'application/json' });
        res.end('{"error":{"message":"Insufficient Balance"}}');
      };
      const response = await post(origin, '/chat/completions', {
        body: { messages: [{ role: 'user', content: 'hi' }], stream: true },
      });
      // A vendor refusal must stay readable. Had the SSE header been written
      // first, the app would have received an empty stream instead.
      assert.equal(response.status, 402);
      assert.match(response.contentType, /application\/json/);
      assert.equal(response.json.error.upstreamStatus, 402);
      assert.equal(response.json.error.code, 'payment_required');
    });
  });

  it('answers 503 when the operator has not configured a chat key', async () => {
    await withStack({ chatApiKey: '' }, async ({ origin }) => {
      const response = await post(origin, '/chat/completions', {
        body: { messages: [{ role: 'user', content: 'hi' }] },
      });
      assert.equal(response.status, 503);
    });
  });

  it('rejects a request with no usable messages', async () => {
    await withStack({}, async ({ origin }) => {
      for (const body of [{}, { messages: [] }, { messages: 'x' }, { messages: [{}] }]) {
        const response = await post(origin, '/chat/completions', { body });
        assert.equal(response.status, 400, JSON.stringify(body));
      }
    });
  });

  it('caps the conversation length', async () => {
    await withStack({}, async ({ origin }) => {
      const messages = new Array(65).fill({ role: 'user', content: 'hi' });
      const response = await post(origin, '/chat/completions', { body: { messages } });
      assert.equal(response.status, 400);
    });
  });

  it('stops pulling from the vendor once the app disconnects', async () => {
    const upstream = await startStubUpstream();
    upstream.state.chat = (req, res) => {
      res.writeHead(200, { 'Content-Type': 'text/event-stream' });
      res.write(`data: ${JSON.stringify({ choices: [{ delta: { content: 'x' } }] })}\n\n`);
      const timer = setInterval(() => {
        try {
          res.write(`data: ${JSON.stringify({ choices: [{ delta: { content: 'y' } }] })}\n\n`);
        } catch (e) {
          // The socket is already gone.
        }
      }, 15);
      res.on('close', () => {
        clearInterval(timer);
        if (!res.writableFinished) {
          upstream.state.streamAborted = true;
        }
      });
    };
    const app = await startApp({ upstream });
    try {
      const controller = new AbortController();
      const response = await fetch(`${app.origin}/chat/completions`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${APP_TOKEN}`,
        },
        body: JSON.stringify({ messages: [{ role: 'user', content: 'hi' }], stream: true }),
        signal: controller.signal,
      });
      assert.equal(response.status, 200);
      const reader = response.body.getReader();
      const first = await reader.read();
      assert.equal(first.done, false);

      controller.abort();
      const aborted = await waitFor(() => upstream.state.streamAborted === true);
      assert.equal(aborted, true, 'the upstream request should have been aborted');
    } finally {
      await app.close();
      await upstream.close();
    }
  });
});

describe('routing', () => {
  it('answers 404 on an unknown path', async () => {
    await withStack({}, async ({ origin }) => {
      const response = await post(origin, '/nope', { body: {} });
      assert.equal(response.status, 404);
      assert.equal(response.json.error.code, 'not_found');
    });
  });

  it('checks the token before the method, so nothing is disclosed unauthenticated', async () => {
    await withStack({}, async ({ origin }) => {
      // An unauthenticated caller learns only that it is not authorised — not
      // which methods the endpoint accepts.
      const anonymous = await get(origin, '/embed', { token: null });
      assert.equal(anonymous.status, 401);

      const authenticated = await get(origin, '/embed');
      assert.equal(authenticated.status, 405);
    });
  });

  it('tolerates a trailing slash', async () => {
    await withStack({}, async ({ origin }) => {
      const response = await post(origin, '/embed/', { body: { inputs: ['a'] } });
      assert.equal(response.status, 200);
    });
  });
});

describe('rate limiting', () => {
  it('answers 429 with Retry-After once the window is full', async () => {
    await withStack({ rateLimitPerMinute: 2 }, async ({ origin }) => {
      assert.equal((await post(origin, '/embed', { body: { inputs: ['a'] } })).status, 200);
      assert.equal((await post(origin, '/embed', { body: { inputs: ['a'] } })).status, 200);
      const blocked = await post(origin, '/embed', { body: { inputs: ['a'] } });
      assert.equal(blocked.status, 429);
      assert.equal(blocked.json.error.code, 'rate_limited');
      assert.equal(Number(blocked.headers.get('retry-after')) >= 1, true);
    });
  });

  it('leaves /health reachable while a client is throttled', async () => {
    await withStack({ rateLimitPerMinute: 1 }, async ({ origin }) => {
      await post(origin, '/embed', { body: { inputs: ['a'] } });
      assert.equal((await post(origin, '/embed', { body: { inputs: ['a'] } })).status, 429);
      assert.equal((await get(origin, '/health')).status, 200);
    });
  });
});

describe('audit and privacy', () => {
  it('records the request without recording what was asked', async () => {
    const upstream = await startStubUpstream();
    const app = await startApp({ upstream });
    const lines = [];
    const collect = (line) => {
      lines.push(line);
    };
    setLogTarget({ info: collect, warn: collect, error: collect });
    try {
      const marker = 'MARKER-学生的私密问题-9f27';
      const response = await post(app.origin, '/chat/completions', {
        body: { messages: [{ role: 'user', content: marker }] },
      });
      assert.equal(response.status, 200);

      // Give the audit line, which is written on response finish, a moment.
      await waitFor(() => lines.some((line) => line.includes('"message":"request"')));

      const joined = lines.join('\n');
      assert.equal(joined.includes(marker), false, 'the prompt must never be logged');
      assert.equal(joined.includes(STUB_CHAT_KEY), false, 'the vendor key must never be logged');
      assert.equal(joined.includes(APP_TOKEN), false, 'the app token must never be logged');

      const auditLine = lines
        .map((line) => JSON.parse(line))
        .find((record) => record.message === 'request' && record.path === '/chat/completions');
      assert.ok(auditLine, 'an audit line should have been written');
      assert.equal(auditLine.status, 200);
      assert.equal(typeof auditLine.requestId, 'string');
      assert.equal(typeof auditLine.ms, 'number');
    } finally {
      resetLogTarget();
      await app.close();
      await upstream.close();
    }
  });

  it('never logs the text sent for embedding', async () => {
    const upstream = await startStubUpstream();
    const app = await startApp({ upstream });
    const lines = [];
    setLogTarget({
      info: (line) => {
        lines.push(line);
      },
      warn: (line) => {
        lines.push(line);
      },
      error: (line) => {
        lines.push(line);
      },
    });
    try {
      const marker = 'MARKER-讲义正文片段-b31c';
      await post(app.origin, '/embed', { body: { inputs: [marker] } });
      await waitFor(() => lines.length > 0);
      assert.equal(lines.join('\n').includes(marker), false);
    } finally {
      resetLogTarget();
      await app.close();
      await upstream.close();
    }
  });
});

describe('transport failure', () => {
  it('answers 502 when the vendor cannot be reached', async () => {
    const app = await startApp({
      embeddingApiKey: 'k',
      embeddingBaseUrl: 'https://embed.invalid/v1',
      chatApiKey: 'k',
      chatBaseUrl: 'https://chat.invalid/v1',
      appOptions: {
        fetchImpl: () => Promise.reject(new Error('simulated transport failure')),
      },
    });
    try {
      const embed = await post(app.origin, '/embed', { body: { inputs: ['a'] } });
      assert.equal(embed.status, 502);
      assert.equal(embed.json.error.code, 'upstream_error');

      const chat = await post(app.origin, '/chat/completions', {
        body: { messages: [{ role: 'user', content: 'hi' }] },
      });
      assert.equal(chat.status, 502);
    } finally {
      await app.close();
    }
  });
});

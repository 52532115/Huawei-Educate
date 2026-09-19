/*
 * Pure-function tests: configuration, the access guard, and the validation
 * rules that decide whether a request or an upstream answer is acceptable.
 *
 * The validation cases are the ones worth having in isolation. Each of them
 * corresponds to a way retrieval could silently return the wrong passage:
 * vectors that arrive out of order, a short response, a mismatched width.
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

import {
  DEFAULT_CHAT_MODEL,
  DEFAULT_EMBEDDING_BATCH_SIZE,
  DEFAULT_EMBEDDING_MODEL,
  DEFAULT_PORT,
  DEFAULT_RATE_LIMIT_PER_MINUTE,
  MAX_EMBED_INPUTS,
  ServerConfig,
  loadConfig,
  normalizeBaseUrl,
} from '../src/config.js';
import { RateLimiter, extractToken, tokenMatches } from '../src/guard.js';
import {
  EmbedRequestError,
  chunkInputs,
  collectInputs,
  readUpstreamVectors,
} from '../src/embed.js';
import { buildUpstreamChatBody, ChatRequestError } from '../src/chat.js';
import { codeForStatus, combineSignals, statusForApp } from '../src/upstream.js';

function baseConfig(overrides = {}) {
  return new ServerConfig({
    port: 0,
    appToken: '',
    chatBaseUrl: 'https://chat.example/v1',
    chatApiKey: '',
    chatModel: DEFAULT_CHAT_MODEL,
    embeddingBaseUrl: 'https://embed.example/v1',
    embeddingApiKey: '',
    embeddingModel: DEFAULT_EMBEDDING_MODEL,
    embeddingDimension: 0,
    embeddingBatchSize: DEFAULT_EMBEDDING_BATCH_SIZE,
    rateLimitPerMinute: DEFAULT_RATE_LIMIT_PER_MINUTE,
    upstreamTimeoutMs: 60000,
    ...overrides,
  });
}

describe('config', () => {
  it('falls back to defaults when the environment is empty', () => {
    const config = loadConfig({});
    assert.equal(config.port, DEFAULT_PORT);
    assert.equal(config.chatModel, DEFAULT_CHAT_MODEL);
    assert.equal(config.embeddingModel, DEFAULT_EMBEDDING_MODEL);
    assert.equal(config.embeddingBatchSize, DEFAULT_EMBEDDING_BATCH_SIZE);
    assert.equal(config.appToken, '');
  });

  it('reads overrides from the environment', () => {
    const config = loadConfig({
      PORT: '9000',
      APP_TOKEN: 'tok',
      CHAT_MODEL: 'my-chat',
      EMBEDDING_MODEL: 'my-embed',
      EMBEDDING_DIMENSION: '1024',
      EMBEDDING_BATCH_SIZE: '4',
      RATE_LIMIT_PER_MINUTE: '30',
    });
    assert.equal(config.port, 9000);
    assert.equal(config.appToken, 'tok');
    assert.equal(config.chatModel, 'my-chat');
    assert.equal(config.embeddingModel, 'my-embed');
    assert.equal(config.embeddingDimension, 1024);
    assert.equal(config.embeddingBatchSize, 4);
    assert.equal(config.rateLimitPerMinute, 30);
  });

  it('ignores an out-of-range or non-numeric number instead of trusting it', () => {
    assert.equal(loadConfig({ PORT: 'abc' }).port, DEFAULT_PORT);
    assert.equal(loadConfig({ PORT: '99999' }).port, DEFAULT_PORT);
    assert.equal(loadConfig({ EMBEDDING_BATCH_SIZE: '0' }).embeddingBatchSize,
      DEFAULT_EMBEDDING_BATCH_SIZE);
    assert.equal(loadConfig({ RATE_LIMIT_PER_MINUTE: 'x' }).rateLimitPerMinute,
      DEFAULT_RATE_LIMIT_PER_MINUTE);
  });

  it('strips trailing slashes from base URLs', () => {
    assert.equal(normalizeBaseUrl('https://x.example/v1//'), 'https://x.example/v1');
    assert.equal(normalizeBaseUrl('https://x.example/v1'), 'https://x.example/v1');
    assert.equal(normalizeBaseUrl('   '), '');
    assert.equal(normalizeBaseUrl(undefined), '');
  });

  it('reports configured state from the presence of a key', () => {
    assert.equal(baseConfig().chatConfigured(), false);
    assert.equal(baseConfig({ chatApiKey: 'k' }).chatConfigured(), true);
    assert.equal(baseConfig({ chatBaseUrl: '', chatApiKey: 'k' }).chatConfigured(), false);
    assert.equal(baseConfig({ embeddingApiKey: 'k' }).embeddingConfigured(), true);
  });

  it('treats an empty token as "auth disabled"', () => {
    assert.equal(baseConfig().authRequired(), false);
    assert.equal(baseConfig({ appToken: 'x' }).authRequired(), true);
  });

  it('never exposes a key, and never names the vendor, in /health', () => {
    const config = baseConfig({
      appToken: 'super-secret-token',
      chatApiKey: 'sk-chat-secret',
      embeddingApiKey: 'sk-embed-secret',
      embeddingDimension: 1024,
    });
    const described = config.describe();
    assert.equal(described.ok, true);
    assert.equal(described.authRequired, true);
    assert.equal(described.chat.configured, true);
    assert.equal(described.embedding.configured, true);
    assert.equal(described.embedding.dimension, 1024);

    const serialized = JSON.stringify(described);
    assert.equal(serialized.includes('super-secret-token'), false);
    assert.equal(serialized.includes('sk-chat-secret'), false);
    assert.equal(serialized.includes('sk-embed-secret'), false);
    assert.equal(serialized.includes('chat.example'), false);
    assert.equal(serialized.includes('embed.example'), false);
  });
});

describe('guard.extractToken', () => {
  it('reads a Bearer token case-insensitively', () => {
    assert.equal(extractToken({ headers: { authorization: 'Bearer abc' } }), 'abc');
    assert.equal(extractToken({ headers: { authorization: 'bearer abc' } }), 'abc');
    assert.equal(extractToken({ headers: { authorization: 'BEARER  abc ' } }), 'abc');
  });

  it('falls back to the x-app-token header', () => {
    assert.equal(extractToken({ headers: { 'x-app-token': 'tok' } }), 'tok');
  });

  it('prefers Authorization when both are present', () => {
    assert.equal(
      extractToken({ headers: { authorization: 'Bearer from-auth', 'x-app-token': 'from-header' } }),
      'from-auth',
    );
  });

  it('returns empty when nothing is presented', () => {
    assert.equal(extractToken({ headers: {} }), '');
    assert.equal(extractToken({ headers: { authorization: 'Basic abc' } }), '');
    assert.equal(extractToken({ headers: { authorization: 'Bearer   ' } }), '');
  });
});

describe('guard.tokenMatches', () => {
  it('accepts an exact match and rejects everything else', () => {
    assert.equal(tokenMatches('abc', 'abc'), true);
    assert.equal(tokenMatches('abc', 'abd'), false);
    assert.equal(tokenMatches('abc', 'abcd'), false);
    assert.equal(tokenMatches('', 'abc'), false);
    assert.equal(tokenMatches('abc', ''), false);
    assert.equal(tokenMatches(null, 'abc'), false);
    assert.equal(tokenMatches('abc', undefined), false);
  });
});

describe('guard.RateLimiter', () => {
  it('allows exactly `perMinute` requests inside one window', () => {
    const limiter = new RateLimiter(3);
    assert.equal(limiter.check('a', 1000).allowed, true);
    assert.equal(limiter.check('a', 1001).allowed, true);
    assert.equal(limiter.check('a', 1002).allowed, true);
    const blocked = limiter.check('a', 1003);
    assert.equal(blocked.allowed, false);
    assert.equal(blocked.retryAfterSeconds, 60);
  });

  it('starts a fresh window once the old one expires', () => {
    const limiter = new RateLimiter(1);
    assert.equal(limiter.check('a', 1000).allowed, true);
    assert.equal(limiter.check('a', 2000).allowed, false);
    assert.equal(limiter.check('a', 61000).allowed, true);
  });

  it('tracks clients independently', () => {
    const limiter = new RateLimiter(1);
    assert.equal(limiter.check('a', 1000).allowed, true);
    assert.equal(limiter.check('b', 1000).allowed, true);
    assert.equal(limiter.check('a', 1000).allowed, false);
  });

  it('reports the remaining budget', () => {
    const limiter = new RateLimiter(5);
    assert.equal(limiter.check('a', 1000).remaining, 4);
    assert.equal(limiter.check('a', 1001).remaining, 3);
  });

  it('disables itself when the limit is zero or invalid', () => {
    assert.equal(new RateLimiter(0).check('a', 1000).allowed, true);
    assert.equal(new RateLimiter(-1).check('a', 1000).remaining, -1);
  });

  it('prunes expired buckets so memory stays bounded', () => {
    const limiter = new RateLimiter(1);
    limiter.check('a', 1000);
    limiter.check('b', 1000);
    assert.equal(limiter.buckets.size, 2);
    limiter.prune(61000);
    assert.equal(limiter.buckets.size, 0);
  });
});

describe('embed.collectInputs', () => {
  it('accepts our `inputs` array', () => {
    assert.deepEqual(collectInputs({ inputs: ['a', 'b'] }), ['a', 'b']);
  });

  it('accepts the OpenAI `input` field, as a string or an array', () => {
    assert.deepEqual(collectInputs({ input: 'a' }), ['a']);
    assert.deepEqual(collectInputs({ input: ['a'] }), ['a']);
    // One bare string is a legitimate single-input request, not a malformed list.
    assert.deepEqual(collectInputs({ inputs: 'x' }), ['x']);
  });

  it('ignores an advisory model field', () => {
    assert.deepEqual(collectInputs({ model: 'whatever', inputs: ['a'] }), ['a']);
  });

  it('rejects a missing, empty or malformed input list', () => {
    for (const body of [{}, { inputs: [] }, { inputs: [1] }, { inputs: ['a', null] }]) {
      assert.throws(() => collectInputs(body), EmbedRequestError);
    }
    assert.throws(() => collectInputs('nope'), EmbedRequestError);
    assert.throws(() => collectInputs([]), EmbedRequestError);
    assert.throws(() => collectInputs(null), EmbedRequestError);
  });

  it('rejects too many inputs', () => {
    const many = new Array(MAX_EMBED_INPUTS + 1).fill('a');
    assert.throws(() => collectInputs({ inputs: many }), EmbedRequestError);
  });

  it('rejects one oversized input', () => {
    assert.throws(() => collectInputs({ inputs: ['x'.repeat(4001)] }), EmbedRequestError);
  });

  it('rejects a batch that is oversized in total', () => {
    const inputs = new Array(60).fill('x'.repeat(4000));
    assert.throws(() => collectInputs({ inputs }), EmbedRequestError);
  });

  it('allows empty strings through — the provider decides what they mean', () => {
    assert.deepEqual(collectInputs({ inputs: [''] }), ['']);
  });
});

describe('embed.chunkInputs', () => {
  it('splits into provider-sized batches, preserving order', () => {
    assert.deepEqual(chunkInputs(['a', 'b', 'c', 'd', 'e'], 2), [['a', 'b'], ['c', 'd'], ['e']]);
  });

  it('returns one batch when the size exceeds the input count', () => {
    assert.deepEqual(chunkInputs(['a', 'b'], 10), [['a', 'b']]);
  });

  it('returns nothing for an empty list', () => {
    assert.deepEqual(chunkInputs([], 4), []);
  });

  it('treats a non-positive size as "no splitting"', () => {
    assert.deepEqual(chunkInputs(['a', 'b'], 0), [['a', 'b']]);
  });
});

describe('embed.readUpstreamVectors', () => {
  const row = (values) => ({ object: 'embedding', embedding: values });

  it('accepts a well-formed answer', () => {
    const read = readUpstreamVectors(
      { model: 'm', data: [{ ...row([1, 2]), index: 0 }, { ...row([3, 4]), index: 1 }] },
      2,
      0,
    );
    assert.equal(read.model, 'm');
    assert.equal(read.dimension, 2);
    assert.deepEqual(read.vectors, [[1, 2], [3, 4]]);
  });

  it('re-orders rows by index, because the protocol allows them shuffled', () => {
    const read = readUpstreamVectors(
      { model: 'm', data: [{ ...row([3, 4]), index: 1 }, { ...row([1, 2]), index: 0 }] },
      2,
      0,
    );
    assert.deepEqual(read.vectors, [[1, 2], [3, 4]]);
  });

  it('rejects a response with the wrong number of vectors', () => {
    assert.throws(
      () => readUpstreamVectors({ data: [{ ...row([1, 2]), index: 0 }] }, 2, 0),
      EmbedRequestError,
    );
  });

  it('rejects duplicate indexes rather than losing a row', () => {
    assert.throws(
      () => readUpstreamVectors(
        { data: [{ ...row([1, 2]), index: 0 }, { ...row([3, 4]), index: 0 }] },
        2,
        0,
      ),
      EmbedRequestError,
    );
  });

  it('rejects a malformed row', () => {
    assert.throws(
      () => readUpstreamVectors({ data: [{ index: 0, embedding: [] }] }, 1, 0),
      EmbedRequestError,
    );
    assert.throws(
      () => readUpstreamVectors({ data: [{ index: 0, embedding: [1, 'x'] }] }, 1, 0),
      EmbedRequestError,
    );
    assert.throws(
      () => readUpstreamVectors({ data: [{ index: 0, embedding: [1, NaN] }] }, 1, 0),
      EmbedRequestError,
    );
  });

  it('rejects vectors of inconsistent width', () => {
    assert.throws(
      () => readUpstreamVectors(
        { data: [{ ...row([1, 2]), index: 0 }, { ...row([1, 2, 3]), index: 1 }] },
        2,
        0,
      ),
      EmbedRequestError,
    );
  });

  it('rejects a width that contradicts the configured dimension', () => {
    assert.throws(
      () => readUpstreamVectors({ data: [{ ...row([1, 2, 3]), index: 0 }] }, 1, 8),
      EmbedRequestError,
    );
    const read = readUpstreamVectors({ data: [{ ...row([1, 2, 3]), index: 0 }] }, 1, 3);
    assert.equal(read.dimension, 3);
  });

  it('rejects a body without a data array', () => {
    assert.throws(() => readUpstreamVectors({}, 1, 0), EmbedRequestError);
    assert.throws(() => readUpstreamVectors(null, 1, 0), EmbedRequestError);
    assert.throws(() => readUpstreamVectors({ data: 'x' }, 1, 0), EmbedRequestError);
  });
});

describe('chat.buildUpstreamChatBody', () => {
  const config = baseConfig({ chatModel: 'server-chosen' });

  it('replaces the client model with the server choice', () => {
    const body = buildUpstreamChatBody({ model: 'client-chosen', messages: [] }, config);
    assert.equal(body.model, 'server-chosen');
  });

  it('forwards the fields the app legitimately uses', () => {
    const body = buildUpstreamChatBody({
      messages: [{ role: 'user', content: 'hi' }],
      stream: true,
      temperature: 0.7,
      max_tokens: 4096,
      tools: [{ type: 'function' }],
      tool_choice: 'auto',
    }, config);
    assert.equal(body.stream, true);
    assert.equal(body.temperature, 0.7);
    assert.equal(body.max_tokens, 4096);
    assert.deepEqual(body.tools, [{ type: 'function' }]);
    assert.equal(body.tool_choice, 'auto');
    assert.equal(body.messages.length, 1);
  });

  it('drops unknown fields instead of smuggling them upstream', () => {
    const body = buildUpstreamChatBody({ messages: [], evil: 'x', api_key: 'y' }, config);
    assert.equal(body.evil, undefined);
    assert.equal(body.api_key, undefined);
  });
});

describe('upstream status mapping', () => {
  it('passes actionable 4xx through unchanged', () => {
    assert.equal(statusForApp(400), 400);
    assert.equal(statusForApp(401), 401);
    assert.equal(statusForApp(402), 402);
    assert.equal(statusForApp(429), 429);
  });

  it('turns any upstream 5xx into 502', () => {
    assert.equal(statusForApp(500), 502);
    assert.equal(statusForApp(503), 502);
  });

  it('names each status for the client', () => {
    assert.equal(codeForStatus(401), 'unauthorized');
    assert.equal(codeForStatus(402), 'payment_required');
    assert.equal(codeForStatus(429), 'rate_limited');
    assert.equal(codeForStatus(502), 'upstream_error');
    assert.equal(codeForStatus(999), 'error');
  });
});

describe('upstream.combineSignals', () => {
  it('returns undefined when there is nothing to combine', () => {
    assert.equal(combineSignals([undefined, null]), undefined);
  });

  it('passes a single signal straight through', () => {
    const controller = new AbortController();
    assert.equal(combineSignals([controller.signal]), controller.signal);
  });

  it('aborts the merged signal when any input aborts', () => {
    const first = new AbortController();
    const second = new AbortController();
    const merged = combineSignals([first.signal, second.signal]);
    assert.equal(merged.aborted, false);
    second.abort();
    assert.equal(merged.aborted, true);
  });

  it('is already aborted when an input arrives aborted', () => {
    const first = new AbortController();
    first.abort();
    const merged = combineSignals([first.signal, new AbortController().signal]);
    assert.equal(merged.aborted, true);
  });
});

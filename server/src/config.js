/*
 * Server configuration, read from the environment.
 *
 * Two upstreams are involved and they are deliberately independent: chat goes
 * to a reasoning model, embeddings go to whatever vector model the team picks.
 * Nothing here shares a key between them, so a leak or a balance problem on one
 * side cannot take the other down.
 *
 * **This file is the only place a vendor credential is allowed to exist.** The
 * app that talks to this server carries no vendor key at all — see the client's
 * AiBackend for the other half of that arrangement.
 */

/** Where the app's own session token comes from, when auth is on. */
export const TOKEN_HEADER = 'x-app-token';

export const DEFAULT_PORT = 8787;
export const DEFAULT_CHAT_BASE_URL = 'https://api.deepseek.com/v1';
export const DEFAULT_CHAT_MODEL = 'deepseek-flash';
export const DEFAULT_EMBEDDING_BASE_URL = 'https://dashscope.aliyuncs.com/compatible-mode/v1';
export const DEFAULT_EMBEDDING_MODEL = 'text-embedding-v3';
export const DEFAULT_EMBEDDING_BATCH_SIZE = 10;
export const DEFAULT_RATE_LIMIT_PER_MINUTE = 120;
export const DEFAULT_UPSTREAM_TIMEOUT_MS = 60000;

/** Request-body ceiling. The client's largest legitimate embed batch is ~62 k chars. */
export const MAX_BODY_BYTES = 1024 * 1024;
/** One embed call may carry at most this many inputs (the shipped corpus is 241). */
export const MAX_EMBED_INPUTS = 512;
/** Per-input ceiling, and the ceiling for the whole batch. */
export const MAX_EMBED_INPUT_CHARS = 4000;
export const MAX_EMBED_TOTAL_CHARS = 200000;
/** Chat is a conversation, not a document dump. */
export const MAX_CHAT_MESSAGES = 64;
export const MAX_CHAT_MESSAGE_CHARS = 32000;

function readString(env, name, fallback) {
  const raw = env[name];
  if (typeof raw !== 'string') {
    return fallback;
  }
  const trimmed = raw.trim();
  return trimmed.length > 0 ? trimmed : fallback;
}

function readInt(env, name, fallback, min, max) {
  const raw = readString(env, name, '');
  if (raw.length === 0) {
    return fallback;
  }
  const value = Number.parseInt(raw, 10);
  if (!Number.isFinite(value) || value < min || value > max) {
    return fallback;
  }
  return value;
}

/**
 * Drops trailing slashes so `base + '/embeddings'` never doubles up. An empty
 * input stays empty, which `configured()` then reads as "not configured".
 */
export function normalizeBaseUrl(url) {
  if (typeof url !== 'string') {
    return '';
  }
  let trimmed = url.trim();
  while (trimmed.length > 0 && trimmed.charAt(trimmed.length - 1) === '/') {
    trimmed = trimmed.substring(0, trimmed.length - 1);
  }
  return trimmed;
}

export class ServerConfig {
  constructor(fields) {
    this.port = fields.port;
    this.appToken = fields.appToken;
    this.chatBaseUrl = fields.chatBaseUrl;
    this.chatApiKey = fields.chatApiKey;
    this.chatModel = fields.chatModel;
    this.embeddingBaseUrl = fields.embeddingBaseUrl;
    this.embeddingApiKey = fields.embeddingApiKey;
    this.embeddingModel = fields.embeddingModel;
    this.embeddingDimension = fields.embeddingDimension;
    this.embeddingBatchSize = fields.embeddingBatchSize;
    this.rateLimitPerMinute = fields.rateLimitPerMinute;
    this.upstreamTimeoutMs = fields.upstreamTimeoutMs;
  }

  chatConfigured() {
    return this.chatApiKey.length > 0 && this.chatBaseUrl.length > 0;
  }

  embeddingConfigured() {
    return this.embeddingApiKey.length > 0 && this.embeddingBaseUrl.length > 0;
  }

  /**
   * An unset token turns auth off. That is only sane for a loopback demo, so
   * `index.js` shouts about it at startup rather than failing silently.
   */
  authRequired() {
    return this.appToken.length > 0;
  }

  /**
   * The public shape of this server, as served by GET /health.
   *
   * Deliberately excludes the upstream base URLs: it answers "can this server
   * do the job" without telling an unauthenticated caller which vendor is
   * behind it. Keys are never part of any response, here or anywhere else.
   */
  describe() {
    return {
      ok: true,
      authRequired: this.authRequired(),
      chat: {
        configured: this.chatConfigured(),
        model: this.chatModel,
      },
      embedding: {
        configured: this.embeddingConfigured(),
        model: this.embeddingModel,
        dimension: this.embeddingDimension,
        batchSize: this.embeddingBatchSize,
      },
      rateLimitPerMinute: this.rateLimitPerMinute,
    };
  }
}

export function loadConfig(env = process.env) {
  return new ServerConfig({
    port: readInt(env, 'PORT', DEFAULT_PORT, 0, 65535),
    appToken: readString(env, 'APP_TOKEN', ''),
    chatBaseUrl: normalizeBaseUrl(readString(env, 'CHAT_BASE_URL', DEFAULT_CHAT_BASE_URL)),
    chatApiKey: readString(env, 'CHAT_API_KEY', ''),
    chatModel: readString(env, 'CHAT_MODEL', DEFAULT_CHAT_MODEL),
    embeddingBaseUrl: normalizeBaseUrl(readString(env, 'EMBEDDING_BASE_URL', DEFAULT_EMBEDDING_BASE_URL)),
    embeddingApiKey: readString(env, 'EMBEDDING_API_KEY', ''),
    embeddingModel: readString(env, 'EMBEDDING_MODEL', DEFAULT_EMBEDDING_MODEL),
    embeddingDimension: readInt(env, 'EMBEDDING_DIMENSION', 0, 0, 8192),
    embeddingBatchSize: readInt(env, 'EMBEDDING_BATCH_SIZE', DEFAULT_EMBEDDING_BATCH_SIZE, 1, 128),
    rateLimitPerMinute: readInt(env, 'RATE_LIMIT_PER_MINUTE', DEFAULT_RATE_LIMIT_PER_MINUTE, 0, 100000),
    upstreamTimeoutMs: readInt(env, 'UPSTREAM_TIMEOUT_MS', DEFAULT_UPSTREAM_TIMEOUT_MS, 1000, 600000),
  });
}

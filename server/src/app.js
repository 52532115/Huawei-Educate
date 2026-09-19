/*
 * Request routing.
 *
 * Order of operations per request, and why:
 *
 *   1. rate limit   — cheapest check, and it runs before anything touches the
 *                     vendor account, so a flood cannot burn quota.
 *   2. auth         — the app token, compared in constant time.
 *   3. handler      — embed or chat, both of which hold vendor credentials.
 *   4. audit        — one line per request, always, success or failure.
 *
 * Nothing here logs a request body or a message. A request id ties the audit
 * line to the handler's own warnings so a failure is traceable without ever
 * recording what a student asked.
 */

import { createServer } from 'node:http';
import { randomUUID } from 'node:crypto';
import { BodyError, clientKeyOf, sendError, sendJson } from './http.js';
import { RateLimiter, extractToken, tokenMatches } from './guard.js';
import { UpstreamClient } from './upstream.js';
import { createEmbedHandler } from './embed.js';
import { CHAT_PATH, createChatHandler } from './chat.js';
import { audit, logger } from './log.js';

export const HEALTH_PATH = '/health';
export const EMBED_PATH = '/embed';

/**
 * Chat is reachable at the OpenAI path so a standard client works unchanged,
 * plus a short alias for curl and for the app's own configuration.
 */
const CHAT_PATHS = ['/chat/completions', '/v1/chat/completions', '/chat'];

function normalizePath(pathname) {
  if (pathname.length > 1 && pathname.charAt(pathname.length - 1) === '/') {
    return pathname.substring(0, pathname.length - 1);
  }
  return pathname;
}

export function isChatPath(pathname) {
  for (const candidate of CHAT_PATHS) {
    if (pathname === candidate) {
      return true;
    }
  }
  return false;
}

function buildUpstream(config, kind, fetchImpl) {
  if (kind === 'embedding') {
    return new UpstreamClient({
      baseUrl: config.embeddingBaseUrl,
      apiKey: config.embeddingApiKey,
      timeoutMs: config.upstreamTimeoutMs,
      fetchImpl,
    });
  }
  return new UpstreamClient({
    baseUrl: config.chatBaseUrl,
    apiKey: config.chatApiKey,
    timeoutMs: config.upstreamTimeoutMs,
    fetchImpl,
  });
}

/**
 * Builds the HTTP server without listening, so tests can bind an ephemeral port
 * and drive the real routing, auth and handlers rather than a simulation of
 * them. `fetchImpl` is injectable for the one failure mode a local stub cannot
 * produce: a transport error.
 */
export function createApp(config, options = {}) {
  const fetchImpl = options.fetchImpl;
  const embeddingUpstream = options.embeddingUpstream
    || buildUpstream(config, 'embedding', fetchImpl);
  const chatUpstream = options.chatUpstream || buildUpstream(config, 'chat', fetchImpl);
  const limiter = options.limiter || new RateLimiter(config.rateLimitPerMinute);

  const handleEmbed = createEmbedHandler({ config, upstream: embeddingUpstream });
  const handleChat = createChatHandler({ config, upstream: chatUpstream });

  const server = createServer(async (req, res) => {
    const requestId = randomUUID();
    const startedAt = Date.now();
    const client = clientKeyOf(req);
    let status = 500;
    let pathname = '/';

    res.setHeader('x-request-id', requestId);

    // A response that closes before it finished means the caller went away.
    // Aborting on that is what stops a cancelled question from continuing to
    // generate — and continuing to be billed — on the vendor side.
    const controller = new AbortController();
    res.on('close', () => {
      if (!res.writableFinished) {
        controller.abort();
      }
    });
    // A socket that dies mid-write raises on the response stream. There is
    // nothing to recover — the caller is gone — but an unhandled error here
    // would take the whole process down with it, including every other
    // learner's in-flight request.
    res.on('error', () => {
      controller.abort();
    });

    try {
      pathname = normalizePath(new URL(req.url, 'http://localhost').pathname);

      if (pathname === HEALTH_PATH) {
        if (req.method !== 'GET' && req.method !== 'HEAD') {
          status = 405;
          sendError(res, 405, 'method_not_allowed', '请使用 GET');
        } else {
          status = 200;
          sendJson(res, 200, config.describe());
        }
        return;
      }

      const limit = limiter.check(client);
      if (!limit.allowed) {
        status = 429;
        logger.warn('rate limit exceeded', { requestId, client, path: pathname });
        sendError(res, 429, 'rate_limited', '请求过于频繁，请稍后再试', {
          headers: { 'Retry-After': String(limit.retryAfterSeconds) },
        });
        return;
      }

      if (config.authRequired() && !tokenMatches(extractToken(req), config.appToken)) {
        status = 401;
        logger.warn('rejected an unauthorized request', {
          requestId,
          client,
          path: pathname,
        });
        sendError(res, 401, 'unauthorized', '应用令牌无效或缺失');
        return;
      }

      if (req.method !== 'POST') {
        status = 405;
        sendError(res, 405, 'method_not_allowed', '请使用 POST');
        return;
      }

      const ctx = { requestId, signal: controller.signal, client };
      if (pathname === EMBED_PATH) {
        status = await handleEmbed(req, res, ctx);
        return;
      }
      if (isChatPath(pathname)) {
        status = await handleChat(req, res, ctx);
        return;
      }
      status = 404;
      sendError(res, 404, 'not_found', '没有这个接口');
    } catch (error) {
      if (error instanceof BodyError) {
        status = error.status;
        if (!res.headersSent) {
          sendError(res, error.status, error.code, error.message);
        }
      } else {
        status = 500;
        logger.error('unhandled failure', {
          requestId,
          path: pathname,
          detail: error && error.message,
        });
        if (!res.headersSent) {
          sendError(res, 500, 'internal_error', '服务器内部错误');
        }
      }
      if (!res.writableEnded) {
        res.end();
      }
    } finally {
      audit({
        requestId,
        method: req.method,
        path: pathname,
        status,
        ms: Date.now() - startedAt,
        client,
      });
    }
  });

  return { server, config, limiter, embeddingUpstream, chatUpstream };
}

/*
 * POST /chat/completions — the chat relay.
 *
 * The app already speaks the OpenAI chat protocol, so this endpoint is a
 * transparent relay: same request shape in, same response shape out, `stream`
 * included. That is the whole point of moving chat here — the fix for
 * AI-SEC-001 must not also become a rewrite of the client's streaming and
 * tool-calling code.
 *
 * Two details carry the weight:
 *
 * 1. **Status before headers.** The upstream answer is inspected before any SSE
 *    header goes out. Once `text/event-stream` has been written there is no way
 *    to turn a failure into a JSON error the client can read, so a 402 from the
 *    vendor would reach the app as an empty stream instead of an explanation.
 *
 * 2. **Disconnect propagation.** When the app cancels a question, this request
 *    is aborted and the upstream call is aborted with it. Tokens already spent
 *    are spent, but a cancelled answer must not keep generating.
 */

import { MAX_BODY_BYTES, MAX_CHAT_MESSAGES, MAX_CHAT_MESSAGE_CHARS } from './config.js';
import { BodyError, readJsonBody, sendError, sendJson, writeChunk } from './http.js';
import { TRANSPORT_TIMEOUT, codeForStatus, statusForApp } from './upstream.js';
import { logger } from './log.js';

export const CHAT_PATH = '/chat/completions';

/**
 * Fields the app is allowed to pass through.
 *
 * A whitelist rather than a passthrough, so a client cannot smuggle unknown
 * parameters into a request that carries the server's vendor key.
 */
const FORWARDED_FIELDS = [
  'messages',
  'stream',
  'temperature',
  'max_tokens',
  'top_p',
  'stop',
  'frequency_penalty',
  'presence_penalty',
  'response_format',
  'tools',
  'tool_choice',
];

export class ChatRequestError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

function checkMessages(messages) {
  if (!Array.isArray(messages) || messages.length === 0) {
    throw new ChatRequestError('bad_request', 'messages 必须是非空数组');
  }
  if (messages.length > MAX_CHAT_MESSAGES) {
    throw new ChatRequestError('bad_request', `messages 最多 ${MAX_CHAT_MESSAGES} 条`);
  }
  for (let i = 0; i < messages.length; i++) {
    const message = messages[i];
    if (!message || typeof message !== 'object' || Array.isArray(message)) {
      throw new ChatRequestError('bad_request', `messages[${i}] 不是对象`);
    }
    if (typeof message.role !== 'string' || message.role.length === 0) {
      throw new ChatRequestError('bad_request', `messages[${i}] 缺少 role`);
    }
    if (typeof message.content === 'string' && message.content.length > MAX_CHAT_MESSAGE_CHARS) {
      throw new ChatRequestError('bad_request', `messages[${i}].content 过长`);
    }
  }
}

/**
 * Builds the upstream body: the whitelisted fields, with the model replaced by
 * the server's choice. The app is not trusted to pick the model — that is the
 * server operator's decision, and it is exactly the kind of thing a client
 * build would otherwise hard-code.
 */
export function buildUpstreamChatBody(body, config) {
  const upstreamBody = { model: config.chatModel };
  for (const field of FORWARDED_FIELDS) {
    if (body[field] !== undefined) {
      upstreamBody[field] = body[field];
    }
  }
  // The thinking switch is set by the SERVER, never forwarded from the client.
  // Two reasons, both deliberate: the field names are vendor dialects rather
  // than OpenAI ones (letting the app send them would make our wire format a
  // vendor dialect), and turning thinking on or off changes what a request
  // costs — the same class of decision as `model`, which is overwritten above
  // for the same reason.
  //
  // An empty object means "send nothing at all". Both spellings are written
  // *after* the whitelist loop and are absent from FORWARDED_FIELDS, so a
  // client that sends them anyway cannot win: the server's value lands last.
  const thinkingFields = config.chatThinkingFields ? config.chatThinkingFields() : {};
  for (const field of Object.keys(thinkingFields)) {
    upstreamBody[field] = thinkingFields[field];
  }
  return upstreamBody;
}

export function createChatHandler({ config, upstream }) {
  return async function handleChat(req, res, ctx) {
    let body;
    try {
      body = await readJsonBody(req, MAX_BODY_BYTES);
    } catch (error) {
      if (error instanceof BodyError) {
        sendError(res, error.status, error.code, error.message);
        return error.status;
      }
      throw error;
    }
    if (!body || typeof body !== 'object' || Array.isArray(body)) {
      sendError(res, 400, 'bad_request', '请求体必须是 JSON 对象');
      return 400;
    }
    try {
      checkMessages(body.messages);
    } catch (error) {
      const code = error instanceof ChatRequestError ? error.code : 'bad_request';
      sendError(res, 400, code, error.message);
      return 400;
    }

    if (!upstream.configured()) {
      sendError(res, 503, 'unavailable', '服务端未配置对话模型密钥');
      return 503;
    }

    const upstreamBody = buildUpstreamChatBody(body, config);
    if (body.stream === true) {
      return await relayStream(req, res, ctx, upstream, upstreamBody);
    }
    return await relayBuffered(req, res, ctx, upstream, upstreamBody);
  };
}

/**
 * Turns an upstream failure into this server's answer. `upstreamStatus` is
 * included deliberately: it is the field that makes "the account is out of
 * balance" distinguishable from "we are broken", both to the app and in the
 * audit log.
 */
function reportUpstreamFailure(res, ctx, status, text, requestId) {
  const mapped = statusForApp(status);
  logger.warn('chat upstream rejected the request', {
    requestId,
    upstreamStatus: status,
    excerpt: typeof text === 'string' ? text.substring(0, 300) : '',
  });
  sendError(res, mapped, codeForStatus(mapped), '对话服务拒绝了请求', {
    details: { upstreamStatus: status },
  });
  return mapped;
}

function reportTransportFailure(res, ctx, error, requestId) {
  const timeout = error && error.code === TRANSPORT_TIMEOUT;
  const status = timeout ? 504 : 502;
  logger.warn('chat upstream transport failure', {
    requestId,
    code: error && error.code,
    detail: error && error.message,
  });
  sendError(res, status, codeForStatus(status), '无法连接对话服务');
  return status;
}

async function relayBuffered(req, res, ctx, upstream, upstreamBody) {
  let answer;
  try {
    answer = await upstream.postJson(CHAT_PATH, upstreamBody, { signal: ctx.signal });
  } catch (error) {
    return reportTransportFailure(res, ctx, error, ctx.requestId);
  }
  if (answer.status < 200 || answer.status >= 300) {
    return reportUpstreamFailure(res, ctx, answer.status, answer.text, ctx.requestId);
  }
  if (!answer.json) {
    logger.warn('chat upstream returned an unparseable body', { requestId: ctx.requestId });
    sendError(res, 502, 'upstream_error', '对话服务返回的数据无法解析');
    return 502;
  }
  sendJson(res, 200, answer.json);
  return 200;
}

async function relayStream(req, res, ctx, upstream, upstreamBody) {
  let answer;
  try {
    answer = await upstream.openStream(CHAT_PATH, upstreamBody, { signal: ctx.signal });
  } catch (error) {
    return reportTransportFailure(res, ctx, error, ctx.requestId);
  }

  if (answer.status < 200 || answer.status >= 300) {
    const text = await answer.text();
    return reportUpstreamFailure(res, ctx, answer.status, text, ctx.requestId);
  }
  if (!answer.body) {
    logger.warn('chat upstream returned an empty stream', { requestId: ctx.requestId });
    sendError(res, 502, 'upstream_error', '对话服务返回了空响应');
    return 502;
  }

  res.writeHead(200, {
    'Content-Type': 'text/event-stream; charset=utf-8',
    'Cache-Control': 'no-cache, no-transform',
    'Connection': 'keep-alive',
    'X-Accel-Buffering': 'no',
  });
  // Send the headers now rather than with the first delta, so the app's
  // streaming request resolves instead of waiting on the model's first token.
  res.flushHeaders();

  const reader = answer.body.getReader();
  let bytes = 0;
  try {
    for (;;) {
      const step = await reader.read();
      if (step.done) {
        break;
      }
      bytes += step.value.length;
      const alive = await writeChunk(res, Buffer.from(step.value));
      if (!alive) {
        logger.info('chat client disconnected mid-stream', { requestId: ctx.requestId, bytes });
        return 499;
      }
    }
  } catch (error) {
    // An aborted upstream read surfaces here; a client that has already gone
    // is the expected cause, so this is not an error worth reporting.
    if (!ctx.signal.aborted) {
      logger.warn('chat stream interrupted', {
        requestId: ctx.requestId,
        detail: error && error.message,
      });
    }
  } finally {
    try {
      await reader.cancel();
    } catch (e) {
      // The reader is already gone; nothing to release.
    }
    if (!res.writableEnded) {
      res.end();
    }
  }
  return 200;
}

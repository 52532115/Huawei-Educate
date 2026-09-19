/*
 * POST /embed — the endpoint the app's KnowledgeEmbeddingProxy calls.
 *
 * Contract (unchanged from what the client already implements, so the device
 * side needed no protocol work):
 *
 *   POST /embed            Authorization: Bearer <app session token>
 *   { "model": "", "inputs": ["…", "…"] }
 *   200 { "model": "text-embedding-v3", "dimension": 1024, "vectors": [[…], […]] }
 *
 * The `model` field is advisory — an empty or absent value means "use whatever
 * this server is configured with". The app sends empty on purpose: the choice
 * of embedding model belongs to whoever operates the server, not to a client
 * build that would then have to be re-released to change it.
 *
 * Vectors are positional, so every failure mode here is all-or-nothing. Padding
 * a short response or dropping a failed batch would silently shift every later
 * vector onto the wrong chunk, and retrieval would return confidently wrong
 * passages — worse than losing the vector signal entirely.
 */

import {
  MAX_BODY_BYTES,
  MAX_EMBED_INPUTS,
  MAX_EMBED_INPUT_CHARS,
  MAX_EMBED_TOTAL_CHARS,
} from './config.js';
import { BodyError, readJsonBody, sendError, sendJson } from './http.js';
import { TRANSPORT_TIMEOUT, codeForStatus, statusForApp } from './upstream.js';
import { logger } from './log.js';

export const EMBEDDINGS_PATH = '/embeddings';

export class EmbedRequestError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

/**
 * Pulls the texts out of a request body.
 *
 * Accepts OpenAI's `input` as well as our `inputs` so the endpoint can be
 * exercised with any standard OpenAI client or a plain curl call.
 */
export function collectInputs(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    throw new EmbedRequestError('bad_request', '请求体必须是 JSON 对象');
  }
  let raw = body.inputs;
  if (raw === undefined) {
    raw = body.input;
  }
  if (typeof raw === 'string') {
    raw = [raw];
  }
  if (!Array.isArray(raw) || raw.length === 0) {
    throw new EmbedRequestError('bad_request', 'inputs 必须是非空的字符串数组');
  }
  if (raw.length > MAX_EMBED_INPUTS) {
    throw new EmbedRequestError('bad_request', `inputs 最多 ${MAX_EMBED_INPUTS} 条`);
  }

  const inputs = [];
  let totalChars = 0;
  for (let i = 0; i < raw.length; i++) {
    const item = raw[i];
    if (typeof item !== 'string') {
      throw new EmbedRequestError('bad_request', `inputs[${i}] 不是字符串`);
    }
    if (item.length > MAX_EMBED_INPUT_CHARS) {
      throw new EmbedRequestError('bad_request', `inputs[${i}] 超过 ${MAX_EMBED_INPUT_CHARS} 字符`);
    }
    totalChars += item.length;
    if (totalChars > MAX_EMBED_TOTAL_CHARS) {
      throw new EmbedRequestError('bad_request', `inputs 总长度超过 ${MAX_EMBED_TOTAL_CHARS} 字符`);
    }
    inputs.push(item);
  }
  return inputs;
}

/** Splits inputs into provider-sized batches, preserving order. */
export function chunkInputs(inputs, batchSize) {
  const size = Number.isFinite(batchSize) && batchSize > 0 ? Math.floor(batchSize) : inputs.length;
  const batches = [];
  for (let start = 0; start < inputs.length; start += size) {
    batches.push(inputs.slice(start, start + size));
  }
  return batches;
}

function isNumberRow(row) {
  if (!Array.isArray(row) || row.length === 0) {
    return false;
  }
  for (let i = 0; i < row.length; i++) {
    if (typeof row[i] !== 'number' || !Number.isFinite(row[i])) {
      return false;
    }
  }
  return true;
}

/**
 * Reads the vectors out of an OpenAI-shaped embeddings response.
 *
 * Rows are re-ordered by their `index` when present — the protocol allows them
 * to arrive out of order, and getting that wrong is another silent misalignment.
 */
export function readUpstreamVectors(json, expectedCount, expectedDimension) {
  if (!json || typeof json !== 'object') {
    throw new EmbedRequestError('upstream_error', '上游返回的不是 JSON 对象');
  }
  const data = json.data;
  if (!Array.isArray(data)) {
    throw new EmbedRequestError('upstream_error', '上游返回缺少 data 数组');
  }
  if (data.length !== expectedCount) {
    throw new EmbedRequestError(
      'upstream_error',
      `上游返回 ${data.length} 条向量，期望 ${expectedCount} 条`,
    );
  }

  const ordered = new Array(expectedCount);
  for (let i = 0; i < data.length; i++) {
    const item = data[i];
    if (!item || typeof item !== 'object' || !isNumberRow(item.embedding)) {
      throw new EmbedRequestError('upstream_error', `上游第 ${i} 条向量格式不正确`);
    }
    const index = Number.isInteger(item.index) && item.index >= 0 && item.index < expectedCount
      ? item.index
      : i;
    ordered[index] = item.embedding;
  }

  let dimension = 0;
  for (let i = 0; i < ordered.length; i++) {
    if (!ordered[i]) {
      throw new EmbedRequestError('upstream_error', '上游返回的 index 有缺失或重复');
    }
    if (dimension === 0) {
      dimension = ordered[i].length;
    } else if (ordered[i].length !== dimension) {
      throw new EmbedRequestError('upstream_error', '上游返回的向量维度不一致');
    }
  }
  if (expectedDimension > 0 && dimension !== expectedDimension) {
    throw new EmbedRequestError(
      'upstream_error',
      `上游返回维度 ${dimension}，与配置的 ${expectedDimension} 不一致`,
    );
  }
  const model = typeof json.model === 'string' ? json.model : '';
  return { vectors: ordered, dimension, model };
}

function buildUpstreamBody(model, chunk, dimension) {
  const body = { model, input: chunk };
  if (dimension > 0) {
    body.dimensions = dimension;
  }
  return body;
}

export function createEmbedHandler({ config, upstream }) {
  return async function handleEmbed(req, res, ctx) {
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

    let inputs;
    try {
      inputs = collectInputs(body);
    } catch (error) {
      const code = error instanceof EmbedRequestError ? error.code : 'bad_request';
      sendError(res, 400, code, error.message);
      return 400;
    }

    if (!upstream.configured()) {
      sendError(res, 503, 'unavailable', '服务端未配置嵌入模型密钥');
      return 503;
    }

    const requestedModel = typeof body.model === 'string' && body.model.trim().length > 0
      ? body.model.trim()
      : config.embeddingModel;

    const batches = chunkInputs(inputs, config.embeddingBatchSize);
    const vectors = [];
    let reportedModel = requestedModel;

    for (let b = 0; b < batches.length; b++) {
      const batch = batches[b];
      let answer;
      try {
        answer = await upstream.postJson(
          EMBEDDINGS_PATH,
          buildUpstreamBody(requestedModel, batch, config.embeddingDimension),
          { signal: ctx.signal },
        );
      } catch (error) {
        const timeout = error && error.code === TRANSPORT_TIMEOUT;
        const status = timeout ? 504 : 502;
        logger.warn('embed upstream transport failure', {
          requestId: ctx.requestId,
          code: error && error.code,
          detail: error && error.message,
          batch: b,
        });
        sendError(res, status, codeForStatus(status), '无法连接嵌入服务');
        return status;
      }

      if (answer.status < 200 || answer.status >= 300) {
        const status = statusForApp(answer.status);
        logger.warn('embed upstream rejected the request', {
          requestId: ctx.requestId,
          upstreamStatus: answer.status,
          limit: limitExcerpt(answer.text),
        });
        sendError(res, status, codeForStatus(status), '嵌入服务拒绝了请求', {
          details: { upstreamStatus: answer.status },
        });
        return status;
      }

      let read;
      try {
        read = readUpstreamVectors(answer.json, batch.length, config.embeddingDimension);
      } catch (error) {
        const code = error instanceof EmbedRequestError ? error.code : 'upstream_error';
        logger.warn('embed upstream payload failed validation', {
          requestId: ctx.requestId,
          detail: error.message,
          batch: b,
        });
        sendError(res, 502, code, '嵌入服务返回的数据不完整');
        return 502;
      }

      if (read.model.length > 0) {
        reportedModel = read.model;
      } else if (reportedModel.length === 0) {
        reportedModel = config.embeddingModel;
      }
      for (let i = 0; i < read.vectors.length; i++) {
        vectors.push(read.vectors[i]);
      }
    }

    if (vectors.length !== inputs.length) {
      sendError(res, 502, 'upstream_error', '嵌入结果条数与输入不符');
      return 502;
    }

    sendJson(res, 200, {
      model: reportedModel,
      dimension: vectors.length > 0 ? vectors[0].length : 0,
      vectors,
    });
    return 200;
  };
}

/** Truncates an upstream error body for the log; never logs request content. */
function limitExcerpt(text) {
  if (typeof text !== 'string') {
    return '';
  }
  return text.length > 300 ? text.substring(0, 300) : text;
}

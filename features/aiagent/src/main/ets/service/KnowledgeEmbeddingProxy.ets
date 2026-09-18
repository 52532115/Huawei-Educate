/*
 * Copyright (c) 2025 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 */

import { http } from '@kit.NetworkKit';
import { KnowledgeEmbeddingBatch } from './KnowledgeEmbedding';
import { Logger } from '@safe/basic';

/**
 * AppStorage key holding the proxy base URL, e.g. `https://api.example.edu/rag`.
 * Set by the same settings surface that holds the chat API key.
 */
export const EMBEDDING_PROXY_KEY = 'aiEmbeddingProxyUrl';
export const EMBEDDING_PROXY_PATH = '/embed';
export const EMBEDDING_PROXY_TIMEOUT_MS = 8000;

const RESPONSE_CODE_OK = 200;

/**
 * The proxy contract.
 *
 * ```
 * POST {base}/embed
 * Authorization: Bearer <app session token>      // optional, app's own auth
 * Content-Type: application/json
 *
 * { "model": "bge-large-zh", "inputs": ["三次握手", "…"] }
 *
 * 200 { "model": "bge-large-zh", "dimension": 1024,
 *       "vectors": [[…], […]] }                  // one vector per input, in order
 * 401/402/429/5xx → any non-200: the client falls back to BM25-only
 * ```
 *
 * **Why a proxy and not a direct vendor call.** The project's own test report
 * lists "API Key 完全运行时化" as a P0 concern: the chat key already lives in
 * client-side storage, and adding a second vendor key for embeddings would
 * repeat that exposure for a capability the learner never sees. So this client
 * carries **no vendor credential of any kind** — the key stays on a server that
 * the team operates, and the client sends only the texts to embed. The
 * `Authorization` header, when present, is the app's own session token, which
 * the proxy is free to ignore.
 *
 * This is also why the local hashed embedder exists: with no proxy configured
 * the app never calls out, and retrieval still works.
 */
export class KnowledgeEmbeddingProxy {
  private endpoint: string = '';
  private sessionToken: string = '';

  constructor(endpoint: string = '', sessionToken: string = '') {
    this.endpoint = KnowledgeEmbeddingProxy.normalize(endpoint);
    this.sessionToken = sessionToken;
  }

  /**
   * Reads the configured endpoint from AppStorage.
   *
   * Separate from the constructor because reading AppStorage is the one impure
   * thing here; keeping it out of construction means the class can be built and
   * tested without any app state.
   */
  static fromAppStorage(): KnowledgeEmbeddingProxy {
    let endpoint = '';
    try {
      endpoint = AppStorage.get<string>(EMBEDDING_PROXY_KEY) || '';
    } catch (e) {
      // AppStorage is absent in unit tests and during preview.
      endpoint = '';
    }
    return new KnowledgeEmbeddingProxy(endpoint);
  }

  private static normalize(endpoint: string): string {
    const trimmed = typeof endpoint === 'string' ? endpoint.trim() : '';
    if (trimmed.length === 0) {
      return '';
    }
    return trimmed.charAt(trimmed.length - 1) === '/'
      ? trimmed.substring(0, trimmed.length - 1)
      : trimmed;
  }

  /** True only when a base URL has been configured. */
  isConfigured(): boolean {
    return this.endpoint.length > 0;
  }

  url(): string {
    return this.endpoint + EMBEDDING_PROXY_PATH;
  }

  private buildHeaders(): Record<string, string> {
    const headers: Record<string, string> = {};
    headers['Content-Type'] = 'application/json';
    if (this.sessionToken.length > 0) {
      headers['Authorization'] = `Bearer ${this.sessionToken}`;
    }
    return headers;
  }

  /**
   * Embeds a batch, or returns null.
   *
   * Null covers every failure — not configured, transport error, non-200,
   * malformed payload, wrong vector count — because the caller's response to
   * all of them is identical: keep the lexical index and lose nothing. A
   * retrieval feature that can fail a question is worse than one that quietly
   * answers from the course notes.
   */
  async embed(texts: string[]): Promise<KnowledgeEmbeddingBatch | null> {
    if (!this.isConfigured() || !Array.isArray(texts) || texts.length === 0) {
      return null;
    }
    const request = http.createHttp();
    try {
      const body = JSON.stringify(buildRequestBody(texts));
      const response = await request.request(this.url(), {
        method: http.RequestMethod.POST,
        header: this.buildHeaders(),
        extraData: body,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: EMBEDDING_PROXY_TIMEOUT_MS,
        readTimeout: EMBEDDING_PROXY_TIMEOUT_MS,
      });
      if (response.responseCode !== RESPONSE_CODE_OK) {
        Logger.warn(`[EmbeddingProxy] non-200 response: ${response.responseCode}`);
        return null;
      }
      return parseEmbeddingResponse(response.result as string, texts.length);
    } catch (error) {
      const message = error instanceof Error ? error.message : 'unknown error';
      Logger.warn(`[EmbeddingProxy] embedding request failed: ${message}`);
      return null;
    } finally {
      request.destroy();
    }
  }
}

interface EmbeddingProxyRequestBody {
  model: string;
  inputs: string[];
}

interface EmbeddingProxyResponseBody {
  model: string;
  dimension: number;
  vectors: number[][];
}

/** The model name is advisory: the proxy owns the choice, the client just relays it. */
function buildRequestBody(texts: string[]): EmbeddingProxyRequestBody {
  return {
    model: '',
    inputs: texts,
  };
}

function hasOnlyNumbers(row: number[]): boolean {
  for (let i = 0; i < row.length; i++) {
    if (typeof row[i] !== 'number' || !Number.isFinite(row[i])) {
      return false;
    }
  }
  return true;
}

/**
 * Validates a proxy payload. A count mismatch is fatal rather than padded: the
 * vectors are positional, so one missing row would silently attach every later
 * embedding to the wrong chunk.
 */
export function parseEmbeddingResponse(raw: string, expectedCount: number): KnowledgeEmbeddingBatch | null {
  if (typeof raw !== 'string' || raw.length === 0) {
    return null;
  }
  let parsed: EmbeddingProxyResponseBody;
  try {
    parsed = JSON.parse(raw) as EmbeddingProxyResponseBody;
  } catch (e) {
    return null;
  }
  if (!parsed || !Array.isArray(parsed.vectors) || parsed.vectors.length !== expectedCount) {
    return null;
  }
  const batch = new KnowledgeEmbeddingBatch();
  batch.model = typeof parsed.model === 'string' ? parsed.model : '';
  for (let i = 0; i < parsed.vectors.length; i++) {
    const row = parsed.vectors[i];
    if (!Array.isArray(row) || row.length === 0 || !hasOnlyNumbers(row)) {
      return null;
    }
    if (batch.dimension === 0) {
      batch.dimension = row.length;
    } else if (row.length !== batch.dimension) {
      return null;
    }
    batch.vectors.push(row);
  }
  return batch;
}

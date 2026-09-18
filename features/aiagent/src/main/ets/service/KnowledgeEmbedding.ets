/*
 * Copyright (c) 2025 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 */

import { KnowledgeChunk } from '../viewmodel/KnowledgeModels';
import { tokenizeWithUnigrams } from './KnowledgeIndex';
import { hashString } from './KnowledgeSnapshotCodec';

/**
 * Width of the hashed vector. 256 keeps the quantised payload near 200 KB for
 * the shipped corpus; wider vectors buy very little once the features are
 * hashed rather than learned.
 */
export const EMBEDDING_DIMENSION = 256;

/** Identifies the local hashed embedder in cached snapshots and diagnostics. */
export const LOCAL_EMBEDDER_MODEL = 'local-hash-v1';

/** Probe for `signature()`; a change to either tokenizer must move the digest. */
const SIGNATURE_PROBE = '探测 三次握手 TCP/IP 的 2020';

/** Vectors are rounded like retrieval scores, so tests can compare them exactly. */
const SCORE_DECIMALS = 10000;

/** One batch of embeddings, from the local embedder or from the proxy. */
export class KnowledgeEmbeddingBatch {
  /** e.g. `local-hash-v1` or whatever the proxy reports. */
  model: string = '';
  dimension: number = 0;
  /** One vector per input text, in input order. */
  vectors: number[][] = [];
}

function round4(value: number): number {
  return Math.round(value * SCORE_DECIMALS) / SCORE_DECIMALS;
}

/**
 * The text that represents one chunk to the embedder.
 *
 * Route headings through here rather than letting each caller compose its own
 * string: a chunk whose heading names the topic must look different from one
 * that merely mentions it, and that only holds if the document side is built
 * the same way every time.
 */
export function documentTextFor(chunk: KnowledgeChunk): string {
  if (!chunk) {
    return '';
  }
  return `${chunk.headingPath}\n${chunk.title}\n${chunk.text}`;
}

/** Maps a term onto a vector slot. Hex parse, so it is exact and bit-free. */
export function hashToBucket(term: string, dimension: number): number {
  if (!Number.isFinite(dimension) || dimension <= 0) {
    return 0;
  }
  const digest = hashString(term);
  const value = parseInt(digest, 16);
  if (!Number.isFinite(value)) {
    return 0;
  }
  return value % dimension;
}

/** Scales a vector to unit length. A zero vector is returned unchanged. */
export function normalizeVector(vector: number[]): number[] {
  let sumOfSquares = 0;
  for (let i = 0; i < vector.length; i++) {
    sumOfSquares += vector[i] * vector[i];
  }
  if (sumOfSquares <= 0) {
    return vector;
  }
  const norm = Math.sqrt(sumOfSquares);
  const scaled: number[] = [];
  for (let i = 0; i < vector.length; i++) {
    scaled.push(round4(vector[i] / norm));
  }
  return scaled;
}

/**
 * Cosine similarity, 0 for anything uncomparable.
 *
 * Returning 0 on a length mismatch (rather than throwing) is deliberate: a
 * cached vector from a differently configured embedder must degrade to "no
 * vector signal", never break the search that is already working.
 */
/**
 * A deterministic, dependency-free embedder.
 *
 * It is a **hashed bag of terms**, not a learned model: it cannot bridge
 * synonyms the way a real embedding does. What it does give is a second, length
 * -normalised view of the same text — one that includes CJK unigrams, which the
 * BM25 side deliberately omits — so fusion can recover passages where the
 * bigram overlap alone was too thin.
 *
 * It exists for two reasons. It makes the vector path real, runnable and
 * testable today, with no network and no key; and it is the offline stand-in
 * for `KnowledgeEmbeddingProxy`, so the retriever, the fusion and the snapshot
 * format are all exercised before any server exists. When the proxy is
 * configured the vectors come from there instead and this class is unused.
 */
export class LocalHashingEmbedder {
  private dimension: number = EMBEDDING_DIMENSION;

  constructor(dimension: number = EMBEDDING_DIMENSION) {
    this.dimension = dimension > 0 ? dimension : EMBEDDING_DIMENSION;
  }

  getDimension(): number {
    return this.dimension;
  }

  model(): string {
    return LOCAL_EMBEDDER_MODEL;
  }

  /**
   * Pins everything that would invalidate a cached vector: the model name, the
   * width, and the tokenizer's behaviour on a fixed probe. Changing the
   * tokenizer without bumping anything is therefore detected, not trusted.
   */
  signature(): string {
    const probe = tokenizeWithUnigrams(SIGNATURE_PROBE);
    return `${LOCAL_EMBEDDER_MODEL}:${this.dimension}:${hashString(probe.join('|'))}`;
  }

  /**
   * Sublinear term frequency, hashed into `dimension` slots, L2-normalised.
   * Same text in, same vector out — the whole point of keeping it arithmetic.
   */
  embed(text: string): number[] {
    const vector: number[] = [];
    for (let i = 0; i < this.dimension; i++) {
      vector.push(0);
    }
    if (typeof text !== 'string' || text.length === 0) {
      return vector;
    }

    const tokens = tokenizeWithUnigrams(text);
    const counts = new Map<string, number>();
    for (let i = 0; i < tokens.length; i++) {
      const term = tokens[i];
      counts.set(term, (counts.get(term) || 0) + 1);
    }
    // Map iteration follows insertion order, so the accumulation order — and
    // therefore the rounding — is reproducible.
    counts.forEach((count: number, term: string) => {
      const bucket = hashToBucket(term, this.dimension);
      vector[bucket] = vector[bucket] + (1 + Math.log(count));
    });
    return normalizeVector(vector);
  }

  embedAll(texts: string[]): number[][] {
    const vectors: number[][] = [];
    if (!Array.isArray(texts)) {
      return vectors;
    }
    for (let i = 0; i < texts.length; i++) {
      vectors.push(this.embed(texts[i]));
    }
    return vectors;
  }
}

/**
 * Cosine similarity, 0 for anything uncomparable.
 *
 * Returning 0 on a length mismatch (rather than throwing) is deliberate: a
 * cached vector from a differently configured embedder must degrade to "no
 * vector signal", never break the search that already works.
 */
export function cosineSimilarity(a: number[], b: number[]): number {
  if (!Array.isArray(a) || !Array.isArray(b) || a.length !== b.length || a.length === 0) {
    return 0;
  }
  let dot = 0;
  let normA = 0;
  let normB = 0;
  for (let i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  if (normA <= 0 || normB <= 0) {
    return 0;
  }
  return dot / (Math.sqrt(normA) * Math.sqrt(normB));
}

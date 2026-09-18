/*
 * Copyright (c) 2025 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 */

import {
  KnowledgeChunk,
  KnowledgeIndexState,
  KnowledgeSnapshot,
  KnowledgeSourceType,
} from '../viewmodel/KnowledgeModels';

/**
 * Bumped only when the *file layout* changes. Content changes do not need it:
 * the chunk fingerprint and the index signature both invalidate the file on
 * their own, so this constant is about parsing, not about correctness.
 */
export const KNOWLEDGE_SNAPSHOT_VERSION = 1;

/** 2^31 − 1, prime. Keeps every hash step inside exact double arithmetic. */
const HASH_MODULUS = 2147483647;
const HASH_MULTIPLIER = 1000003;
const HASH_SEED = 5381;
const HEX = '0123456789abcdef';
/**
 * Polynomial rolling hash, hex encoded — a cache key, not a security digest.
 *
 * Modular arithmetic rather than the usual FNV shift/xor form: every
 * intermediate (`hash * HASH_MULTIPLIER + code`) stays below 2^51, so it is
 * exact in a double on any engine. A 32-bit-integer form would instead depend
 * on the runtime's integer coercion, and a cache key that differs between the
 * device and the test runner is worse than no cache key.
 */
export function hashString(text: string): string {
  if (typeof text !== 'string' || text.length === 0) {
    return '0000000';
  }
  let hash = HASH_SEED;
  for (let i = 0; i < text.length; i++) {
    hash = (hash * HASH_MULTIPLIER + text.charCodeAt(i)) % HASH_MODULUS;
  }
  let out = '';
  let remaining = hash;
  for (let digit = 0; digit < 7; digit++) {
    out = HEX.charAt(remaining % 16) + out;
    remaining = Math.floor(remaining / 16);
  }
  return out;
}

/**
 * Digest of the chunk list, i.e. "what would be indexed".
 *
 * A pure function of the chunks, so any change to the corpus *or* to the
 * chunker moves it: adding a note, editing a paragraph, or changing a chunk
 * boundary all invalidate a persisted snapshot, and no human has to remember
 * to do anything.
 */
export function fingerprintChunks(chunks: KnowledgeChunk[]): string {
  if (!Array.isArray(chunks)) {
    return hashString('');
  }
  const parts: string[] = [];
  parts.push(String(chunks.length));
  for (let i = 0; i < chunks.length; i++) {
    const chunk = chunks[i];
    // chunkId already encodes docId and ordinal, but heading/tag/text are what
    // the index actually reads, so they are hashed too.
    parts.push(chunk.chunkId);
    parts.push(chunk.headingPath);
    parts.push(chunk.knowledgeTag);
    parts.push(chunk.sourceType);
    parts.push(chunk.text);
  }
  return hashString(parts.join('\u0001'));
}

/** Serialises a snapshot. Field order is fixed so the bytes are reproducible. */
export function encodeSnapshot(snapshot: KnowledgeSnapshot): string {
  return JSON.stringify(snapshot);
}

function isFiniteNumber(value: number): boolean {
  return typeof value === 'number' && Number.isFinite(value);
}

function toNumberArray(raw: number[]): number[] {
  const out: number[] = [];
  if (!Array.isArray(raw)) {
    return out;
  }
  for (let i = 0; i < raw.length; i++) {
    const value = raw[i];
    if (!isFiniteNumber(value)) {
      return [];
    }
    out.push(value);
  }
  return out;
}

/**
 * Rebuilds a snapshot from disk, or returns null.
 *
 * Null means "rebuild from the corpus", which is always correct — so every
 * uncertainty (wrong version, truncated file, a field of the wrong type) is
 * resolved the same way instead of being repaired into something half-trusted.
 * This is the boundary where corrupt data would otherwise enter retrieval and
 * produce confidently wrong citations.
 */
export function decodeSnapshot(json: string): KnowledgeSnapshot | null {
  if (typeof json !== 'string' || json.length === 0) {
    return null;
  }
  let parsed: KnowledgeSnapshot;
  try {
    parsed = JSON.parse(json) as KnowledgeSnapshot;
  } catch (e) {
    return null;
  }
  if (!parsed || parsed.version !== KNOWLEDGE_SNAPSHOT_VERSION) {
    return null;
  }
  if (typeof parsed.fingerprint !== 'string' || typeof parsed.signature !== 'string') {
    return null;
  }
  if (!Array.isArray(parsed.chunks)) {
    return null;
  }

  const snapshot = new KnowledgeSnapshot();
  snapshot.version = parsed.version;
  snapshot.fingerprint = parsed.fingerprint;
  snapshot.signature = parsed.signature;
  snapshot.vectorSignature = typeof parsed.vectorSignature === 'string'
    ? parsed.vectorSignature
    : '';

  for (let i = 0; i < parsed.chunks.length; i++) {
    const raw = parsed.chunks[i];
    if (!raw || typeof raw.chunkId !== 'string' || raw.chunkId.length === 0) {
      return null;
    }
    if (typeof raw.text !== 'string' || typeof raw.headingPath !== 'string') {
      return null;
    }
    const chunk = new KnowledgeChunk();
    chunk.chunkId = raw.chunkId;
    chunk.docId = typeof raw.docId === 'string' ? raw.docId : '';
    chunk.title = typeof raw.title === 'string' ? raw.title : '';
    chunk.headingPath = raw.headingPath;
    chunk.courseId = typeof raw.courseId === 'string' ? raw.courseId : '';
    chunk.knowledgeTag = typeof raw.knowledgeTag === 'string' ? raw.knowledgeTag : '';
    chunk.sourceType = typeof raw.sourceType === 'string'
      ? raw.sourceType as KnowledgeSourceType
      : KnowledgeSourceType.COURSE_NOTE;
    chunk.text = raw.text;
    chunk.chunkIndex = isFiniteNumber(raw.chunkIndex) ? raw.chunkIndex : i;
    snapshot.chunks.push(chunk);
  }

  const state = new KnowledgeIndexState();
  const rawState = parsed.state;
  if (!rawState || !Array.isArray(rawState.terms) || !Array.isArray(rawState.postings) ||
    !Array.isArray(rawState.chunkLengths)) {
    return null;
  }
  if (rawState.terms.length !== rawState.postings.length ||
    rawState.chunkLengths.length !== snapshot.chunks.length) {
    return null;
  }
  state.chunkLengths = toNumberArray(rawState.chunkLengths);
  if (state.chunkLengths.length !== snapshot.chunks.length) {
    return null;
  }
  state.averageLength = isFiniteNumber(rawState.averageLength) ? rawState.averageLength : 0;
  for (let t = 0; t < rawState.terms.length; t++) {
    const term = rawState.terms[t];
    if (typeof term !== 'string' || term.length === 0) {
      return null;
    }
    const flat = toNumberArray(rawState.postings[t]);
    if (flat.length !== rawState.postings[t].length || flat.length % 2 !== 0) {
      return null;
    }
    state.terms.push(term);
    state.postings.push(flat);
  }
  snapshot.state = state;

  if (Array.isArray(parsed.vectors)) {
    for (let v = 0; v < parsed.vectors.length; v++) {
      const vector = toNumberArray(parsed.vectors[v]);
      if (vector.length !== parsed.vectors[v].length) {
        return null;
      }
      snapshot.vectors.push(vector);
    }
    // Vectors are positional, so a partial set would silently mis-align with
    // the chunks and score the wrong passage.
    if (snapshot.vectors.length !== 0 && snapshot.vectors.length !== snapshot.chunks.length) {
      return null;
    }
    // Vectors with no provenance cannot be checked against the current
    // embedder, and an unverifiable vector is not worth the bytes.
    if (snapshot.vectors.length > 0 && snapshot.vectorSignature.length === 0) {
      return null;
    }
  }
  return snapshot;
}

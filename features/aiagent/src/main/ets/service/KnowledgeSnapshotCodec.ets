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
  const quantized = quantizeVectors(snapshot.vectors);
  const encoded: EncodedKnowledgeSnapshot = {
    version: snapshot.version,
    fingerprint: snapshot.fingerprint,
    signature: snapshot.signature,
    vectorSignature: snapshot.vectorSignature,
    chunks: snapshot.chunks,
    state: snapshot.state,
    vectors: [],
    vectorsQuantized: quantized.rows,
    vectorScales: quantized.scales,
  };
  return JSON.stringify(encoded);
}

/**
 * The file layout, as opposed to the in-memory model.
 *
 * Vectors are the one field whose *storage* form differs from its *working*
 * form, so the packing lives here and `KnowledgeSnapshot.vectors` keeps holding
 * plain floats. Everything downstream — the retriever, the fusion, the store —
 * therefore never learns that the bytes on disk are quantised.
 *
 * Why quantise at all: 243 chunks × 1024 dimensions as JSON floats is about
 * 5.2 MB, which is parsed on every launch and defeats the entire point of
 * caching (the rebuild it avoids costs ~11 ms). Symmetric int8 per row brings
 * that to ~0.33 MB, and on the shipped corpus it reproduces the exact
 * end-to-end ranking — Recall@3 0.9697, MRR 0.9545, paraphrase 1.00, identical
 * to float32 in every position. So the trade is "16× smaller file, same
 * answers", not "smaller file, slightly worse answers".
 */
interface EncodedKnowledgeSnapshot {
  version: number;
  fingerprint: string;
  signature: string;
  vectorSignature: string;
  chunks: KnowledgeChunk[];
  state: KnowledgeIndexState;
  /** Written as an empty array by this version; read for files written before it. */
  vectors: number[][];
  /** One base64 row per chunk, in chunk order. Empty when there are no vectors. */
  vectorsQuantized: string[];
  /** Per-row dequantisation scale, index-aligned with `vectorsQuantized`. */
  vectorScales: number[];
}

const BASE64_ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

/** Largest magnitude an int8 slot can hold. */
const QUANT_MAX = 127;

/**
 * Shift applied to a quantised value before it becomes a byte, so every byte is
 * 0..255. Without it a negative value would need two's-complement handling, and
 * this module deliberately does no bitwise arithmetic.
 */
const BYTE_OFFSET = 128;

/** Standard base64 with padding. Hand-rolled: no bit ops, no platform API. */
export function encodeBase64(bytes: number[]): string {
  let out = '';
  if (!Array.isArray(bytes)) {
    return out;
  }
  for (let i = 0; i < bytes.length; i += 3) {
    const hasSecond = i + 1 < bytes.length;
    const hasThird = i + 2 < bytes.length;
    const b0 = clampByte(bytes[i]);
    const b1 = hasSecond ? clampByte(bytes[i + 1]) : 0;
    const b2 = hasThird ? clampByte(bytes[i + 2]) : 0;
    out += BASE64_ALPHABET.charAt(Math.floor(b0 / 4));
    out += BASE64_ALPHABET.charAt((b0 % 4) * 16 + Math.floor(b1 / 16));
    out += hasSecond ? BASE64_ALPHABET.charAt((b1 % 16) * 4 + Math.floor(b2 / 64)) : '=';
    out += hasThird ? BASE64_ALPHABET.charAt(b2 % 64) : '=';
  }
  return out;
}

/** Inverse of `encodeBase64`. Padding and any stray character are skipped. */
export function decodeBase64(text: string): number[] {
  const out: number[] = [];
  if (typeof text !== 'string' || text.length === 0) {
    return out;
  }
  let buffer = 0;
  let bits = 0;
  for (let i = 0; i < text.length; i++) {
    const value = BASE64_ALPHABET.indexOf(text.charAt(i));
    if (value < 0) {
      continue;
    }
    buffer = buffer * 64 + value;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      const divisor = Math.pow(2, bits);
      out.push(Math.floor(buffer / divisor) % 256);
      // Keep the accumulator inside exact double range; `bits` is always < 6.
      buffer = buffer % divisor;
    }
  }
  return out;
}

function clampByte(value: number): number {
  if (!isFiniteNumber(value)) {
    return 0;
  }
  const rounded = Math.round(value);
  if (rounded < 0) {
    return 0;
  }
  return rounded > 255 ? 255 : rounded;
}

/** A quantised vector set, ready to be written. */
export class QuantizedVectorSet {
  scales: number[] = [];
  rows: string[] = [];
}

/**
 * Symmetric per-row int8 quantisation.
 *
 * Per row rather than one scale for the whole set: the rows come from the same
 * model so their magnitudes are close, but "close" is not "equal", and a single
 * global scale would spend precision on the largest row at the expense of the
 * rest. One float per row costs 243 numbers in the file.
 */
export function quantizeVectors(rows: number[][]): QuantizedVectorSet {
  const set = new QuantizedVectorSet();
  if (!Array.isArray(rows)) {
    return set;
  }
  for (let i = 0; i < rows.length; i++) {
    const row = rows[i];
    if (!Array.isArray(row) || row.length === 0) {
      continue;
    }
    let maxAbs = 0;
    for (let v = 0; v < row.length; v++) {
      const magnitude = Math.abs(row[v]);
      if (magnitude > maxAbs) {
        maxAbs = magnitude;
      }
    }
    const scale = maxAbs > 0 ? maxAbs / QUANT_MAX : 1;
    const bytes: number[] = [];
    for (let v = 0; v < row.length; v++) {
      let slot = Math.round(row[v] / scale);
      if (slot > QUANT_MAX) {
        slot = QUANT_MAX;
      }
      if (slot < -QUANT_MAX) {
        slot = -QUANT_MAX;
      }
      bytes.push(slot + BYTE_OFFSET);
    }
    set.scales.push(scale);
    set.rows.push(encodeBase64(bytes));
  }
  return set;
}

/**
 * Inverse of `quantizeVectors`, or null when the payload cannot be trusted.
 *
 * Null rather than a best-effort repair: a row of the wrong width would shift
 * every later similarity onto the wrong passage, and a confidently wrong
 * citation is worse than re-embedding. Bad input here becomes "no cache", which
 * is the same outcome as every other unreadable-file case.
 */
export function dequantizeVectors(scales: number[], rows: string[]): number[][] | null {
  if (!Array.isArray(scales) || !Array.isArray(rows) || scales.length !== rows.length) {
    return null;
  }
  const out: number[][] = [];
  let width = 0;
  for (let i = 0; i < rows.length; i++) {
    const scale = scales[i];
    if (!isFiniteNumber(scale) || scale <= 0 || typeof rows[i] !== 'string') {
      return null;
    }
    const bytes = decodeBase64(rows[i]);
    if (bytes.length === 0) {
      return null;
    }
    if (width === 0) {
      width = bytes.length;
    } else if (bytes.length !== width) {
      return null;
    }
    const vector: number[] = [];
    for (let b = 0; b < bytes.length; b++) {
      vector.push((bytes[b] - BYTE_OFFSET) * scale);
    }
    out.push(vector);
  }
  return out;
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
  let parsed: EncodedKnowledgeSnapshot;
  try {
    parsed = JSON.parse(json) as EncodedKnowledgeSnapshot;
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

  // Vectors may be packed (current) or float (files written before the packing
  // existed). Both are accepted; the packed form wins when present, because a
  // file cannot meaningfully carry both.
  const packedRows = Array.isArray(parsed.vectorsQuantized) ? parsed.vectorsQuantized : [];
  if (packedRows.length > 0) {
    const scales = Array.isArray(parsed.vectorScales) ? parsed.vectorScales : [];
    const decoded = dequantizeVectors(scales, packedRows);
    if (decoded === null) {
      return null;
    }
    snapshot.vectors = decoded;
  } else if (Array.isArray(parsed.vectors)) {
    for (let v = 0; v < parsed.vectors.length; v++) {
      const vector = toNumberArray(parsed.vectors[v]);
      if (vector.length !== parsed.vectors[v].length) {
        return null;
      }
      snapshot.vectors.push(vector);
    }
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
  return snapshot;
}

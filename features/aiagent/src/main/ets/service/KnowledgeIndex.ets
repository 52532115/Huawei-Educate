/*
 * Copyright (c) 2025 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 */

import {
  KnowledgeChunk,
  KnowledgeHit,
  KnowledgeIndexState,
  KnowledgeIndexStats,
} from '../viewmodel/KnowledgeModels';
import { hashString } from './KnowledgeSnapshotCodec';

/** BM25 knobs. Injectable so the offline tests can pin them. */
export class Bm25Config {
  k1: number = 1.2;
  b: number = 0.75;
}

/** One (term, chunk) pair in the inverted index. */
export class KnowledgePosting {
  chunkIndex: number = 0;
  termFrequency: number = 0;
}

/** Internal accumulator for one chunk's score. */
class ScoredChunk {
  chunkIndex: number = 0;
  score: number = 0;
  matchedTerms: string[] = [];
}

const MIN_LATIN_TOKEN_LENGTH = 2;

/**
 * Chinese function words. ArkTS has no segmenter and this project takes no
 * third-party dependencies, so tokens are bigrams — which means a stop word has
 * to be filtered per character (a two-character function word like 什么 would
 * otherwise survive as a bigram).
 */
const CJK_STOP_CHARACTERS = '的了是在和与及或吗呢吧啊我你他她它这那有会要就都也很个上下中对为以之其而则于把被着过';

const LATIN_STOP_WORDS: string[] = [
  'the', 'a', 'an', 'is', 'are', 'was', 'were', 'of', 'to', 'in', 'on', 'for', 'and', 'or',
  'not', 'with', 'as', 'by', 'at', 'it', 'this', 'that', 'be', 'can', 'will', 'from', 'what', 'how',
];

function isCjkCode(code: number): boolean {
  return (code >= 0x4E00 && code <= 0x9FFF) ||
    (code >= 0x3400 && code <= 0x4DBF) ||
    (code >= 0xF900 && code <= 0xFAFF);
}

function isWordCode(code: number): boolean {
  const isDigit = code >= 0x30 && code <= 0x39;
  const isLower = code >= 0x61 && code <= 0x7A;
  return isDigit || isLower;
}

function isCjkStopCharacter(ch: string): boolean {
  return CJK_STOP_CHARACTERS.indexOf(ch) >= 0;
}

/** Drops a bigram only when both halves are function words, so 中国 survives. */
function isStopBigram(bigram: string): boolean {
  return isCjkStopCharacter(bigram.charAt(0)) && isCjkStopCharacter(bigram.charAt(1));
}

/**
 * Splits text into index terms.
 *
 * - Chinese runs become overlapping bigrams: 三次握手 → 三次 / 次握 / 握手.
 *   This needs no dictionary and handles the compounds that matter in course
 *   material (三次握手, 二叉搜索树) without a segmenter.
 * - Latin/digit runs stay whole and lowercase: BM25 → bm25.
 * - Punctuation (including full-width) simply ends a run.
 */
export function tokenize(text: string): string[] {
  const tokens: string[] = [];
  if (typeof text !== 'string' || text.length === 0) {
    return tokens;
  }

  const lowered = text.toLowerCase();
  let i = 0;
  while (i < lowered.length) {
    const code = lowered.charCodeAt(i);

    if (isCjkCode(code)) {
      let end = i;
      while (end < lowered.length && isCjkCode(lowered.charCodeAt(end))) {
        end += 1;
      }
      const run = lowered.substring(i, end);
      if (run.length === 1) {
        if (!isCjkStopCharacter(run)) {
          tokens.push(run);
        }
      } else {
        for (let k = 0; k + 1 < run.length; k++) {
          const bigram = run.substring(k, k + 2);
          if (!isStopBigram(bigram)) {
            tokens.push(bigram);
          }
        }
      }
      i = end;
      continue;
    }

    if (isWordCode(code)) {
      let end = i;
      while (end < lowered.length && isWordCode(lowered.charCodeAt(end))) {
        end += 1;
      }
      const token = lowered.substring(i, end);
      if (token.length >= MIN_LATIN_TOKEN_LENGTH && LATIN_STOP_WORDS.indexOf(token) < 0) {
        tokens.push(token);
      }
      i = end;
      continue;
    }

    i += 1;
  }
  return tokens;
}

/** Keeps the first occurrence of each term, so query order is preserved. */
function dedupeTokens(tokens: string[]): string[] {
  const unique: string[] = [];
  const seen = new Set<string>();
  for (let i = 0; i < tokens.length; i++) {
    const token = tokens[i];
    if (!seen.has(token)) {
      seen.add(token);
      unique.push(token);
    }
  }
  return unique;
}

function isBigram(token: string): boolean {
  return token.length === 2 && isCjkCode(token.charCodeAt(0)) && isCjkCode(token.charCodeAt(1));
}

/**
 * `tokenize` plus the individual characters of every CJK bigram.
 *
 * Used only by the hashed-vector embedder, and derived from `tokenize` rather
 * than scanning the text again — one scanner, so the two cannot drift apart.
 * The unigrams matter for paraphrase: a learner who writes 排好序 still shares
 * 排 with 排序, which the bigram-only form would miss.
 */
export function tokenizeWithUnigrams(text: string): string[] {
  const tokens = tokenize(text);
  const expanded: string[] = [];
  for (let i = 0; i < tokens.length; i++) {
    const token = tokens[i];
    expanded.push(token);
    if (isBigram(token)) {
      expanded.push(token.charAt(0));
      expanded.push(token.charAt(1));
    }
  }
  return expanded;
}

/**
 * In-memory BM25 index over knowledge chunks.
 *
 * Pure logic: no AppStorage, no file system, no clock, no randomness. The
 * index is rebuilt from chunks rather than persisted here — persistence and
 * lazy loading belong to a store, exactly as PracticeHistoryStore owns the
 * mastery file while the scoring rules stay in pure functions.
 *
 * Ranking is a total order (score desc, then chunkId asc), so a query with
 * ties still returns a reproducible sequence.
 */
export class KnowledgeIndex {
  private chunks: KnowledgeChunk[] = [];
  private postings: Map<string, KnowledgePosting[]> = new Map();
  private chunkLengths: number[] = [];
  private averageLength: number = 0;
  private config: Bm25Config = new Bm25Config();

  constructor(config: Bm25Config = new Bm25Config()) {
    this.config = config;
  }

  /** Replaces the index contents. Empty input yields an empty, usable index. */
  build(chunks: KnowledgeChunk[]): void {
    this.chunks = [];
    this.postings = new Map<string, KnowledgePosting[]>();
    this.chunkLengths = [];
    this.averageLength = 0;
    if (!Array.isArray(chunks)) {
      return;
    }
    for (let i = 0; i < chunks.length; i++) {
      this.chunks.push(chunks[i]);
    }

    let totalLength = 0;
    for (let i = 0; i < this.chunks.length; i++) {
      const tokens = this.collectTokens(this.chunks[i]);
      this.chunkLengths.push(tokens.length);
      totalLength += tokens.length;

      const frequencies = new Map<string, number>();
      for (let t = 0; t < tokens.length; t++) {
        const term = tokens[t];
        frequencies.set(term, (frequencies.get(term) || 0) + 1);
      }
      frequencies.forEach((frequency: number, term: string) => {
        const posting = new KnowledgePosting();
        posting.chunkIndex = i;
        posting.termFrequency = frequency;
        const bucket = this.postings.get(term);
        if (bucket) {
          bucket.push(posting);
        } else {
          this.postings.set(term, [posting]);
        }
      });
    }

    this.averageLength = this.chunks.length > 0 ? totalLength / this.chunks.length : 0;
  }

  /**
   * Title and heading path are indexed twice. A chunk whose heading names the
   * topic should outrank one that merely mentions the topic in a paragraph.
   */
  private collectTokens(chunk: KnowledgeChunk): string[] {
    const tokens: string[] = [];
    const titleTokens = tokenize(chunk.title);
    for (let i = 0; i < titleTokens.length; i++) {
      tokens.push(titleTokens[i]);
    }
    for (let i = 0; i < titleTokens.length; i++) {
      tokens.push(titleTokens[i]);
    }
    const headingTokens = tokenize(chunk.headingPath);
    for (let i = 0; i < headingTokens.length; i++) {
      tokens.push(headingTokens[i]);
    }
    const bodyTokens = tokenize(chunk.text);
    for (let i = 0; i < bodyTokens.length; i++) {
      tokens.push(bodyTokens[i]);
    }
    return tokens;
  }

  /**
   * Top-`topK` chunks for a query, best first.
   *
   * A query with no usable terms (empty, or only function words) returns
   * nothing rather than everything — answering "no idea" is the contract the
   * caller needs, and it is what keeps the tutor from citing a random chunk.
   */
  search(query: string, topK: number = 5): KnowledgeHit[] {
    const hits: KnowledgeHit[] = [];
    if (topK <= 0 || this.chunks.length === 0) {
      return hits;
    }
    const terms = dedupeTokens(tokenize(query));
    if (terms.length === 0) {
      return hits;
    }

    const count = this.chunks.length;
    const average = this.averageLength > 0 ? this.averageLength : 1;
    const totals = new Map<number, number>();
    const matched = new Map<number, string[]>();

    for (let t = 0; t < terms.length; t++) {
      const term = terms[t];
      const bucket = this.postings.get(term);
      if (!bucket || bucket.length === 0) {
        continue;
      }
      const documentFrequency = bucket.length;
      const idf = Math.log(1 + (count - documentFrequency + 0.5) / (documentFrequency + 0.5));

      for (let p = 0; p < bucket.length; p++) {
        const posting = bucket[p];
        const length = this.chunkLengths[posting.chunkIndex];
        const denominator = posting.termFrequency +
          this.config.k1 * (1 - this.config.b + this.config.b * length / average);
        if (denominator <= 0) {
          continue;
        }
        const contribution = idf * (posting.termFrequency * (this.config.k1 + 1)) / denominator;
        totals.set(posting.chunkIndex, (totals.get(posting.chunkIndex) || 0) + contribution);

        const termList = matched.get(posting.chunkIndex);
        if (termList) {
          termList.push(term);
        } else {
          matched.set(posting.chunkIndex, [term]);
        }
      }
    }

    const scored: ScoredChunk[] = [];
    totals.forEach((score: number, chunkIndex: number) => {
      const item = new ScoredChunk();
      item.chunkIndex = chunkIndex;
      item.score = score;
      const termsForChunk: string[] | undefined = matched.get(chunkIndex);
      item.matchedTerms = termsForChunk ? termsForChunk : [];
      scored.push(item);
    });
    scored.sort((a: ScoredChunk, b: ScoredChunk) => this.compareScored(a, b));

    const limit = scored.length < topK ? scored.length : topK;
    for (let i = 0; i < limit; i++) {
      const item = scored[i];
      const hit = new KnowledgeHit();
      hit.chunk = this.chunks[item.chunkIndex];
      hit.score = Math.round(item.score * 10000) / 10000;
      hit.matchedTerms = item.matchedTerms;
      hits.push(hit);
    }
    return hits;
  }

  /** Score descending, then chunk id ascending so ties stay reproducible. */
  private compareScored(a: ScoredChunk, b: ScoredChunk): number {
    if (a.score !== b.score) {
      return b.score - a.score;
    }
    const idA = this.chunks[a.chunkIndex].chunkId;
    const idB = this.chunks[b.chunkIndex].chunkId;
    if (idA === idB) {
      return 0;
    }
    return idA < idB ? -1 : 1;
  }

  stats(): KnowledgeIndexStats {
    const stats = new KnowledgeIndexStats();
    stats.chunkCount = this.chunks.length;
    stats.termCount = this.postings.size;
    let total = 0;
    for (let i = 0; i < this.chunkLengths.length; i++) {
      total += this.chunkLengths[i];
    }
    stats.avgChunkLength = this.chunks.length > 0 ? Math.round(total / this.chunks.length) : 0;
    return stats;
  }

  isEmpty(): boolean {
    return this.chunks.length === 0;
  }

  /**
   * A stable digest of how this class turns a chunk into index terms.
   *
   * The persisted postings are only valid for the exact tokenizer and field
   * weighting that produced them, and a cached file cannot notice that the code
   * changed. Rather than trusting whoever edits `tokenize` or `collectTokens`
   * to also bump a version constant, this signature is computed from a fixed
   * probe chunk through the real code path and stored alongside the postings.
   * A mismatch on load means "rebuild", with no manual bookkeeping.
   */
  buildSignature(): string {
    const tokens = this.collectTokens(buildSignatureProbe());
    return hashString(tokens.join('|'));
  }

  /** Snapshot of the postings. The chunk list is owned by the caller. */
  exportState(): KnowledgeIndexState {
    const state = new KnowledgeIndexState();
    state.chunkLengths = this.chunkLengths.slice();
    state.averageLength = this.averageLength;
    this.postings.forEach((bucket: KnowledgePosting[], term: string) => {
      const flat: number[] = [];
      for (let i = 0; i < bucket.length; i++) {
        flat.push(bucket[i].chunkIndex);
        flat.push(bucket[i].termFrequency);
      }
      state.terms.push(term);
      state.postings.push(flat);
    });
    return state;
  }

  /**
   * Restores an exported state. Returns false — and leaves the index untouched
   * — when the state does not line up with `chunks`, because a half-applied
   * index would return confidently wrong rankings instead of failing.
   *
   * Transient, no-answer queries return nothing: the caller then rebuilds from
   * the chunks it already has, which is always safe.
   */
  importState(state: KnowledgeIndexState, chunks: KnowledgeChunk[]): boolean {
    if (!state || !Array.isArray(chunks)) {
      return false;
    }
    if (state.chunkLengths.length !== chunks.length ||
      state.terms.length !== state.postings.length) {
      return false;
    }
    const restoredPostings = new Map<string, KnowledgePosting[]>();
    for (let t = 0; t < state.terms.length; t++) {
      const term = state.terms[t];
      if (typeof term !== 'string' || term.length === 0) {
        return false;
      }
      const flat = state.postings[t];
      if (!Array.isArray(flat) || flat.length % 2 !== 0) {
        return false;
      }
      const bucket: KnowledgePosting[] = [];
      for (let p = 0; p + 1 < flat.length; p += 2) {
        const chunkIndex = flat[p];
        const termFrequency = flat[p + 1];
        if (chunkIndex < 0 || chunkIndex >= chunks.length || termFrequency <= 0) {
          return false;
        }
        const posting = new KnowledgePosting();
        posting.chunkIndex = chunkIndex;
        posting.termFrequency = termFrequency;
        bucket.push(posting);
      }
      restoredPostings.set(term, bucket);
    }

    this.chunks = [];
    for (let i = 0; i < chunks.length; i++) {
      this.chunks.push(chunks[i]);
    }
    this.postings = restoredPostings;
    this.chunkLengths = state.chunkLengths.slice();
    this.averageLength = state.averageLength;
    return true;
  }
}

/**
 * Fixed probe used by `buildSignature`. It deliberately contains a CJK run, a
 * Latin acronym with a slash, a bare number and a stop word, so a change to any
 * branch of the tokenizer moves the signature.
 */
function buildSignatureProbe(): KnowledgeChunk {
  const probe = new KnowledgeChunk();
  probe.chunkId = 'k_probe_0';
  probe.docId = 'probe';
  probe.title = '探测 三次握手';
  probe.headingPath = '探测 › TCP/IP 协议';
  probe.text = '这是一个用于固定分词行为的样例 bm25 的 的 2020';
  return probe;
}


/*
 * Copyright (c) 2025 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 */

import {
  KnowledgeChunk,
  KnowledgeHit,
  KnowledgeIndexStats,
  KnowledgeSnapshot,
  KnowledgeSourceType,
  SeedCourseInput,
  SeedLectureInput,
  SeedQuestionInput,
} from '../viewmodel/KnowledgeModels';
import { KnowledgeChunker } from './KnowledgeChunker';
import { KnowledgeIndex } from './KnowledgeIndex';
import { KnowledgeSeedCorpus } from './KnowledgeSeedCorpus';
import { fingerprintChunks, KNOWLEDGE_SNAPSHOT_VERSION } from './KnowledgeSnapshotCodec';
import { KnowledgeEmbeddingBatch } from './KnowledgeEmbedding';
import { KnowledgeVectorRetriever, fuseRankings } from './KnowledgeVectorRetriever';
import { KnowledgeIndexStore } from './KnowledgeIndexStore';
import { buildCourseCatalog } from './KnowledgeCourseCatalog';
import { buildLectureNotes } from './KnowledgeNotesCatalog';
import { AdaptivePracticeService } from './AdaptivePracticeService';

/**
 * How many passages the retriever hands to the model by default. One knob so
 * the chat fast path and the agent tool cannot drift apart; four chunks of
 * ~320 characters stay well inside the prompt budget while still covering a
 * question that spans two chapters.
 */
export const KNOWLEDGE_DEFAULT_TOP_K = 4;

/**
 * How deep each retriever is asked to go before fusion. Wider than the final
 * `topK` on purpose: RRF rewards agreement, and a passage sitting at rank 7 in
 * both lists is exactly the kind of candidate a single retriever's top 4 would
 * have hidden.
 */
export const HYBRID_CANDIDATE_DEPTH = 10;

/** How the in-memory index came to exist. Reported for diagnostics and tests. */
export const LOAD_SOURCE_CACHE = 'cache';
export const LOAD_SOURCE_REBUILD = 'rebuild';
export const LOAD_SOURCE_EMPTY = 'empty';
export const LOAD_SOURCE_FAILED = 'failed';

/**
 * How long after start-up the background index build is scheduled.
 *
 * The build is only a few straight-line milliseconds, but start-up is the one
 * place in the app where a few milliseconds are visible to the learner — so it
 * is deferred past the first frame rather than run inline. The delay is short
 * enough that the index is essentially always ready before a question has been
 * typed, which is the entire point: it moves the cost off the *chat turn*.
 */
export const KNOWLEDGE_WARMUP_DELAY_MS = 400;


const NEWLINE = '\n';
const BLOCK_HEADER = '【检索到的课程资料】';

/**
 * Supplies the raw documents the index is built from.
 *
 * It is a separate class because it is the only piece that touches the rest of
 * the app: `KnowledgeStore` stays a pure retriever (and therefore offline
 * testable) while the wiring to `AdaptivePracticeService` lives here.
 *
 * The corpus is deliberately **public material only** — the shipped course
 * notes, the shipped course catalogue and the shipped question bank. Learner
 * data (error book, exam scores, profile) is never indexed, so a retrieval
 * hit can never leak one student's notes into another context, and the answer
 * can never be grounded on personal data that was supposed to stay in its own
 * tool.
 */
export class KnowledgeCorpusProvider {
  private practiceService: AdaptivePracticeService = new AdaptivePracticeService();

  /** Long-form notes: the substance the catalogue rows only summarise. */
  getLectures(): SeedLectureInput[] {
    return buildLectureNotes();
  }

  getCourses(): SeedCourseInput[] {
    return buildCourseCatalog();
  }

  getQuestions(): SeedQuestionInput[] {
    const bank = this.practiceService.getShippedQuestionBank();
    const inputs: SeedQuestionInput[] = [];
    for (let i = 0; i < bank.length; i++) {
      const question = bank[i];
      const input = new SeedQuestionInput();
      input.questionId = question.id;
      input.title = question.title;
      input.options = question.options;
      input.correctIndex = question.correctIndex;
      input.knowledgeTag = question.knowledgeTag;
      input.explanation = question.explanation;
      input.recommendation = question.recommendation;
      inputs.push(input);
    }
    return inputs;
  }
}

/** Human-readable source label used in retrieved passages and citations. */
export function describeKnowledgeSource(sourceType: KnowledgeSourceType): string {
  switch (sourceType) {
    case KnowledgeSourceType.COURSE:
      return '课程大纲';
    case KnowledgeSourceType.QUESTION_BANK:
      return '题库解析';
    case KnowledgeSourceType.ERROR_BOOK:
      return '错题本';
    default:
      return '课程笔记';
  }
}

/**
 * Retrieval facade over the local course knowledge base.
 *
 * The index is assembled once per process, on the first search or on an
 * explicit `warmUp()`, and then reused: the corpus never changes at runtime.
 * Sharing the instance (see `getInstance`) is what makes that once-per-process
 * rather than once-per-chat-turn.
 *
 * Assembly order is cache-first: the persisted snapshot is loaded when it
 * belongs to exactly this corpus and this indexing code, and the corpus is only
 * chunked and tokenized when it does not. Both keys are derived, never
 * hand-maintained — see `fingerprintChunks` and `KnowledgeIndex.buildSignature`.
 *
 * This is the seam the whole RAG feature is reached through: the chat fast path
 * and the agent tool both call `search` and never touch the chunker or the
 * index directly.
 */
export class KnowledgeStore {
  private static shared: KnowledgeStore | null = null;
  /**
   * Set when a warm-up has been scheduled, so a recreated ability cannot queue
   * a second timer for work that is already done or already pending.
   */
  private static warmUpScheduled: boolean = false;

  private provider: KnowledgeCorpusProvider;
  private indexStore: KnowledgeIndexStore;
  private index: KnowledgeIndex = new KnowledgeIndex();
  private buildAttempted: boolean = false;
  private loadSource: string = LOAD_SOURCE_EMPTY;
  private fingerprint: string = '';
  private snapshotSaved: boolean = false;
  /** Kept so the dense side and the snapshot can be built without rebuilding. */
  private chunks: KnowledgeChunk[] = [];
  private indexSignature: string = '';
  private vectorSignature: string = '';
  private vectorRetriever: KnowledgeVectorRetriever = new KnowledgeVectorRetriever();

  constructor(provider: KnowledgeCorpusProvider = new KnowledgeCorpusProvider(),
    indexStore: KnowledgeIndexStore = new KnowledgeIndexStore()) {
    this.provider = provider;
    this.indexStore = indexStore;
  }

  /** Process-wide instance, so the index is built once no matter who asks. */
  static getInstance(): KnowledgeStore {
    const existing = KnowledgeStore.shared;
    if (existing !== null) {
      return existing;
    }
    const created = new KnowledgeStore();
    KnowledgeStore.shared = created;
    return created;
  }

  /**
   * Schedules the one-time background index build. This is what start-up
   * should call — not `warmUp()` directly.
   *
   * Scheduling rather than building inline is deliberate on two counts. The
   * build must not sit on the start-up path, and it must run *after* the app
   * has published `filesDir`: without it the disk cache is silently bypassed
   * (`KnowledgeIndexStore` reports itself disabled) and every launch would pay
   * a full rebuild while looking perfectly healthy.
   *
   * A dropped or failed warm-up is not an error condition. `search` builds on
   * demand, so the worst case is that the first question pays the few
   * milliseconds this was meant to absorb — which is why every failure here is
   * swallowed. An index that could not be prepared must never keep the app
   * from starting.
   */
  static scheduleWarmUp(delayMs: number = KNOWLEDGE_WARMUP_DELAY_MS): void {
    if (KnowledgeStore.warmUpScheduled) {
      return;
    }
    KnowledgeStore.warmUpScheduled = true;
    setTimeout(() => {
      try {
        KnowledgeStore.getInstance().warmUp();
      } catch (e) {
        // Leave the empty index in place; search() still degrades to an
        // ordinary answer, exactly as it would have without the cache.
      }
    }, delayMs);
  }

  /**
   * Forgets that a warm-up was scheduled, so the next `scheduleWarmUp` queues
   * another one. Used by tests; harmless at runtime because a second build is
   * already a no-op.
   */
  static resetWarmUpSchedule(): void {
    KnowledgeStore.warmUpScheduled = false;
  }

  /**
   * Builds the index ahead of the first question, so no chat turn pays for it.
   *
   * This — not the disk cache — is what actually keeps the build off the
   * critical path, and the measured numbers say so: on the shipped corpus a
   * cold rebuild is ~11 ms of which the disk cache removes ~6 ms, while moving
   * the work to app start removes all of it. `search` stays correct whether or
   * not it was called.
   *
   * Start-up should reach this through `scheduleWarmUp`, which defers it past
   * the first frame and guarantees `filesDir` exists first. This stays public
   * for the tests and for any caller that is already off the critical path.
   */
  warmUp(): void {
    this.ensureBuilt();
  }

  /** Where the current index came from: `cache`, `rebuild`, `empty`, `failed`. */
  getLoadSource(): string {
    return this.loadSource;
  }

  /** True when the last rebuild managed to write a snapshot to `filesDir`. */
  wasSnapshotSaved(): boolean {
    return this.snapshotSaved;
  }

  /** Digest of the indexed chunks; the cache key. Empty before the first build. */
  getFingerprint(): string {
    return this.fingerprint;
  }

  /**
   * Top-`topK` passages for a query, best first.
   *
   * Degradation is deliberate and silent: if the corpus cannot be assembled the
   * store yields no hits, the caller falls back to an ordinary answer, and the
   * tutor stays usable. A retrieval failure must never turn into a failed turn.
   */
  search(query: string, topK: number = KNOWLEDGE_DEFAULT_TOP_K): KnowledgeHit[] {
    this.ensureBuilt();
    return this.index.search(query, topK);
  }

  /**
   * Top-`topK` passages fused from the lexical and dense rankings.
   *
   * The query vector is passed in rather than computed here, because producing
   * it may be asynchronous (the proxy) while `search` must stay callable from
   * synchronous code. It also keeps the store free of any embedder dependency.
   *
   * Falls back to plain BM25 whenever the dense side is unavailable — no
   * vectors prepared, a vector of the wrong width, or an empty query vector —
   * so a caller can always use this instead of branching itself.
   */
  searchHybrid(query: string, queryVector: number[],
    topK: number = KNOWLEDGE_DEFAULT_TOP_K): KnowledgeHit[] {
    this.ensureBuilt();
    if (this.vectorRetriever.isEmpty() || !Array.isArray(queryVector) || queryVector.length === 0) {
      return this.index.search(query, topK);
    }
    const lexical = this.index.search(query, HYBRID_CANDIDATE_DEPTH);
    const dense = this.vectorRetriever.search(queryVector, HYBRID_CANDIDATE_DEPTH);
    return fuseRankings(lexical, dense, topK);
  }

  /**
   * Installs (or replaces) the dense side.
   *
   * Returns false when the batch cannot be paired with the current chunks — a
   * count mismatch, a malformed row, or a corpus that never built. Nothing is
   * installed in that case: half a vector set would score the wrong passage,
   * which is worse than having no dense side at all.
   */
  prepareVectors(batch: KnowledgeEmbeddingBatch, signature: string): boolean {
    this.ensureBuilt();
    if (!batch || !Array.isArray(batch.vectors) || this.chunks.length === 0) {
      return false;
    }
    if (!this.vectorRetriever.build(batch.vectors, this.chunks)) {
      return false;
    }
    this.vectorSignature = signature;
    this.persist();
    return true;
  }

  /** True when a dense side is available for `searchHybrid`. */
  hasVectors(): boolean {
    return !this.vectorRetriever.isEmpty();
  }

  /** Which embedder produced the installed vectors; empty when there are none. */
  getVectorSource(): string {
    return this.vectorSignature;
  }

  /** Drops the dense side, e.g. after the configured proxy changes. */
  clearVectors(): void {
    this.vectorRetriever = new KnowledgeVectorRetriever();
    this.vectorSignature = '';
  }

  /**
   * True when the installed vectors came from exactly this embedder.
   *
   * This is what makes an expensive embedding path affordable: on a warm start
   * the proxy is never called, because the cached vectors already carry the
   * signature of the model that produced them.
   */
  hasVectorsFor(signature: string): boolean {
    return !this.vectorRetriever.isEmpty() && this.vectorSignature === signature;
  }

  stats(): KnowledgeIndexStats {
    this.ensureBuilt();
    return this.index.stats();
  }

  /**
   * Drops the cached index so the next call rebuilds it. Used by tests, and by
   * anything that ever changes the corpus at runtime.
   */
  invalidate(): void {
    this.index = new KnowledgeIndex();
    this.buildAttempted = false;
    this.loadSource = LOAD_SOURCE_EMPTY;
    this.fingerprint = '';
    this.snapshotSaved = false;
    this.chunks = [];
    this.indexSignature = '';
    this.clearVectors();
  }

  /**
   * Formats hits as a prompt block. Pure data: the citation *instruction* lives
   * in the system prompt, so there is exactly one place that decides how the
   * model is told to cite.
   */
  buildContextBlock(hits: KnowledgeHit[]): string {
    if (!Array.isArray(hits) || hits.length === 0) {
      return '';
    }
    const lines: string[] = [BLOCK_HEADER];
    for (let i = 0; i < hits.length; i++) {
      const chunk = hits[i].chunk;
      const citation = this.citationOf(hits[i]);
      lines.push(`[${i + 1}]（${describeKnowledgeSource(chunk.sourceType)}）${citation}` +
        `｜知识点：${chunk.knowledgeTag}`);
      lines.push(chunk.text);
      lines.push('');
    }
    return lines.join(NEWLINE);
  }

  /** Citation text for one hit: the heading path, or the title when there is none. */
  citationOf(hit: KnowledgeHit): string {
    const chunk = hit.chunk;
    if (chunk.headingPath.length > 0) {
      return chunk.headingPath;
    }
    return chunk.title.length > 0 ? chunk.title : chunk.docId;
  }

  private ensureBuilt(): void {
    if (this.buildAttempted) {
      return;
    }
    // Set before building: a corpus that failed once must not be retried on
    // every single chat turn.
    this.buildAttempted = true;
    try {
      const corpus = new KnowledgeSeedCorpus();
      const documents = corpus.buildDocuments(
        this.provider.getCourses(),
        this.provider.getQuestions(),
        this.provider.getLectures(),
      );
      const chunks = new KnowledgeChunker().buildChunks(documents);
      if (chunks.length === 0) {
        // Caching an empty index would turn one bad launch into a permanent
        // "the tutor knows nothing" state.
        this.index = new KnowledgeIndex();
        this.loadSource = LOAD_SOURCE_EMPTY;
        return;
      }

      // Two independent keys: the corpus digest catches a changed chunk list,
      // the signature catches changed tokenizing code. Either one alone would
      // let a stale snapshot be served with full confidence.
      this.fingerprint = fingerprintChunks(chunks);
      const signature = this.index.buildSignature();

      const cached = this.indexStore.load(this.fingerprint, signature);
      if (cached !== null && this.index.importState(cached.state, cached.chunks)) {
        this.chunks = cached.chunks;
        this.indexSignature = signature;
        this.restoreCachedVectors(cached);
        this.loadSource = LOAD_SOURCE_CACHE;
        return;
      }

      this.index.build(chunks);
      this.chunks = chunks;
      this.indexSignature = signature;
      this.loadSource = LOAD_SOURCE_REBUILD;
      this.persist();
    } catch (e) {
      // Leave the empty index in place; search() then reports "no match".
      this.index = new KnowledgeIndex();
      this.chunks = [];
      this.loadSource = LOAD_SOURCE_FAILED;
    }
  }

  /**
   * Reinstalls vectors from a snapshot. A batch that cannot be paired with the
   * cached chunks is dropped rather than trusted — the caller re-embeds, which
   * is expensive but correct.
   */
  private restoreCachedVectors(snapshot: KnowledgeSnapshot): void {
    if (snapshot.vectors.length === 0 || snapshot.vectorSignature.length === 0) {
      return;
    }
    if (this.vectorRetriever.build(snapshot.vectors, snapshot.chunks)) {
      this.vectorSignature = snapshot.vectorSignature;
    }
  }

  /** Writes the snapshot, vectors included. Failure only costs the next launch CPU. */
  private persist(): void {
    if (this.chunks.length === 0) {
      return;
    }
    const snapshot = new KnowledgeSnapshot();
    snapshot.version = KNOWLEDGE_SNAPSHOT_VERSION;
    snapshot.fingerprint = this.fingerprint;
    snapshot.signature = this.indexSignature;
    snapshot.vectorSignature = this.vectorSignature;
    snapshot.chunks = this.chunks;
    snapshot.state = this.index.exportState();
    snapshot.vectors = this.vectorRetriever.isEmpty() ? [] : this.vectorRetriever.exportVectors();
    this.snapshotSaved = this.indexStore.save(snapshot);
  }
}


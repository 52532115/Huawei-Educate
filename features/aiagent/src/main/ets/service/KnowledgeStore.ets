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
import { KnowledgeEmbeddingBatch, documentTextFor } from './KnowledgeEmbedding';
import {
  KnowledgeVectorRetriever,
  fuseRankings,
  RRF_RANK_CONSTANT,
  RRF_DEFAULT_VECTOR_WEIGHT,
} from './KnowledgeVectorRetriever';
import { KnowledgeProxyEmbedder, vectorWeightForSignature } from './KnowledgeEmbeddingProxy';
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

/**
 * How many chunk texts go into one `/embed` request.
 *
 * The shipped 243 chunks arrive as 10 requests of 25 — roughly 6.5k characters
 * each, comfortably inside the proxy's 8 s budget and inside the server's own
 * per-request limits. Sending everything at once would technically work, but
 * then one slow round trip fails the whole build, and the client would be
 * leaning on the server's batching instead of owning its own.
 */
export const DENSE_EMBED_BATCH_SIZE = 25;

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
 * and the agent tool both call `searchBest` and never touch the chunker, the
 * index or the embedder directly.
 *
 * Both layers of retrieval live behind it. `search` is the lexical index and is
 * always available; `searchBest` adds the dense side when — and only when — a
 * real embedder is configured, building it in the background so no question
 * ever waits for it. Everything about the dense side is optional, so every
 * failure mode ends in the same place: the lexical answer.
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
  /**
   * How much the installed dense list counts in the fusion. Travels with the
   * vectors rather than being a single global default, because the right number
   * is a property of the embedder that produced them (see
   * `RRF_REMOTE_VECTOR_WEIGHT`).
   */
  private vectorWeight: number = RRF_DEFAULT_VECTOR_WEIGHT;
  /**
   * Replaces the default embedder. Production never calls this — the default is
   * the configured proxy, resolved lazily so a settings change takes effect on
   * the next question rather than at construction time.
   */
  private embedderOverride: KnowledgeProxyEmbedder | null = null;
  /** Single-flight guard: concurrent callers share one build. */
  private densePromise: Promise<boolean> | null = null;
  /**
   * The endpoint whose embedding attempt failed, if any. Sticky per endpoint,
   * so a dead backend costs one timeout instead of one per question, while
   * correcting the address in the settings panel retries immediately.
   */
  private denseFailedKey: string = '';

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
   * it may be asynchronous (the proxy) while this must stay callable from
   * synchronous code — and because it keeps the *fusion* a pure function of two
   * rankings, which is what the weight sweep in the tests exploits.
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
    return fuseRankings(lexical, dense, topK, RRF_RANK_CONSTANT, this.vectorWeight);
  }

  /**
   * Best retrieval available right now, which is what the chat fast path and
   * the agent tool call.
   *
   * Two behaviours worth stating, because both are deliberate:
   *
   * - **The first question after a cold start gets BM25, not a delay.** With no
   *   dense side yet this starts the embedding build in the background and
   *   answers from the lexical index immediately; the *next* question is
   *   hybrid. Waiting would put ten network round trips in front of the first
   *   token of a question the learner has already typed.
   * - **It never rejects.** An unconfigured or unreachable backend costs the
   *   vector signal and nothing else — no error surfaces, no turn fails, and
   *   the answer is exactly the one this app gave before any of this existed.
   *
   * Never wire the offline stand-in embedder in here. The hashed bag-of-terms
   * substitute is a measured loss on this corpus, so the dense side is only ever
   * the configured embedder.
   */
  async searchBest(query: string, topK: number = KNOWLEDGE_DEFAULT_TOP_K): Promise<KnowledgeHit[]> {
    this.ensureBuilt();
    const embedder = this.embedder();
    if (embedder.isConfigured() && !this.denseBlocked(embedder)) {
      if (this.hasVectors()) {
        const queryVector = await this.embedQuery(embedder, query);
        if (queryVector !== null) {
          if (this.denseVectorsAreStale(embedder)) {
            // The vectors on hand came from a different embedder than the one
            // that just answered — the backend address, or the model behind it,
            // changed. Fusing them would compare a query from one model against
            // passages from another: a ranking that looks perfectly reasonable
            // and means nothing. Drop them and rebuild instead.
            this.clearVectors();
            this.startDenseBuild(embedder);
            return this.index.search(query, topK);
          }
          return this.searchHybrid(query, queryVector, topK);
        }
      } else {
        this.startDenseBuild(embedder);
      }
    }
    return this.index.search(query, topK);
  }

  /**
   * True when the installed vectors came from a different embedder than the one
   * that just produced a query vector.
   *
   * Only answerable *after* a successful call, because a remote embedder's
   * signature is a property of its reply (model name and width), not of its
   * configuration. Comparing a query against vectors from another model is
   * exactly the "confidently wrong" failure this feature is built to avoid, so
   * a mismatch is treated as "no vectors" rather than as a tolerable drift.
   */
  private denseVectorsAreStale(embedder: KnowledgeProxyEmbedder): boolean {
    const current = embedder.signature();
    return current.length > 0 && this.vectorSignature.length > 0 &&
      this.vectorSignature !== current;
  }

  /** True when a dense side exists or is being built right now. */
  isDensePending(): boolean {
    return this.densePromise !== null;
  }

  /** How much the installed dense list counts in the fusion. */
  getVectorWeight(): number {
    return this.vectorWeight;
  }

  /**
   * Replaces the embedder used by `searchBest`. Exists so the dense lifecycle
   * can be exercised without a network, and so a future non-proxy embedder
   * (a direct vendor call, a bundled model) is a wiring change rather than a
   * rewrite of this class.
   */
  setEmbedder(embedder: KnowledgeProxyEmbedder | null): void {
    this.embedderOverride = embedder;
    this.denseFailedKey = '';
  }

  private embedder(): KnowledgeProxyEmbedder {
    const override = this.embedderOverride;
    return override !== null ? override : KnowledgeProxyEmbedder.current();
  }

  /**
   * True when this endpoint already failed, so the next question does not pay
   * for the same mistake. A different endpoint clears the memory instead of
   * inheriting it.
   */
  private denseBlocked(embedder: KnowledgeProxyEmbedder): boolean {
    const key = embedder.endpointKey();
    if (this.denseFailedKey.length === 0) {
      return false;
    }
    if (this.denseFailedKey === key) {
      return true;
    }
    this.denseFailedKey = '';
    return false;
  }

  private markDenseFailed(embedder: KnowledgeProxyEmbedder): void {
    this.denseFailedKey = embedder.endpointKey();
  }

  /**
   * Embeds the query, or null.
   *
   * A failure here blocks the dense side for this endpoint as well, because the
   * alternative — retrying an 8 s timeout on every question — is a worse
   * experience than the feature being off. Fixing the backend address unblocks
   * it; a restart does too.
   */
  private async embedQuery(embedder: KnowledgeProxyEmbedder, query: string): Promise<number[] | null> {
    if (typeof query !== 'string' || query.length === 0) {
      return null;
    }
    const batch = await embedder.embedBatch([query]);
    if (batch === null || batch.vectors.length === 0) {
      this.markDenseFailed(embedder);
      return null;
    }
    return batch.vectors[0];
  }

  /**
   * Starts the dense build without waiting for it.
   *
   * Single-flight by construction: whoever calls first owns the promise, and
   * anyone who arrives while it is in flight simply leaves. Without this, a
   * burst of questions — or the fast path and the agent tool at once — would
   * each start embedding all 243 chunks, which is 10× the cost and 10× the
   * cost is real money when the embedder is billed per token.
   */
  private startDenseBuild(embedder: KnowledgeProxyEmbedder): void {
    if (this.densePromise !== null) {
      return;
    }
    const pending = this.buildDense(embedder);
    this.densePromise = pending;
    const settle = (): void => {
      this.densePromise = null;
    };
    pending.then(settle, settle);
  }

  /**
   * Embeds every chunk, in batches, and installs the result.
   *
   * All-or-nothing: one failed batch discards the whole set. A partial set
   * would attach vectors to the wrong chunks — the same rule `prepareVectors`
   * enforces, and the reason none of this can be "retried next time" from
   * inside the loop.
   */
  private async buildDense(embedder: KnowledgeProxyEmbedder): Promise<boolean> {
    this.ensureBuilt();
    const chunks = this.chunks;
    const fingerprint = this.fingerprint;
    if (chunks.length === 0) {
      return false;
    }
    const vectors: number[][] = [];
    let dimension = 0;
    let model = '';
    for (let start = 0; start < chunks.length; start += DENSE_EMBED_BATCH_SIZE) {
      const slice = chunks.slice(start, start + DENSE_EMBED_BATCH_SIZE);
      const texts: string[] = [];
      for (let i = 0; i < slice.length; i++) {
        texts.push(documentTextFor(slice[i]));
      }
      const batch = await embedder.embedBatch(texts);
      if (batch === null || batch.vectors.length !== texts.length) {
        this.markDenseFailed(embedder);
        return false;
      }
      if (dimension === 0) {
        dimension = batch.dimension;
      } else if (batch.dimension !== dimension) {
        this.markDenseFailed(embedder);
        return false;
      }
      for (let i = 0; i < batch.vectors.length; i++) {
        vectors.push(batch.vectors[i]);
      }
      model = batch.model.length > 0 ? batch.model : model;
    }
    if (vectors.length !== chunks.length) {
      return false;
    }
    // The corpus was replaced while the batches were in flight — only
    // `invalidate` does that, and installing now would pair fresh vectors with
    // the wrong chunks.
    if (this.fingerprint !== fingerprint || this.chunks !== chunks) {
      return false;
    }
    const installed = new KnowledgeEmbeddingBatch();
    installed.model = model;
    installed.dimension = dimension;
    installed.vectors = vectors;
    return this.prepareVectors(installed, embedder.signature(), embedder.recommendedWeight());
  }

  /**
   * Installs (or replaces) the dense side.
   *
   * Returns false when the batch cannot be paired with the current chunks — a
   * count mismatch, a malformed row, or a corpus that never built. Nothing is
   * installed in that case: half a vector set would score the wrong passage,
   * which is worse than having no dense side at all.
   *
   * `weight` says how much these vectors deserve to count in the fusion. It is
   * a parameter rather than a constant because it is a property of the embedder
   * that produced them, and the two embedders this code has measured want very
   * different numbers.
   */
  prepareVectors(batch: KnowledgeEmbeddingBatch, signature: string,
    weight: number = RRF_DEFAULT_VECTOR_WEIGHT): boolean {
    this.ensureBuilt();
    if (!batch || !Array.isArray(batch.vectors) || this.chunks.length === 0) {
      return false;
    }
    if (!this.vectorRetriever.build(batch.vectors, this.chunks)) {
      return false;
    }
    this.vectorSignature = signature;
    this.vectorWeight = Number.isFinite(weight) && weight > 0 ? weight : RRF_DEFAULT_VECTOR_WEIGHT;
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
    this.vectorWeight = RRF_DEFAULT_VECTOR_WEIGHT;
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
   *
   * The fusion weight is re-derived from the signature instead of being stored.
   * A signature already records which retriever produced the vectors, and the
   * weight is a property of that retriever, so deriving it keeps a warm start
   * ranking identically to the cold start that wrote the cache.
   */
  private restoreCachedVectors(snapshot: KnowledgeSnapshot): void {
    if (snapshot.vectors.length === 0 || snapshot.vectorSignature.length === 0) {
      return;
    }
    if (this.vectorRetriever.build(snapshot.vectors, snapshot.chunks)) {
      this.vectorSignature = snapshot.vectorSignature;
      this.vectorWeight = vectorWeightForSignature(snapshot.vectorSignature);
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


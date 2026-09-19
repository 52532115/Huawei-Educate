/*
 * Copyright (c) 2025 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 */

import { KnowledgeChunk, KnowledgeHit } from '../viewmodel/KnowledgeModels';
import { cosineSimilarity } from './KnowledgeEmbedding';

/**
 * RRF damping constant. The usual 60: rank 1 in one list scores 1/61 and rank
 * 20 scores 1/80, so agreement between the two retrievers outweighs a single
 * retriever's confidence. That is the property wanted here — BM25 is exact on
 * shared vocabulary and the vector side is fuzzier but broader, so a passage
 * both of them like is the safer bet than one BM25 is loud about alone.
 */
export const RRF_RANK_CONSTANT = 60;

/**
 * Weight of the dense list inside the fusion when the caller does not say.
 *
 * Kept as a knob rather than hardcoded because the offline dense side is a
 * hashed stand-in, and a measurement on the labelled set showed that trusting
 * it as an equal partner *lowers* Recall@3 — it has no semantic power, so its
 * disagreements with BM25 are mostly noise. Down-weighting it lets the dense
 * list break ties and contribute candidates without being able to displace a
 * confident lexical hit.
 */
export const RRF_DEFAULT_VECTOR_WEIGHT = 0.35;

/**
 * Weight for a dense list that came from a real embedding model.
 *
 * Equal weight, and that number is a measurement rather than a preference. On
 * the shipped corpus with a real 1024-dim model (see
 * `_test_artifacts/_eval_real_embedding.cjs`), sweeping the weight gave
 *
 * | weight | Recall@3 | MRR    | paraphrase |
 * |--------|----------|--------|------------|
 * | 0      | 0.8485   | 0.7273 | 0.7500     |  ← BM25 alone
 * | 0.35   | 0.9091   | 0.8636 | 0.8333     |  ← what the stand-in wants
 * | 1      | 0.9697   | 0.9545 | 1.0000     |  ← best
 *
 * so down-weighting a *semantic* retriever throws away exactly the property
 * that makes it worth its cost. The stand-in's 0.35 is not a guess that the
 * real model inherits; the two are different retrievers and get different
 * numbers. Whichever embedder installs the vectors declares its own.
 */
export const RRF_REMOTE_VECTOR_WEIGHT = 1;

/** Provenance labels, mirrored on `KnowledgeHit.retriever`. */
export const RETRIEVER_BM25 = 'bm25';
export const RETRIEVER_VECTOR = 'vector';
export const RETRIEVER_HYBRID = 'hybrid';

/** Dense similarity search over per-chunk vectors. Pure: no I/O, no clock. */
export class KnowledgeVectorRetriever {
  private vectors: number[][] = [];
  private chunks: KnowledgeChunk[] = [];

  /**
   * Replaces the contents. Returns false when the vectors cannot be paired with
   * the chunks — a partially applied set would score the wrong passage, so the
   * retriever stays empty and the caller keeps using BM25 alone.
   */
  build(vectors: number[][], chunks: KnowledgeChunk[]): boolean {
    if (!Array.isArray(vectors) || !Array.isArray(chunks)) {
      return false;
    }
    if (vectors.length === 0 || vectors.length !== chunks.length) {
      return false;
    }
    const width = vectors[0].length;
    if (width === 0) {
      return false;
    }
    for (let i = 0; i < vectors.length; i++) {
      if (!Array.isArray(vectors[i]) || vectors[i].length !== width) {
        return false;
      }
    }
    this.vectors = [];
    for (let i = 0; i < vectors.length; i++) {
      this.vectors.push(vectors[i].slice());
    }
    this.chunks = chunks.slice();
    return true;
  }

  size(): number {
    return this.vectors.length;
  }

  isEmpty(): boolean {
    return this.vectors.length === 0;
  }

  /** Width of the stored vectors, or 0 when empty. */
  dimension(): number {
    return this.vectors.length > 0 ? this.vectors[0].length : 0;
  }

  /** Copy, so the persisted snapshot cannot be mutated through this handle. */
  exportVectors(): number[][] {
    const out: number[][] = [];
    for (let i = 0; i < this.vectors.length; i++) {
      out.push(this.vectors[i].slice());
    }
    return out;
  }

  /**
   * Top-`topK` by cosine similarity. Non-positive similarities are dropped:
   * a passage that is orthogonal to the question is not a candidate, and
   * keeping it would let noise into the fusion.
   */
  search(queryVector: number[], topK: number = 5): KnowledgeHit[] {
    const hits: KnowledgeHit[] = [];
    if (this.isEmpty() || topK <= 0 || !Array.isArray(queryVector)) {
      return hits;
    }
    if (queryVector.length !== this.dimension()) {
      return hits;
    }

    const scored: KnowledgeHit[] = [];
    for (let i = 0; i < this.vectors.length; i++) {
      const similarity = cosineSimilarity(queryVector, this.vectors[i]);
      if (similarity <= 0) {
        continue;
      }
      const hit = new KnowledgeHit();
      hit.chunk = this.chunks[i];
      hit.score = Math.round(similarity * 10000) / 10000;
      hit.matchedTerms = [];
      hit.retriever = RETRIEVER_VECTOR;
      scored.push(hit);
    }
    scored.sort((a: KnowledgeHit, b: KnowledgeHit): number => {
      if (a.score !== b.score) {
        return b.score - a.score;
      }
      return a.chunk.chunkId < b.chunk.chunkId ? -1 : (a.chunk.chunkId > b.chunk.chunkId ? 1 : 0);
    });

    const limit = scored.length < topK ? scored.length : topK;
    for (let i = 0; i < limit; i++) {
      hits.push(scored[i]);
    }
    return hits;
  }
}

/** Accumulator for one chunk across both ranked lists. */
class FusedEntry {
  hit: KnowledgeHit = new KnowledgeHit();
  score: number = 0;
  terms: string[] = [];
}

function addRanking(entries: Map<string, FusedEntry>, hits: KnowledgeHit[],
  rankConstant: number, weight: number): void {
  if (!Array.isArray(hits) || weight <= 0) {
    return;
  }
  for (let i = 0; i < hits.length; i++) {
    const hit = hits[i];
    if (!hit || !hit.chunk || hit.chunk.chunkId.length === 0) {
      continue;
    }
    const key = hit.chunk.chunkId;
    const contribution = weight / (rankConstant + i + 1);
    const existing = entries.get(key);
    const entry = existing ? existing : new FusedEntry();
    if (!existing) {
      entry.hit = hit;
    }
    entry.score = entry.score + contribution;
    for (let t = 0; t < hit.matchedTerms.length; t++) {
      if (entry.terms.indexOf(hit.matchedTerms[t]) < 0) {
        entry.terms.push(hit.matchedTerms[t]);
      }
    }
    if (!existing) {
      entries.set(key, entry);
    }
  }
}

/**
 * Reciprocal rank fusion of the lexical and vector lists.
 *
 * The point of fusing ranks rather than scores is that BM25 scores and cosine
 * similarities are not on a shared scale — normalising them against each other
 * would be a guess, while ranks are directly comparable.
 *
 * Ties break on chunkId, so the merged order is a total order like every other
 * ranking in this feature. `score` on the result is the fused value, not a BM25
 * score; `retriever` records where the passage came from.
 */
export function fuseRankings(bm25Hits: KnowledgeHit[], vectorHits: KnowledgeHit[],
  topK: number, rankConstant: number = RRF_RANK_CONSTANT,
  vectorWeight: number = RRF_DEFAULT_VECTOR_WEIGHT): KnowledgeHit[] {
  const fused: KnowledgeHit[] = [];
  if (topK <= 0) {
    return fused;
  }
  const entries = new Map<string, FusedEntry>();
  // BM25 first, so a chunk found by both keeps its lexical hit object (and with
  // it the matched terms that explain why it was retrieved).
  addRanking(entries, bm25Hits, rankConstant, 1);
  addRanking(entries, vectorHits, rankConstant, vectorWeight);

  const ordered: FusedEntry[] = [];
  entries.forEach((entry: FusedEntry) => {
    ordered.push(entry);
  });
  ordered.sort((a: FusedEntry, b: FusedEntry): number => {
    if (a.score !== b.score) {
      return b.score - a.score;
    }
    const idA = a.hit.chunk.chunkId;
    const idB = b.hit.chunk.chunkId;
    return idA < idB ? -1 : (idA > idB ? 1 : 0);
  });

  const limit = ordered.length < topK ? ordered.length : topK;
  for (let i = 0; i < limit; i++) {
    const entry = ordered[i];
    const hit = entry.hit;
    hit.score = Math.round(entry.score * 10000) / 10000;
    hit.matchedTerms = entry.terms;
    hit.retriever = RETRIEVER_HYBRID;
    fused.push(hit);
  }
  return fused;
}

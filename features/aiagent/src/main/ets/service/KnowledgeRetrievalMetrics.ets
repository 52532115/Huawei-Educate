/*
 * Copyright (c) 2025 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 */

import { KnowledgeHit } from '../viewmodel/KnowledgeModels';
import { KnowledgeEvalCase } from './KnowledgeEvalSet';

/**
 * Grading depth. Three matches what the tutor actually sees: the prompt block
 * carries the top four passages, and a relevant passage sitting at rank 4 is
 * usually accompanied by a better one above it. Reporting at 3 keeps the number
 * from flattering the retriever.
 */
export const EVAL_DEFAULT_TOP_K = 3;

/** A one-character term would match nearly any chunk; such a label is a bug. */
const MIN_TERM_LENGTH = 2;

const NEWLINE = '\n';

/** What one labelled query produced. */
export class RetrievalCaseOutcome {
  query: string = '';
  bucket: string = '';
  /** 1-based rank of the first relevant passage; 0 when none was retrieved. */
  rank: number = 0;
  /** `1 / rank`, or 0 when nothing relevant was found. */
  reciprocalRank: number = 0;
  /** The answer term that matched — makes a pass diagnosable, not just green. */
  matchedTerm: string = '';
  /** What the retriever returned, so a miss can be read without re-running. */
  retrieved: string[] = [];
}

/** Aggregate quality over a set of queries. */
export class RetrievalReport {
  k: number = 0;
  /** Empty for the whole set, otherwise the bucket this report covers. */
  bucket: string = '';
  caseCount: number = 0;
  hitCount: number = 0;
  /**
   * Fraction of queries with at least one relevant passage in the top k. Binary
   * per query: this set has one answer location per question, so counting
   * "how many of the 3 slots were useful" would measure padding, not retrieval.
   */
  recallAtK: number = 0;
  /** Mean reciprocal rank — rewards putting the answer first, not just finding it. */
  mrr: number = 0;
  /** Queries with no relevant hit: the list worth reading before trusting a score. */
  misses: string[] = [];
}

/** The answer term this hit satisfies, or an empty string. */
export function matchedTermFor(hit: KnowledgeHit, evalCase: KnowledgeEvalCase): string {
  if (!hit || !hit.chunk || !evalCase || !Array.isArray(evalCase.expected)) {
    return '';
  }
  if (evalCase.docId.length > 0 && hit.chunk.docId !== evalCase.docId) {
    return '';
  }
  // Heading and body together: a label may name a section (heading) or a term
  // that only the prose carries (ARP, TIME_WAIT, ACID).
  const haystack = `${hit.chunk.headingPath}${NEWLINE}${hit.chunk.text}`;
  for (let i = 0; i < evalCase.expected.length; i++) {
    const term = evalCase.expected[i];
    if (typeof term !== 'string' || term.length < MIN_TERM_LENGTH) {
      continue;
    }
    if (haystack.indexOf(term) >= 0) {
      return term;
    }
  }
  return '';
}

/** True when this hit is graded relevant for this case. */
export function isRelevantHit(hit: KnowledgeHit, evalCase: KnowledgeEvalCase): boolean {
  return matchedTermFor(hit, evalCase).length > 0;
}

/** Scores one query's ranked hits. */
export function evaluateCase(hits: KnowledgeHit[], evalCase: KnowledgeEvalCase,
  k: number = EVAL_DEFAULT_TOP_K): RetrievalCaseOutcome {
  const outcome = new RetrievalCaseOutcome();
  outcome.query = evalCase ? evalCase.query : '';
  outcome.bucket = evalCase ? evalCase.bucket : '';
  if (!Array.isArray(hits)) {
    return outcome;
  }
  const limit = hits.length < k ? hits.length : k;
  for (let i = 0; i < limit; i++) {
    outcome.retrieved.push(hits[i].chunk ? hits[i].chunk.chunkId : '');
    if (outcome.rank === 0) {
      const term = matchedTermFor(hits[i], evalCase);
      if (term.length > 0) {
        outcome.rank = i + 1;
        outcome.reciprocalRank = 1 / (i + 1);
        outcome.matchedTerm = term;
      }
    }
  }
  return outcome;
}

/**
 * Aggregates outcomes. `bucket` of '' covers every case, otherwise only that
 * bucket — which is how the lexical/paraphrase split gets reported honestly
 * instead of being averaged into one comfortable number.
 */
export function summarize(outcomes: RetrievalCaseOutcome[], k: number,
  bucket: string = ''): RetrievalReport {
  const report = new RetrievalReport();
  report.k = k;
  report.bucket = bucket;
  if (!Array.isArray(outcomes)) {
    return report;
  }
  let rankSum = 0;
  for (let i = 0; i < outcomes.length; i++) {
    const outcome = outcomes[i];
    if (bucket.length > 0 && outcome.bucket !== bucket) {
      continue;
    }
    report.caseCount += 1;
    if (outcome.rank > 0) {
      report.hitCount += 1;
      rankSum += outcome.reciprocalRank;
    } else {
      report.misses.push(outcome.query);
    }
  }
  if (report.caseCount > 0) {
    report.recallAtK = round4(report.hitCount / report.caseCount);
    report.mrr = round4(rankSum / report.caseCount);
  }
  return report;
}

/** Four decimals, matching the rounding the retriever already applies to scores. */
function round4(value: number): number {
  return Math.round(value * 10000) / 10000;
}

/** e.g. "Recall@3 0.8667 · MRR 0.7222（30 题：命中 26）". */
export function formatRetrievalReport(report: RetrievalReport): string {
  const scope = report.bucket.length > 0 ? ` [${report.bucket}]` : '';
  return `Recall@${report.k} ${report.recallAtK.toFixed(4)} · ` +
    `MRR ${report.mrr.toFixed(4)}（${report.caseCount} 题：命中 ${report.hitCount}）${scope}`;
}

/*
 * Copyright (c) 2025 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 */

import { ErrorQuestionItem } from '../viewmodel/ChatModels';
import {
  AdaptivePracticeQuestion,
  ErrorBookPracticeCandidate,
  PracticeDifficulty,
} from '../viewmodel/AdaptivePracticeModels';

/** Marks questions rebuilt from the learner's own error book. */
export const SOURCE_ERROR_BOOK = 'error_book_review';

const UNCATEGORIZED_TAG = '未分类';
const DEMO_RECORD_PREFIX = 'err_default_';
const MIN_OPTION_COUNT = 2;
const MAX_OPTION_COUNT = 6;
const DAY_MS = 86400000;
const MAX_AGE_LEVEL = 4;
const MAX_REPEAT_FOR_SCORE = 3;
const AGE_WEIGHT = 0.6;
const REPEAT_WEIGHT = 0.4;
const DEFAULT_RECOMMENDATION = '先独立重做一遍，再对照当时的错误思路，检查是不是真的掌握了。';

/**
 * Mojibake detector, deliberately separate from
 * AdaptivePracticeService.containsMojibake: that one treats a half-width '?'
 * as corruption (killing any question that contains one) and carries an
 * invisible PUA character that is easy to blank out by accident — and a blank
 * marker makes indexOf('') match everything.
 *
 * Exported so the RAG chunker drops corrupted chunks with the same rule
 * instead of growing a second detector that can drift from this one.
 */
export function isCorruptedText(text: string): boolean {
  const markers: string[] = ['锛', '鏁', '璁', '缁', '绋', '楂', '鏈', '鍓', '�'];
  for (let i = 0; i < markers.length; i++) {
    if (text.indexOf(markers[i]) >= 0) {
      return true;
    }
  }
  for (let i = 0; i < text.length; i++) {
    const code = text.charCodeAt(i);
    if (code >= 0xE000 && code <= 0xF8FF) {
      return true;
    }
  }
  return false;
}

/**
 * The one place a knowledge tag is cleaned. Both the question-building path and
 * the mastery profile builder must call this: they key the same knowledge point,
 * so a corrupted category falling back to 未分类 on one side and staying raw on
 * the other would split one knowledge point into two mastery entries — the
 * learner would answer six questions about it and never see the number move.
 */
export function normalizeKnowledgeTag(raw: string): string {
  const tag = typeof raw === 'string' ? raw.trim() : '';
  if (tag.length === 0 || isCorruptedText(tag)) {
    return UNCATEGORIZED_TAG;
  }
  return tag;
}

/**
 * Bins "days since last reviewed" into 0..4. Exported because the cumulative
 * mastery model decays on exactly the same review cadence as the error book's
 * scoring — sharing the table keeps the two from drifting apart.
 */
export function reviewAgeLevel(ageDays: number): number {
  if (ageDays < 1) {
    return 0;
  }
  if (ageDays < 3) {
    return 1;
  }
  if (ageDays < 7) {
    return 2;
  }
  if (ageDays < 14) {
    return 3;
  }
  return MAX_AGE_LEVEL;
}

/**
 * Trims and collapses runs of whitespace so re-entries of the same question
 * group together. Used both to de-duplicate error-book records and to stop the
 * same question appearing twice in one session.
 */
export function normalizeQuestionTitle(title: string): string {
  const trimmed = typeof title === 'string' ? title.trim() : '';
  let result = '';
  let pendingSpace = false;
  for (let i = 0; i < trimmed.length; i++) {
    const ch = trimmed.charAt(i);
    if (ch === ' ' || ch === '\t' || ch === '\n' || ch === '\r') {
      pendingSpace = true;
      continue;
    }
    if (pendingSpace && result.length > 0) {
      result += ' ';
    }
    pendingSpace = false;
    result += ch;
  }
  return result;
}

/**
 * Turns error-book records into practice questions — "AI 出的题就是你错过的题".
 *
 * This class is a pure transformation: it never touches AppStorage or the file
 * system (ErrorBookPracticeSource.ets must stay free of both so it can be unit
 * tested without any I/O stub). Reading and writing the error book stays in
 * AdaptivePracticeService.
 *
 * Everything here is deterministic — `now` is always injected by the caller and
 * neither Date.now() nor Math.random() may be used, so the same input always
 * produces the same question order. That is what makes "review priority"
 * explainable and testable.
 */
export class ErrorBookPracticeSource {
  /**
   * Builds up to `count` questions, best-first. Returns fewer when the error
   * book cannot supply that many — filling the gap is the caller's job.
   *
   * `excludeIds` skips questions already shown (e.g. by an earlier round in the
   * same sitting), so asking for another set walks down the ranked list instead
   * of returning the same top N.
   */
  buildQuestions(items: ErrorQuestionItem[], count: number, now: number,
    excludeIds: string[] = []): AdaptivePracticeQuestion[] {
    const questions: AdaptivePracticeQuestion[] = [];
    if (count <= 0) {
      return questions;
    }
    const candidates = this.buildCandidates(items, now);
    const pool = excludeIds.length > 0
      ? candidates.filter((c: ErrorBookPracticeCandidate) => excludeIds.indexOf(this.questionIdFor(c)) < 0)
      : candidates;
    const picked = this.pickTopByRoundRobin(pool, count);
    for (let i = 0; i < picked.length; i++) {
      questions.push(this.toQuestion(picked[i]));
    }
    return questions;
  }

  /**
   * Cleans, de-duplicates and ranks the records. Exported shape so the offline
   * tests can assert each stage without building a whole session.
   */
  buildCandidates(items: ErrorQuestionItem[], now: number): ErrorBookPracticeCandidate[] {
    const candidates: ErrorBookPracticeCandidate[] = [];
    if (!Array.isArray(items)) {
      return candidates;
    }

    const valid: ErrorBookPracticeCandidate[] = [];
    for (let i = 0; i < items.length; i++) {
      const candidate = this.normalizeRecord(items[i], now);
      if (candidate) {
        valid.push(candidate);
      }
    }

    // The manual entry page has no de-duplication at all, so the same question
    // saved twice yields two records with different ids. Group them and let the
    // group size count as extra failures.
    const groups = new Map<string, ErrorBookPracticeCandidate[]>();
    for (let i = 0; i < valid.length; i++) {
      const candidate = valid[i];
      const bucket = groups.get(candidate.normalizedTitle);
      if (bucket) {
        bucket.push(candidate);
      } else {
        groups.set(candidate.normalizedTitle, [candidate]);
      }
    }

    groups.forEach((bucket: ErrorBookPracticeCandidate[]) => {
      let best = bucket[0];
      for (let i = 1; i < bucket.length; i++) {
        if (this.compareCandidates(bucket[i], best) < 0) {
          best = bucket[i];
        }
      }
      if (bucket.length > best.repeatCount) {
        best.repeatCount = bucket.length;
        best.difficulty = this.resolveDifficulty(best.repeatCount);
        best.score = this.computeScore(best, now);
      }
      candidates.push(best);
    });

    candidates.sort((a: ErrorBookPracticeCandidate, b: ErrorBookPracticeCandidate) => this.compareCandidates(a, b));
    return candidates;
  }

  // ---------- cleaning ----------

  private normalizeRecord(item: ErrorQuestionItem, now: number): ErrorBookPracticeCandidate | null {
    if (!item) {
      return null;
    }

    const title = typeof item.title === 'string' ? item.title.trim() : '';
    if (title.length === 0 || isCorruptedText(title)) {
      return null;
    }

    const options = this.resolveOptions(item.options);
    if (options.length < MIN_OPTION_COUNT) {
      return null;
    }

    const correctIndex = this.resolveCorrectIndex(item.correctIndex, options.length);
    if (correctIndex < 0) {
      return null;
    }

    const recordId = typeof item.id === 'string' ? item.id : '';
    const createTime = this.resolveCreateTime(item.createTime, now);

    const candidate = new ErrorBookPracticeCandidate();
    candidate.recordId = recordId;
    candidate.title = title;
    candidate.normalizedTitle = normalizeQuestionTitle(title);
    candidate.options = options;
    candidate.correctIndex = correctIndex;
    candidate.knowledgeTag = this.resolveTag(item.category);
    candidate.userNote = typeof item.userNote === 'string' ? item.userNote : '';
    candidate.mistakeReason = typeof item.mistakeReason === 'string' ? item.mistakeReason : '';
    candidate.analysis = typeof item.analysis === 'string' ? item.analysis : '';
    candidate.createTime = createTime;
    candidate.lastActivityTime = this.resolveLastActivity(createTime, item.lastReviewTime, now);
    candidate.isDemo = recordId.indexOf(DEMO_RECORD_PREFIX) === 0;
    candidate.repeatCount = this.resolveRepeatCount(item.wrongCount);
    candidate.difficulty = this.resolveDifficulty(candidate.repeatCount);
    candidate.score = this.computeScore(candidate, now);
    return candidate;
  }

  /**
   * Keeps option positions intact. Blank entries are rejected instead of
   * filtered: dropping "['A', '', 'C']"[1] would shift every later index and
   * silently point correctIndex at the wrong answer.
   */
  private resolveOptions(raw: string[]): string[] {
    const options: string[] = [];
    if (!Array.isArray(raw) || raw.length < MIN_OPTION_COUNT) {
      return options;
    }
    for (let i = 0; i < raw.length && i < MAX_OPTION_COUNT; i++) {
      const option = raw[i];
      if (typeof option !== 'string' || option.trim().length === 0) {
        return [];
      }
      options.push(option.trim());
    }
    return options.length >= MIN_OPTION_COUNT ? options : [];
  }

  private resolveCorrectIndex(raw: number, optionCount: number): number {
    if (typeof raw !== 'number' || !Number.isFinite(raw)) {
      return -1;
    }
    const index = Math.floor(raw);
    if (index < 0 || index >= optionCount) {
      return -1;
    }
    return index;
  }

  private resolveTag(raw: string): string {
    return normalizeKnowledgeTag(raw);
  }

  private resolveCreateTime(raw: number, now: number): number {
    // An unknown timestamp is treated as "just recorded": it ranks lowest by
    // age and has to earn its place through repeatCount instead.
    if (typeof raw !== 'number' || !Number.isFinite(raw) || raw <= 0) {
      return now;
    }
    return raw > now ? now : raw;
  }

  private resolveLastActivity(createTime: number, rawReview: number, now: number): number {
    let last = createTime;
    if (typeof rawReview === 'number' && Number.isFinite(rawReview) && rawReview > last) {
      last = rawReview;
    }
    return last > now ? now : last;
  }

  private resolveRepeatCount(raw: number): number {
    if (typeof raw === 'number' && Number.isFinite(raw) && raw > 1) {
      return Math.floor(raw);
    }
    return 1;
  }

  // ---------- scoring ----------

  /**
   * 0..100 review priority:
   *   score = 100 * (0.6 * ageLevel/4 + 0.4 * (repeats-1)/2)
   *
   * Age is binned rather than linear so the number is explainable and free of
   * floating-point noise; it is measured from max(createTime, lastReviewTime),
   * which is standard spaced-repetition semantics — a question you just failed
   * again resets its age but climbs back through repeatCount.
   */
  private computeScore(candidate: ErrorBookPracticeCandidate, now: number): number {
    const ageDays = (now - candidate.lastActivityTime) / DAY_MS;
    const ageW = this.ageLevel(ageDays) / MAX_AGE_LEVEL;
    let repeats = candidate.repeatCount;
    if (repeats < 1) {
      repeats = 1;
    }
    if (repeats > MAX_REPEAT_FOR_SCORE) {
      repeats = MAX_REPEAT_FOR_SCORE;
    }
    const repeatW = (repeats - 1) / (MAX_REPEAT_FOR_SCORE - 1);
    return Math.round(100 * (AGE_WEIGHT * ageW + REPEAT_WEIGHT * repeatW));
  }

  private ageLevel(ageDays: number): number {
    return reviewAgeLevel(ageDays);
  }

  private resolveDifficulty(repeatCount: number): PracticeDifficulty {
    if (repeatCount >= 3) {
      return PracticeDifficulty.HARD;
    }
    if (repeatCount === 2) {
      return PracticeDifficulty.MEDIUM;
    }
    return PracticeDifficulty.BASIC;
  }

  /**
   * Total order, so the same input always yields the same sequence. It never
   * looks at array positions: the error book is written with unshift, so index
   * order carries no meaning.
   */
  private compareCandidates(a: ErrorBookPracticeCandidate, b: ErrorBookPracticeCandidate): number {
    if (a.score !== b.score) {
      return b.score - a.score;
    }
    if (a.isDemo !== b.isDemo) {
      return a.isDemo ? 1 : -1;
    }
    if (a.lastActivityTime !== b.lastActivityTime) {
      return a.lastActivityTime < b.lastActivityTime ? -1 : 1;
    }
    if (a.createTime !== b.createTime) {
      return a.createTime < b.createTime ? -1 : 1;
    }
    if (a.title !== b.title) {
      return a.title < b.title ? -1 : 1;
    }
    if (a.recordId === b.recordId) {
      return 0;
    }
    return a.recordId < b.recordId ? -1 : 1;
  }

  // ---------- selection ----------

  /**
   * Round-robin across knowledge tags so six questions never all come from the
   * same topic: the first pass takes one from each tag, the second pass the
   * runner-up, and so on. Buckets are ordered by their best question, so weak
   * topics still lead.
   */
  private pickTopByRoundRobin(candidates: ErrorBookPracticeCandidate[],
    count: number): ErrorBookPracticeCandidate[] {
    const picked: ErrorBookPracticeCandidate[] = [];
    if (count <= 0) {
      return picked;
    }

    const buckets = new Map<string, ErrorBookPracticeCandidate[]>();
    for (let i = 0; i < candidates.length; i++) {
      const candidate = candidates[i];
      const bucket = buckets.get(candidate.knowledgeTag);
      if (bucket) {
        bucket.push(candidate);
      } else {
        buckets.set(candidate.knowledgeTag, [candidate]);
      }
    }

    const lists: ErrorBookPracticeCandidate[][] = [];
    buckets.forEach((bucket: ErrorBookPracticeCandidate[]) => {
      lists.push(bucket);
    });
    lists.sort((a: ErrorBookPracticeCandidate[], b: ErrorBookPracticeCandidate[]) => this.compareCandidates(a[0], b[0]));

    let round = 0;
    while (picked.length < count) {
      let progressed = false;
      for (let i = 0; i < lists.length && picked.length < count; i++) {
        if (round < lists[i].length) {
          picked.push(lists[i][round]);
          progressed = true;
        }
      }
      if (!progressed) {
        break;
      }
      round += 1;
    }
    return picked;
  }

  // ---------- output ----------

  /** Stable id for a candidate, derived without touching any clock or RNG. */
  private questionIdFor(candidate: ErrorBookPracticeCandidate): string {
    return candidate.recordId.length > 0
      ? `q_err_${candidate.recordId}`
      : `q_err_h_${this.stableHash(candidate.normalizedTitle)}`;
  }

  private toQuestion(candidate: ErrorBookPracticeCandidate): AdaptivePracticeQuestion {
    const id = this.questionIdFor(candidate);
    // Demo records are never written back: answering one wrong appends a real
    // record of the learner's own instead of editing the shipped sample data.
    const sourceRecordId = candidate.isDemo ? '' : candidate.recordId;
    return new AdaptivePracticeQuestion(
      id,
      candidate.title,
      [...candidate.options],
      candidate.correctIndex,
      candidate.knowledgeTag,
      candidate.difficulty,
      SOURCE_ERROR_BOOK,
      this.buildExplanation(candidate),
      this.buildRecommendation(candidate),
      sourceRecordId,
    );
  }

  /**
   * The error book has no model answer, so the explanation is built from what
   * the learner themselves wrote — their note and the reason they got it wrong.
   */
  private buildExplanation(candidate: ErrorBookPracticeCandidate): string {
    const label = String.fromCharCode(65 + candidate.correctIndex);
    let text = `正确答案是 ${label}。这道题来自你的错题本。`;
    if (candidate.userNote.length > 0) {
      text += `当时的笔记：${candidate.userNote}`;
    }
    if (candidate.mistakeReason.length > 0) {
      text += `当时的错误思路：${candidate.mistakeReason}`;
    }
    return text;
  }

  private buildRecommendation(candidate: ErrorBookPracticeCandidate): string {
    if (candidate.analysis.length > 0) {
      return candidate.analysis;
    }
    if (candidate.repeatCount >= 3) {
      return `这道题已经重做错 ${candidate.repeatCount} 次，建议先回到「${candidate.knowledgeTag}」的概念和例题，再回来重做。`;
    }
    return DEFAULT_RECOMMENDATION;
  }

  /**
   * Polynomial rolling hash in base36 — stable across runs, unlike
   * Date.now()-based ids. Arithmetic only (mod 2^31-1), no bitwise operators.
   */
  private stableHash(text: string): string {
    let hash = 0;
    for (let i = 0; i < text.length; i++) {
      hash = (hash * 31 + text.charCodeAt(i)) % 2147483647;
    }
    return hash.toString(36);
  }
}

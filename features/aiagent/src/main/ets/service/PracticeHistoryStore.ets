/*
 * Copyright (c) 2025 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 */

import fileIo from '@ohos.file.fs';
import { reviewAgeLevel } from './ErrorBookPracticeSource';

const PRACTICE_HISTORY_KEY = 'PracticeHistory';
const PRACTICE_HISTORY_FILE = '/practiceHistory.json';
/** Stamped so a later revision can migrate the file instead of guessing. */
const PRACTICE_HISTORY_VERSION = 1;
/** Bounds the file: the 61st knowledge point evicts the least recently practiced. */
const MAX_HISTORY_ENTRIES = 60;
const DAY_MS = 86400000;

export const MASTERY_MIN = 0;
export const MASTERY_MAX = 100;
/** One correct answer is worth +6, one wrong answer costs −8. */
export const MASTERY_CORRECT_GAIN = 6;
export const MASTERY_WRONG_LOSS = 8;
/**
 * Where a knowledge point starts when it has no history yet. Equal to the old
 * per-session heuristic's "first error" value (AdaptivePracticeService), so a
 * learner upgrading mid-course does not see every number jump.
 */
export const DEFAULT_SEED_MASTERY = 68;
/** Below this a knowledge point still needs work, matching the practice page's
 *  colour threshold (getMasteryColor) and DataCollectService's weak-point cut-off. */
export const WEAK_MASTERY_THRESHOLD = 60;

/** The accumulated mastery of one knowledge point. */
export class PracticeHistoryEntry {
  tag: string = '';
  /** Stored, un-decayed value, always within [0, 100]. Decay is applied on read. */
  mastery: number = 0;
  attempts: number = 0;
  correct: number = 0;
  /** 0 means "never practiced" — such an entry is never persisted. */
  lastPracticeTime: number = 0;

  constructor(tag: string = '', mastery: number = 0, attempts: number = 0,
    correct: number = 0, lastPracticeTime: number = 0) {
    this.tag = tag;
    this.mastery = mastery;
    this.attempts = attempts;
    this.correct = correct;
    this.lastPracticeTime = lastPracticeTime;
  }
}

/** Aggregate counters. Derived from the entries on read, never persisted — a
 *  stored total is a second source of truth that can drift out of sync. */
export class PracticeHistoryTotals {
  attempts: number = 0;
  correct: number = 0;
  tags: number = 0;
  lastPracticeTime: number = 0;
}

/** The on-disk shape. Separate from PracticeHistoryEntry so a corrupt or older
 *  field can be rejected field-by-field during rehydration. */
interface PracticeHistoryEntryRecord {
  tag: string;
  mastery: number;
  attempts: number;
  correct: number;
  lastPracticeTime: number;
}

interface PracticeHistoryRecord {
  version: number;
  entries: PracticeHistoryEntryRecord[];
}

// ---------- pure logic (no I/O, unit-testable without any stub) ----------

/** Keeps a stored mastery inside [0, 100]; anything not a finite number reads as 0. */
export function clampMastery(value: number): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    return MASTERY_MIN;
  }
  if (value < MASTERY_MIN) {
    return MASTERY_MIN;
  }
  return value > MASTERY_MAX ? MASTERY_MAX : value;
}

/**
 * How much a knowledge point has faded, by how long it has gone unpracticed.
 * An explicit table rather than arithmetic so the numbers stay explainable, and
 * so an out-of-range level cannot silently skip the penalty.
 */
export function decayPenaltyForAgeLevel(level: number): number {
  switch (level) {
    case 0:
      return 0;
    case 1:
      return 4;
    case 2:
      return 8;
    case 3:
      return 12;
    case 4:
      return 16;
    default:
      return 16;
  }
}

/**
 * Decay for a knowledge point last practiced at `lastPracticeTime`, on the same
 * review cadence the error book already scores by (reviewAgeLevel).
 * No timestamp means no anchor to fade from, so nothing is subtracted.
 */
export function masteryDecay(lastPracticeTime: number, now: number): number {
  if (typeof lastPracticeTime !== 'number' || !Number.isFinite(lastPracticeTime) ||
    lastPracticeTime <= 0 || typeof now !== 'number' || !Number.isFinite(now)) {
    return 0;
  }
  return decayPenaltyForAgeLevel(reviewAgeLevel((now - lastPracticeTime) / DAY_MS));
}

/** What the learner should see: the stored value minus however much has faded. */
export function effectiveMasteryOf(stored: number, lastPracticeTime: number, now: number): number {
  return clampMastery(clampMastery(stored) - masteryDecay(lastPracticeTime, now));
}

/**
 * Pure accumulation: the delta applies to the stored value, never to the
 * decayed one. Rebasing onto the effective value would mean a read (which
 * applies decay) could change what a write produces.
 */
export function nextStoredMastery(stored: number, isCorrect: boolean): number {
  const delta = isCorrect ? MASTERY_CORRECT_GAIN : -MASTERY_WRONG_LOSS;
  return clampMastery(clampMastery(stored) + delta);
}

/** e.g. "已练 6 次 · 正确 4 次（67%）· 今天练过". Empty for a never-practiced tag,
 *  so the caller can skip rendering the row entirely. */
export function buildPracticeHistoryLine(attempts: number, correct: number,
  lastPracticeTime: number, now: number): string {
  if (!Number.isFinite(attempts) || attempts <= 0) {
    return '';
  }
  const safeCorrect = Number.isFinite(correct) && correct > 0 ? Math.floor(correct) : 0;
  const cappedCorrect = safeCorrect > attempts ? attempts : safeCorrect;
  const accuracy = Math.round(100 * cappedCorrect / attempts);
  return `已练 ${attempts} 次 · 正确 ${cappedCorrect} 次（${accuracy}%）· ${formatRecency(lastPracticeTime, now)}`;
}

/** e.g. "累计练习 42 题 · 正确 31 题（74%）· 覆盖 9 个知识点". */
export function buildHistorySummaryLine(attempts: number, correct: number, tags: number): string {
  if (!Number.isFinite(attempts) || attempts <= 0) {
    return '还没有累计练习记录，做完一组就会开始统计。';
  }
  const safeCorrect = Number.isFinite(correct) && correct > 0 ? Math.floor(correct) : 0;
  const cappedCorrect = safeCorrect > attempts ? attempts : safeCorrect;
  const safeTags = Number.isFinite(tags) && tags > 0 ? Math.floor(tags) : 0;
  const accuracy = Math.round(100 * cappedCorrect / attempts);
  return `累计练习 ${attempts} 题 · 正确 ${cappedCorrect} 题（${accuracy}%）· 覆盖 ${safeTags} 个知识点`;
}

function formatRecency(lastPracticeTime: number, now: number): string {
  if (typeof lastPracticeTime !== 'number' || !Number.isFinite(lastPracticeTime) ||
    lastPracticeTime <= 0 || typeof now !== 'number' || !Number.isFinite(now)) {
    return '暂无记录';
  }
  const days = Math.floor((now - lastPracticeTime) / DAY_MS);
  if (days <= 0) {
    return '今天练过';
  }
  return `${days} 天前练过`;
}

// ---------- persistence ----------

/**
 * Cumulative per-knowledge-point mastery, plus a compact practice history.
 *
 * This is the piece the practice flow was missing: mastery used to be recomputed
 * from the raw error book on every session, so practising a topic ten times
 * showed exactly what seeing it once showed, and a topic left alone for a month
 * never came back. Here a correct answer raises the stored value, a wrong one
 * lowers it, and time fades it — across sessions and across restarts.
 *
 * `now` is always injected by the caller: nothing in this file reads a clock, so
 * the same inputs always produce the same file.
 */
export class PracticeHistoryStore {
  /**
   * Records one answered question and persists immediately — the learner may
   * abandon the session on the very next tap, and the answer still counts.
   * Returns the new stored mastery, or -1 when the tag is unusable (nothing written).
   */
  recordAnswer(tag: string, isCorrect: boolean, now: number, seedMastery: number): number {
    const key = typeof tag === 'string' ? tag.trim() : '';
    if (key.length === 0) {
      return -1;
    }

    const entries = this.loadEntries();
    let entry: PracticeHistoryEntry | undefined = undefined;
    for (let i = 0; i < entries.length; i++) {
      if (entries[i].tag === key) {
        entry = entries[i];
        break;
      }
    }

    let target: PracticeHistoryEntry;
    if (entry === undefined) {
      target = new PracticeHistoryEntry(key, clampMastery(seedMastery), 0, 0, 0);
      entries.push(target);
    } else {
      target = entry;
    }

    target.mastery = nextStoredMastery(target.mastery, isCorrect);
    target.attempts += 1;
    if (isCorrect) {
      target.correct += 1;
    }
    target.lastPracticeTime = now;

    this.saveEntries(this.evictOverflow(entries, key));
    return target.mastery;
  }

  /** A copy, so callers cannot mutate stored state. attempts === 0 means "no history". */
  getEntry(tag: string): PracticeHistoryEntry {
    const key = typeof tag === 'string' ? tag.trim() : '';
    if (key.length === 0) {
      return new PracticeHistoryEntry();
    }
    const entries = this.loadEntries();
    for (let i = 0; i < entries.length; i++) {
      if (entries[i].tag === key) {
        const found = entries[i];
        return new PracticeHistoryEntry(found.tag, found.mastery, found.attempts,
          found.correct, found.lastPracticeTime);
      }
    }
    return new PracticeHistoryEntry();
  }

  /** Decayed mastery, or -1 when the knowledge point has never been practiced. */
  getEffectiveMastery(tag: string, now: number): number {
    const entry = this.getEntry(tag);
    if (entry.attempts <= 0) {
      return -1;
    }
    return effectiveMasteryOf(entry.mastery, entry.lastPracticeTime, now);
  }

  /**
   * Decays an entry the caller already holds. Same answer as
   * getEffectiveMastery, without re-reading storage for every tag.
   */
  effectiveMasteryFor(entry: PracticeHistoryEntry, now: number): number {
    if (entry.attempts <= 0) {
      return -1;
    }
    return effectiveMasteryOf(entry.mastery, entry.lastPracticeTime, now);
  }

  /** Every knowledge point that has been practiced at least once, as copies. */
  getPracticedEntries(): PracticeHistoryEntry[] {
    const result: PracticeHistoryEntry[] = [];
    const entries = this.loadEntries();
    for (let i = 0; i < entries.length; i++) {
      const entry = entries[i];
      if (entry.attempts > 0) {
        result.push(new PracticeHistoryEntry(entry.tag, entry.mastery, entry.attempts,
          entry.correct, entry.lastPracticeTime));
      }
    }
    return result;
  }

  hasHistory(tag: string): boolean {
    return this.getEntry(tag).attempts > 0;
  }

  getTotals(): PracticeHistoryTotals {
    const totals = new PracticeHistoryTotals();
    const entries = this.loadEntries();
    for (let i = 0; i < entries.length; i++) {
      const entry = entries[i];
      totals.attempts += entry.attempts;
      totals.correct += entry.correct;
      totals.tags += 1;
      if (entry.lastPracticeTime > totals.lastPracticeTime) {
        totals.lastPracticeTime = entry.lastPracticeTime;
      }
    }
    return totals;
  }

  /**
   * Knowledge points that have been practiced and are still below the weak
   * threshold, worst first. Deterministic: mastery ascending, then tag.
   */
  weakestTags(now: number, limit: number): string[] {
    const result: string[] = [];
    if (!Number.isFinite(limit) || limit <= 0) {
      return result;
    }
    const weak: PracticeHistoryEntry[] = [];
    const entries = this.loadEntries();
    for (let i = 0; i < entries.length; i++) {
      const entry = entries[i];
      if (entry.attempts <= 0) {
        continue;
      }
      if (effectiveMasteryOf(entry.mastery, entry.lastPracticeTime, now) < WEAK_MASTERY_THRESHOLD) {
        weak.push(entry);
      }
    }
    weak.sort((a: PracticeHistoryEntry, b: PracticeHistoryEntry): number => {
      const masteryA = effectiveMasteryOf(a.mastery, a.lastPracticeTime, now);
      const masteryB = effectiveMasteryOf(b.mastery, b.lastPracticeTime, now);
      if (masteryA !== masteryB) {
        return masteryA - masteryB;
      }
      return a.tag < b.tag ? -1 : (a.tag > b.tag ? 1 : 0);
    });
    for (let i = 0; i < weak.length && i < limit; i++) {
      result.push(weak[i].tag);
    }
    return result;
  }

  /** Wipes the practice history. The learner profile is cleared separately. */
  clearHistory(): void {
    this.saveEntries([]);
  }

  // ---------- file I/O ----------

  /**
   * Keeps the newest MAX_HISTORY_ENTRIES, and never the tag that was just
   * written — an eviction pass must not undo the answer being recorded.
   */
  private evictOverflow(entries: PracticeHistoryEntry[], protectedTag: string): PracticeHistoryEntry[] {
    if (entries.length <= MAX_HISTORY_ENTRIES) {
      return entries;
    }
    const protectedEntry = this.findById(entries, protectedTag);
    if (protectedEntry === null) {
      // Should not happen — the caller just wrote it — but dropping the newest
      // row is worse than keeping one entry too many.
      return entries;
    }
    const others: PracticeHistoryEntry[] = [];
    for (let i = 0; i < entries.length; i++) {
      if (entries[i] !== protectedEntry) {
        others.push(entries[i]);
      }
    }
    others.sort((a: PracticeHistoryEntry, b: PracticeHistoryEntry): number => {
      if (a.lastPracticeTime !== b.lastPracticeTime) {
        return a.lastPracticeTime - b.lastPracticeTime;
      }
      return a.tag < b.tag ? -1 : (a.tag > b.tag ? 1 : 0);
    });
    // Keep the newest MAX_HISTORY_ENTRIES - 1 others, then the just-written row,
    // whose fresh lastPracticeTime puts it beyond the next eviction.
    const result: PracticeHistoryEntry[] = [];
    const keepFrom = others.length - (MAX_HISTORY_ENTRIES - 1);
    for (let i = keepFrom > 0 ? keepFrom : 0; i < others.length; i++) {
      result.push(others[i]);
    }
    result.push(protectedEntry);
    return result;
  }

  private findById(entries: PracticeHistoryEntry[], tag: string): PracticeHistoryEntry | null {
    for (let i = 0; i < entries.length; i++) {
      if (entries[i].tag === tag) {
        return entries[i];
      }
    }
    return null;
  }

  private loadEntries(): PracticeHistoryEntry[] {
    let json = '';
    try {
      json = AppStorage.get<string>(PRACTICE_HISTORY_KEY) || '';
    } catch (e) {
      // AppStorage may not be initialized during preview or unit tests.
    }

    if (json.length === 0) {
      const filePath = this.getHistoryFilePath();
      if (filePath) {
        try {
          json = fileIo.readTextSync(filePath);
        } catch (e) {
          // No persisted history yet.
        }
      }
    }

    if (json.length === 0) {
      return [];
    }
    try {
      const record = JSON.parse(json) as PracticeHistoryRecord;
      return this.recordToEntries(record);
    } catch (e) {
      // A corrupt payload must not cost the learner their next answer.
      return [];
    }
  }

  private saveEntries(entries: PracticeHistoryEntry[]): void {
    const records: PracticeHistoryEntryRecord[] = [];
    for (let i = 0; i < entries.length; i++) {
      const entry = entries[i];
      const row: PracticeHistoryEntryRecord = {
        tag: entry.tag,
        mastery: entry.mastery,
        attempts: entry.attempts,
        correct: entry.correct,
        lastPracticeTime: entry.lastPracticeTime,
      };
      records.push(row);
    }
    const payload: PracticeHistoryRecord = {
      version: PRACTICE_HISTORY_VERSION,
      entries: records,
    };
    const json = JSON.stringify(payload);

    try {
      AppStorage.setOrCreate(PRACTICE_HISTORY_KEY, json);
    } catch (e) {
      // Same as above: the in-memory copy is best-effort.
    }

    const filePath = this.getHistoryFilePath();
    if (!filePath) {
      return;
    }
    try {
      const file: fileIo.File = fileIo.openSync(filePath, 0o2 | 0o100 | 0o1000);
      fileIo.writeSync(file.fd, json);
      fileIo.closeSync(file);
    } catch (e) {
      // Persist failure must not interrupt practice.
    }
  }

  /** Field by field, because this is the boundary where corrupt data enters. */
  private recordToEntries(record: PracticeHistoryRecord): PracticeHistoryEntry[] {
    const entries: PracticeHistoryEntry[] = [];
    if (!record || !Array.isArray(record.entries)) {
      return entries;
    }
    for (let i = 0; i < record.entries.length; i++) {
      const raw = record.entries[i];
      if (!raw) {
        continue;
      }
      const tag = typeof raw.tag === 'string' ? raw.tag.trim() : '';
      if (tag.length === 0) {
        continue;
      }
      // First occurrence wins: a duplicated tag would otherwise double-count.
      let duplicated = false;
      for (let j = 0; j < entries.length; j++) {
        if (entries[j].tag === tag) {
          duplicated = true;
          break;
        }
      }
      if (duplicated) {
        continue;
      }
      // An entry exists only because something was answered: attempts is the
      // invariant, so a row without a positive count is dropped rather than repaired.
      if (typeof raw.attempts !== 'number' || !Number.isFinite(raw.attempts) || raw.attempts <= 0) {
        continue;
      }
      const attempts = Math.floor(raw.attempts);
      let correct = 0;
      if (typeof raw.correct === 'number' && Number.isFinite(raw.correct) && raw.correct > 0) {
        correct = Math.min(Math.floor(raw.correct), attempts);
      }
      const mastery = typeof raw.mastery === 'number' && Number.isFinite(raw.mastery)
        ? clampMastery(raw.mastery)
        : DEFAULT_SEED_MASTERY;
      const lastPracticeTime = typeof raw.lastPracticeTime === 'number' &&
        Number.isFinite(raw.lastPracticeTime) && raw.lastPracticeTime > 0
        ? raw.lastPracticeTime
        : 0;
      entries.push(new PracticeHistoryEntry(tag, mastery, attempts, correct, lastPracticeTime));
    }
    return entries;
  }

  private getHistoryFilePath(): string | null {
    const filesDir = AppStorage.get<string>('filesDir');
    if (!filesDir) {
      return null;
    }
    return filesDir + PRACTICE_HISTORY_FILE;
  }
}

/*
 * Copyright (c) 2025 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 */

import fileIo from '@ohos.file.fs';
import {
  AdaptivePracticeQuestion,
  PracticeDifficulty,
} from '../viewmodel/AdaptivePracticeModels';
import {
  SOURCE_AI_GENERATED,
  SYNTHESIS_CONTRACT_VERSION,
} from './PracticeQuestionSynthesizer';

/** One file, next to the other `filesDir` payloads (errorBook.json, …). */
const POOL_FILE = '/generatedQuestions.json';
/** Directory holding every per-app data file, published by the app entry. */
const FILES_DIR_KEY = 'filesDir';

/**
 * Most questions kept per knowledge point.
 *
 * Eight is a few rounds' worth of "换一组" and comfortably more than one call
 * produces, so a healthy pool rarely reaches it. The cap exists for the case
 * where it is not healthy: synthesis runs on every round, and without a ceiling
 * a learner who keeps tapping would grow the file without bound.
 */
export const MAX_QUESTIONS_PER_TAG = 8;

/**
 * Most knowledge points kept at all.
 *
 * The pool is keyed by whatever tag the learner's weak points happen to have,
 * and an agent can drive arbitrary ones ("帮我出几道傅里叶变换的题"), so the
 * number of tags is not bounded by anything upstream. When the cap is reached
 * the least recently written tag is dropped whole.
 */
export const MAX_TAGS = 24;

/** Persisted shape of one question. Mirrors the model, minus runtime state. */
interface PoolQuestionRecord {
  id: string;
  title: string;
  options: string[];
  correctIndex: number;
  knowledgeTag: string;
  difficulty: string;
  explanation: string;
  recommendation: string;
  citation: string;
}

/**
 * Persisted shape of one knowledge point. `seq` is the pool-wide write counter
 * at the moment this tag was last written — the eviction order, and the reason
 * it is stored rather than derived from array position.
 */
interface PoolTagRecord {
  tag: string;
  seq: number;
  questions: PoolQuestionRecord[];
}

interface PoolDocument {
  version: number;
  fingerprint: string;
  nextSeq: number;
  tags: PoolTagRecord[];
}

/**
 * Cache of model-written practice questions, keyed by knowledge point.
 *
 * **Why a file and not AppStorage.** Same reason as the retrieval snapshot: a
 * few dozen questions is a hundred-odd KB of text that is read once per launch
 * and never by the UI, and AppStorage would hold a parsed copy of it in memory
 * for the whole app run. It is also genuinely persistent state — the questions
 * cost money to write, so losing them on every launch would mean paying again
 * for the same content.
 *
 * **Two-key invalidation, one of them deliberate.** A change to the lecture
 * corpus makes cached questions describe material that no longer exists, and a
 * change to the prompt/response contract makes them describe a shape the parser
 * no longer accepts. Either one drops the whole pool rather than keeping a
 * mixture that would make a parsing bug look like a content problem.
 *
 * The corpus fingerprint arrives *late* — it is only known once the retrieval
 * index is built — and starts out empty. An empty fingerprint therefore means
 * "not known yet, change nothing", never "the corpus changed": treating it as a
 * change would wipe the cache on every cold-start first frame.
 *
 * **All IO is best effort.** No file system, an unreadable file or a corrupt
 * record costs this launch's cache and nothing else; the practice engine falls
 * back to the shipped bank, which is what it did before any of this existed.
 */
export class GeneratedQuestionPool {
  private doc: PoolDocument | null = null;
  private loaded: boolean = false;
  /** Bumped so tests can tell a persisted write from an in-memory-only change. */
  private saveAttempts: number = 0;
  private saveSuccesses: number = 0;

  /** The path is resolved per call, so a late `filesDir` still works. */
  private poolPath(): string | null {
    let filesDir = '';
    try {
      filesDir = AppStorage.get<string>(FILES_DIR_KEY) || '';
    } catch (e) {
      // AppStorage is absent in unit tests and during preview.
      return null;
    }
    if (filesDir.length === 0) {
      return null;
    }
    return filesDir + POOL_FILE;
  }

  /**
   * Declares which corpus the pool belongs to, dropping everything if it has
   * changed. Passing '' is a no-op — see the class comment.
   */
  setCorpusFingerprint(fingerprint: string): void {
    this.ensureLoaded();
    if (fingerprint.length === 0) {
      return;
    }
    const doc = this.document();
    if (doc.fingerprint === fingerprint) {
      return;
    }
    const fresh: PoolDocument = {
      version: SYNTHESIS_CONTRACT_VERSION,
      fingerprint: fingerprint,
      nextSeq: 0,
      tags: [],
    };
    this.doc = fresh;
    this.persist();
  }

  /** Read-only view of the corpus fingerprint currently in force. */
  getCorpusFingerprint(): string {
    this.ensureLoaded();
    return this.document().fingerprint;
  }

  /**
   * Adds questions under one knowledge point, returning how many were new.
   *
   * Re-adding a question already held is a no-op: ids are derived from the
   * knowledge point and the stem, so the second synthesis of the same question
   * collapses onto the first instead of filling the pool with near-duplicates.
   */
  add(tag: string, questions: AdaptivePracticeQuestion[]): number {
    this.ensureLoaded();
    if (tag.length === 0 || questions.length === 0) {
      return 0;
    }
    const doc = this.document();
    let record: PoolTagRecord | null = this.findTag(doc, tag);
    if (record === null) {
      this.evictTagsIfNeeded(doc);
      const created: PoolTagRecord = { tag: tag, seq: 0, questions: [] };
      doc.tags.push(created);
      record = created;
    }

    let added = 0;
    for (let i = 0; i < questions.length; i++) {
      const question = questions[i];
      if (question.id.length === 0 || this.hasQuestion(record, question.id)) {
        continue;
      }
      record.questions.push(this.toRecord(question));
      added += 1;
    }
    if (added === 0) {
      return 0;
    }

    // Oldest first: the pool is a rolling buffer, and the questions a learner
    // has not seen in the longest time are the ones worth recycling.
    while (record.questions.length > MAX_QUESTIONS_PER_TAG) {
      record.questions.shift();
    }
    doc.nextSeq += 1;
    record.seq = doc.nextSeq;
    this.persist();
    return added;
  }

  /**
   * Up to `limit` cached questions for a knowledge point, freshest-first skipped.
   *
   * `excludeIds` is the caller's already-served list, so this obeys the same
   * "换一组" contract as every other layer. Returned questions are copies: the
   * practice session mutates them (selection, submission, mastery guard) and
   * that state must not leak back into the pool.
   */
  getForTag(tag: string, excludeIds: string[], limit: number): AdaptivePracticeQuestion[] {
    this.ensureLoaded();
    const questions: AdaptivePracticeQuestion[] = [];
    if (tag.length === 0 || limit <= 0) {
      return questions;
    }
    const record = this.findTag(this.document(), tag);
    if (record === null) {
      return questions;
    }
    for (let i = 0; i < record.questions.length && questions.length < limit; i++) {
      const question = this.fromRecord(record.questions[i]);
      if (question === null || excludeIds.indexOf(question.id) >= 0) {
        continue;
      }
      questions.push(question);
    }
    return questions;
  }

  /** How many questions are held for one knowledge point. */
  countForTag(tag: string): number {
    this.ensureLoaded();
    const record = this.findTag(this.document(), tag);
    return record === null ? 0 : record.questions.length;
  }

  /** Total questions held, across every knowledge point. */
  size(): number {
    this.ensureLoaded();
    const doc = this.document();
    let total = 0;
    for (let i = 0; i < doc.tags.length; i++) {
      total += doc.tags[i].questions.length;
    }
    return total;
  }

  /** How many knowledge points are held. */
  tagCount(): number {
    this.ensureLoaded();
    return this.document().tags.length;
  }

  /** Persistence counters, so a test can tell writing from not writing. */
  getSaveStats(): number[] {
    return [this.saveAttempts, this.saveSuccesses];
  }

  /** Drops everything, in memory and on disk. */
  reset(): void {
    this.ensureLoaded();
    this.doc = null;
    this.loaded = true;
    const path = this.poolPath();
    if (path === null) {
      return;
    }
    try {
      fileIo.unlinkSync(path);
    } catch (e) {
      // Nothing cached; nothing to do.
    }
  }

  /** Loads the file once, if there is one. Later writes keep `loaded` true. */
  private ensureLoaded(): void {
    if (this.loaded) {
      return;
    }
    this.loaded = true;
    const path = this.poolPath();
    if (path === null) {
      return;
    }
    let json = '';
    try {
      json = fileIo.readTextSync(path);
    } catch (e) {
      // First launch, or the file was cleared.
      return;
    }
    const decoded = decodePool(json);
    if (decoded !== null) {
      this.doc = decoded;
    }
  }

  /** The document, created empty on first use. */
  private document(): PoolDocument {
    if (this.doc === null) {
      const empty: PoolDocument = {
        version: SYNTHESIS_CONTRACT_VERSION,
        fingerprint: '',
        nextSeq: 0,
        tags: [],
      };
      this.doc = empty;
    }
    return this.doc;
  }

  /** True when this knowledge point already holds a question with this id. */
  private hasQuestion(record: PoolTagRecord, id: string): boolean {
    for (let i = 0; i < record.questions.length; i++) {
      if (record.questions[i].id === id) {
        return true;
      }
    }
    return false;
  }

  private findTag(doc: PoolDocument, tag: string): PoolTagRecord | null {
    for (let i = 0; i < doc.tags.length; i++) {
      if (doc.tags[i].tag === tag) {
        return doc.tags[i];
      }
    }
    return null;
  }

  private evictTagsIfNeeded(doc: PoolDocument): void {
    while (doc.tags.length >= MAX_TAGS) {
      let oldest = 0;
      for (let i = 1; i < doc.tags.length; i++) {
        if (doc.tags[i].seq < doc.tags[oldest].seq) {
          oldest = i;
        }
      }
      doc.tags.splice(oldest, 1);
    }
  }

  private toRecord(question: AdaptivePracticeQuestion): PoolQuestionRecord {
    const record: PoolQuestionRecord = {
      id: question.id,
      title: question.title,
      options: question.options,
      correctIndex: question.correctIndex,
      knowledgeTag: question.knowledgeTag,
      difficulty: question.difficulty,
      explanation: question.explanation,
      recommendation: question.recommendation,
      citation: question.citation,
    };
    return record;
  }

  /** Rebuilds a question, or null when the record cannot be trusted. */
  private fromRecord(record: Object): AdaptivePracticeQuestion | null {
    if (record === null || typeof record !== 'object') {
      return null;
    }
    // Read through a loose view: this object came out of a file, so what is
    // there is whatever was written, not what the interface claims. Typed as
    // `Object` rather than the interface for that reason — ArkTS rejects the
    // cast from a type with no index signature to `Record<string, Object>`.
    const raw = record as Record<string, Object>;
    const id = readString(raw, 'id');
    const title = readString(raw, 'title');
    const options = readStringArray(raw, 'options');
    if (id.length === 0 || title.length === 0 || options.length < 2) {
      return null;
    }
    const correctIndex = raw['correctIndex'];
    if (typeof correctIndex !== 'number' || !Number.isInteger(correctIndex) ||
      correctIndex < 0 || correctIndex >= options.length) {
      return null;
    }
    const question = new AdaptivePracticeQuestion(
      id,
      title,
      options,
      correctIndex,
      readString(raw, 'knowledgeTag'),
      parseDifficulty(readString(raw, 'difficulty')),
      SOURCE_AI_GENERATED,
      readString(raw, 'explanation'),
      readString(raw, 'recommendation'),
    );
    question.citation = readString(raw, 'citation');
    return question;
  }

  /** Best-effort write. A cache that cannot be written is never a broken pool. */
  private persist(): void {
    const path = this.poolPath();
    if (path === null || this.doc === null) {
      return;
    }
    this.saveAttempts += 1;
    const json = JSON.stringify(this.doc);
    try {
      const file: fileIo.File = fileIo.openSync(path, 0o2 | 0o100 | 0o1000);
      fileIo.writeSync(file.fd, json);
      fileIo.closeSync(file);
      this.saveSuccesses += 1;
    } catch (e) {
      // Slow launch, never a failed one.
    }
  }
}

/** Difficulty enum from its persisted string, defaulting to the entry level. */
function parseDifficulty(raw: string): PracticeDifficulty {
  if (raw === PracticeDifficulty.MEDIUM) {
    return PracticeDifficulty.MEDIUM;
  }
  if (raw === PracticeDifficulty.HARD) {
    return PracticeDifficulty.HARD;
  }
  return PracticeDifficulty.BASIC;
}

/** String field of a decoded object; '' when absent or of another type. */
function readString(raw: Record<string, Object>, key: string): string {
  const value = raw[key];
  return typeof value === 'string' ? value : '';
}

/** String array field of a decoded object, keeping only the string entries. */
function readStringArray(raw: Record<string, Object>, key: string): string[] {
  const values: string[] = [];
  const value = raw[key];
  if (!Array.isArray(value)) {
    return values;
  }
  // Annotated so the element type is `Object` and not the `any` a bare index
  // read of a narrowed array produces — ArkTS rejects `any` outright.
  const items = value as Object[];
  for (let i = 0; i < items.length; i++) {
    const item = items[i];
    if (typeof item === 'string') {
      values.push(item);
    }
  }
  return values;
}

/**
 * Reads a stored pool, or null when it cannot be used.
 *
 * Rejects the whole document on a contract-version mismatch — questions written
 * under another contract may not even parse under this one — and drops
 * individual malformed records rather than the batch, because a single bad
 * entry is not a reason to pay for the other ninety again.
 */
function decodePool(json: string): PoolDocument | null {
  if (typeof json !== 'string' || json.length === 0) {
    return null;
  }
  let parsed: PoolDocument | null = null;
  try {
    parsed = JSON.parse(json) as PoolDocument;
  } catch (e) {
    return null;
  }
  if (parsed === null || typeof parsed !== 'object') {
    return null;
  }
  if (parsed.version !== SYNTHESIS_CONTRACT_VERSION) {
    return null;
  }
  if (!Array.isArray(parsed.tags)) {
    return null;
  }

  const tags: PoolTagRecord[] = [];
  for (let i = 0; i < parsed.tags.length; i++) {
    const rawTag = parsed.tags[i];
    if (rawTag === null || typeof rawTag !== 'object' || typeof rawTag.tag !== 'string' ||
      rawTag.tag.length === 0 || !Array.isArray(rawTag.questions)) {
      continue;
    }
    const record: PoolTagRecord = {
      tag: rawTag.tag,
      seq: typeof rawTag.seq === 'number' ? rawTag.seq : 0,
      questions: rawTag.questions,
    };
    tags.push(record);
  }

  const document: PoolDocument = {
    version: SYNTHESIS_CONTRACT_VERSION,
    fingerprint: typeof parsed.fingerprint === 'string' ? parsed.fingerprint : '',
    nextSeq: typeof parsed.nextSeq === 'number' ? parsed.nextSeq : 0,
    tags: tags,
  };
  return document;
}

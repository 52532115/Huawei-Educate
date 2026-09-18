/*
 * Copyright (c) 2025 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 */

/**
 * Where a knowledge chunk came from. A string enum so it survives the
 * AppStorage/file round-trip without an implicit enum conversion.
 */
export enum KnowledgeSourceType {
  /** Course metadata shipped with the app (data/cs_courses.json). */
  COURSE = 'course',
  /** A question the practice engine can hand out. */
  QUESTION_BANK = 'question_bank',
  /** Something the learner wrote: an error-book note. */
  ERROR_BOOK = 'error_book',
  /** Long-form course notes once they exist. */
  COURSE_NOTE = 'course_note',
}

/**
 * A raw knowledge item before chunking. `text` is Markdown-ish: `##` headings
 * become chunk boundaries, so the chunker can attach a heading path (and with
 * it a citation) to every slice.
 */
export class KnowledgeDocument {
  docId: string = '';
  title: string = '';
  courseId: string = '';
  /** Raw tag; the chunker normalises it through the single shared cleaner. */
  knowledgeTag: string = '';
  sourceType: KnowledgeSourceType = KnowledgeSourceType.COURSE_NOTE;
  text: string = '';
}

/**
 * A retrievable slice of one document. `chunkId` is derived from the document
 * id plus the ordinal, so it is stable across runs — which is what lets the
 * offline tests assert exact retrieval results.
 */
export class KnowledgeChunk {
  chunkId: string = '';
  docId: string = '';
  /** Nearest heading; falls back to the document title. Indexed with a boost. */
  title: string = '';
  /** Ancestor headings joined with ' › ', e.g. "数据结构 › 树 › 二叉搜索树". */
  headingPath: string = '';
  courseId: string = '';
  knowledgeTag: string = '';
  sourceType: KnowledgeSourceType = KnowledgeSourceType.COURSE_NOTE;
  text: string = '';
  chunkIndex: number = 0;
}

/**
 * One scored retrieval result. `score` is rounded to four decimals so test
 * assertions compare exactly instead of chasing floating-point noise.
 */
export class KnowledgeHit {
  chunk: KnowledgeChunk = new KnowledgeChunk();
  score: number = 0;
  /** Query terms that actually matched, in query order. */
  matchedTerms: string[] = [];
  /**
   * Which retriever produced this hit — `bm25`, `vector` or `hybrid`. Kept so a
   * fused ranking stays explicable: without it, "why is this passage here"
   * cannot be answered once the two lists are merged.
   */
  retriever: string = 'bm25';
}

/**
 * Serializable form of a `KnowledgeIndex`, chunk list excluded.
 *
 * The postings are flattened into one `[chunkIndex, termFrequency, ...]` array
 * per term rather than an array of objects: the object form is ~3x larger as
 * JSON, and this file is written to flash on device.
 *
 * `chunks` is deliberately not part of this — the snapshot owns the chunk list
 * once, and the two are always written and validated together.
 */
export class KnowledgeIndexState {
  chunkLengths: number[] = [];
  averageLength: number = 0;
  /** Terms of the inverted index, in the order `postings` follows. */
  terms: string[] = [];
  /** `postings[i]` belongs to `terms[i]`, as flat (chunkIndex, termFrequency) pairs. */
  postings: number[][] = [];
}

/** Index size summary, shown in the UI and asserted in the tests. */
export class KnowledgeIndexStats {
  chunkCount: number = 0;
  termCount: number = 0;
  avgChunkLength: number = 0;
}

/** Course input for building the seed corpus out of data the app already has. */
export class SeedCourseInput {
  courseId: string = '';
  title: string = '';
  category: string = '';
  description: string = '';
}

/**
 * Long-form course notes for one course, before they are turned into documents.
 *
 * `markdown` opens with a `## <course title>` heading, so every chunk cut from
 * the note carries the course name in its citation path ("计算机网络 › 传输层 ›
 * TCP 三次握手") without the adapter having to prefix anything.
 */
export class SeedLectureInput {
  courseId: string = '';
  title: string = '';
  category: string = '';
  /** Knowledge area; deliberately the same string the question bank tags carry. */
  knowledgeTag: string = '';
  markdown: string = '';
}

/** Question input for building the seed corpus out of the practice bank. */
export class SeedQuestionInput {
  questionId: string = '';
  title: string = '';
  options: string[] = [];
  correctIndex: number = -1;
  knowledgeTag: string = '';
  explanation: string = '';
  recommendation: string = '';
}

/**
 * Everything the retriever can reuse across process launches.
 *
 * `fingerprint` covers the chunk list and `signature` covers the index
 * implementation (tokenizer + field weighting), so a change to either the
 * corpus or the retrieval code invalidates the file automatically — a stale
 * index can never be served silently.
 *
 * `vectors` is the payload that actually justifies persistence: for BM25 the
 * saved work is one tokenizing pass, but an embedding cannot be recomputed
 * cheaply at all (locally it is arithmetic over every chunk; through the proxy
 * it is a network round-trip). It is parallel to `chunks` and empty when no
 * embedder is active.
 */
export class KnowledgeSnapshot {
  version: number = 0;
  fingerprint: string = '';
  signature: string = '';
  /**
   * Which embedder produced `vectors`. Kept apart from `signature` because the
   * postings stay valid when only the embedder changes — dropping the whole
   * snapshot for a new embedding model would throw away work that is still
   * correct.
   */
  vectorSignature: string = '';
  chunks: KnowledgeChunk[] = [];
  state: KnowledgeIndexState = new KnowledgeIndexState();
  vectors: number[][] = [];
}

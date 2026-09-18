/*
 * Copyright (c) 2025 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 */

import { KnowledgeChunk, KnowledgeDocument } from '../viewmodel/KnowledgeModels';
import { isCorruptedText, normalizeKnowledgeTag } from './ErrorBookPracticeSource';

/** Paragraphs are merged until the chunk would pass this many characters. */
export const CHUNK_TARGET_CHARS = 320;
/** Hard upper bound for one segment; longer paragraphs get split. */
export const CHUNK_MAX_CHARS = 560;
/**
 * Chunks shorter than this carry no retrieval signal and are dropped. Kept low
 * on purpose: a multiple-choice option block ("A. SYN / B. SYN+ACK") is only
 * ~17 characters, and dropping it would leave the most quotable part of a
 * question unretrievable. Relevance is the retriever's job, not the chunker's.
 */
export const CHUNK_MIN_CHARS = 15;
/** How much of the previous chunk is repeated at the top of the next one. */
export const CHUNK_OVERLAP_CHARS = 60;

const MAX_HEADING_LEVEL = 6;
const HEADING_PATH_SEPARATOR = ' › ';
const FENCE_MARKER = '```';
const BOUNDARY_CHARS = '。！？；.!?;';
const NEWLINE = '\n';

/** A parsed Markdown heading. */
export class HeadingLine {
  level: number = 0;
  text: string = '';

  constructor(level: number, text: string) {
    this.level = level;
    this.text = text;
  }
}

/** One heading plus everything under it, with its ancestor path resolved. */
export class KnowledgeSection {
  level: number = 0;
  heading: string = '';
  body: string = '';
  headingPath: string[] = [];
}

/**
 * Recognises `#`..`######` headings. Line-based and regex-free on purpose:
 * ArkTS has no need for a regex engine here, and the project's other Markdown
 * parser (components/MarkdownText.ets) deliberately avoids them too.
 *
 * `#######` (seven hashes) is not a heading, matching MarkdownText's rule, and
 * a hash run not followed by a space is ordinary text (`#话题`).
 */
export function parseHeadingLine(line: string): HeadingLine | null {
  const trimmed = line.trim();
  if (trimmed.length === 0 || trimmed.charAt(0) !== '#') {
    return null;
  }
  let level = 0;
  while (level < trimmed.length && trimmed.charAt(level) === '#') {
    level += 1;
  }
  if (level > MAX_HEADING_LEVEL) {
    return null;
  }
  if (level >= trimmed.length) {
    return null;
  }
  const rest = trimmed.substring(level);
  if (rest.charAt(0) !== ' ') {
    return null;
  }
  const heading = rest.trim();
  if (heading.length === 0) {
    return null;
  }
  return new HeadingLine(level, heading);
}

/**
 * Turns Markdown-ish documents into retrievable chunks.
 *
 * This class is a pure transformation: no AppStorage, no file system, no
 * clock, no randomness. The same documents always produce the same chunks in
 * the same order, which is what makes retrieval results assertable offline —
 * the same contract ErrorBookPracticeSource follows.
 */
export class KnowledgeChunker {
  /**
   * Chunks every document in order. Chunk ids are `k_<docId>_<ordinal>`, so a
   * test can name an expected hit exactly instead of asserting on prose.
   */
  buildChunks(docs: KnowledgeDocument[]): KnowledgeChunk[] {
    const chunks: KnowledgeChunk[] = [];
    if (!Array.isArray(docs)) {
      return chunks;
    }
    for (let i = 0; i < docs.length; i++) {
      this.appendDocumentChunks(docs[i], chunks);
    }
    return chunks;
  }

  /**
   * Splits a document on its headings, resolving each section's ancestor path
   * in a single pass. Sections are returned in document order.
   */
  splitIntoSections(text: string): KnowledgeSection[] {
    const sections: KnowledgeSection[] = [];
    if (typeof text !== 'string' || text.length === 0) {
      return sections;
    }

    const lines = text.split(NEWLINE);
    const stack: string[] = [];
    let current: KnowledgeSection | null = null;
    let inFence = false;

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      // A heading inside a fenced code block is code, not structure.
      if (line.trim().indexOf(FENCE_MARKER) === 0) {
        inFence = !inFence;
      }
      const heading: HeadingLine | null = inFence ? null : parseHeadingLine(line);

      if (heading !== null) {
        if (current !== null) {
          sections.push(current);
        }
        // Sibling or shallower heading: drop deeper entries before pushing.
        while (stack.length >= heading.level) {
          stack.pop();
        }
        stack.push(heading.text);
        const section = new KnowledgeSection();
        section.level = heading.level;
        section.heading = heading.text;
        section.body = '';
        section.headingPath = stack.slice();
        current = section;
        continue;
      }

      if (current === null) {
        // Text before the first heading: keep it, with no citation path.
        const preamble = new KnowledgeSection();
        preamble.headingPath = [];
        current = preamble;
      }
      current.body += `${line}${NEWLINE}`;
    }

    if (current !== null) {
      sections.push(current);
    }
    return sections;
  }

  // ---------- document -> chunks ----------

  private appendDocumentChunks(doc: KnowledgeDocument, out: KnowledgeChunk[]): void {
    if (!doc) {
      return;
    }
    const docId = typeof doc.docId === 'string' ? doc.docId.trim() : '';
    if (docId.length === 0) {
      return;
    }
    const text = typeof doc.text === 'string' ? doc.text : '';
    if (text.trim().length === 0) {
      return;
    }

    const sections = this.splitIntoSections(text);
    const fallbackTitle = typeof doc.title === 'string' && doc.title.trim().length > 0 ? doc.title.trim() : docId;
    // Overlap carries the tail of the last emitted chunk, including across
    // sections: a fact that straddles a heading boundary stays retrievable.
    let previousTail = '';
    let chunkIndex = 0;

    for (let s = 0; s < sections.length; s++) {
      const section = sections[s];
      const segments = this.splitSegments(section.body);
      if (segments.length === 0) {
        continue;
      }
      const packed = this.packSegments(segments);

      for (let p = 0; p < packed.length; p++) {
        const bodyText = packed[p].trim();
        if (bodyText.length === 0) {
          continue;
        }
        const assembled = previousTail.length > 0 ? `${previousTail}${NEWLINE}${bodyText}` : bodyText;
        if (assembled.length < CHUNK_MIN_CHARS) {
          continue;
        }
        // Corrupted text is dropped rather than indexed: a mojibake chunk can
        // only match mojibake, and it would pollute the cited source line.
        if (isCorruptedText(assembled)) {
          continue;
        }

        const chunk = new KnowledgeChunk();
        chunk.chunkId = `k_${docId}_${chunkIndex}`;
        chunk.docId = docId;
        chunk.title = section.heading.length > 0 ? section.heading : fallbackTitle;
        chunk.headingPath =
          section.headingPath.length > 0 ? section.headingPath.join(HEADING_PATH_SEPARATOR) : '';
        chunk.courseId = typeof doc.courseId === 'string' ? doc.courseId : '';
        chunk.knowledgeTag = normalizeKnowledgeTag(doc.knowledgeTag);
        chunk.sourceType = doc.sourceType;
        chunk.text = assembled;
        chunk.chunkIndex = chunkIndex;

        out.push(chunk);
        // The ordinal only advances for chunks that survive, so the id
        // sequence has no gaps for a test to have to guess at.
        chunkIndex += 1;
        previousTail = this.tailOverlap(assembled, CHUNK_OVERLAP_CHARS);
      }
    }
  }

  // ---------- text -> segments ----------

  /**
   * Paragraphs first, then any paragraph that alone exceeds CHUNK_MAX_CHARS is
   * split. A blank line is the paragraph boundary; runs of non-blank lines
   * (list items, an option block) stay together.
   */
  private splitSegments(body: string): string[] {
    const segments: string[] = [];
    const paragraphs = this.splitParagraphs(body);
    for (let i = 0; i < paragraphs.length; i++) {
      const paragraph = paragraphs[i];
      if (paragraph.length <= CHUNK_MAX_CHARS) {
        segments.push(paragraph);
        continue;
      }
      const pieces = this.splitLongText(paragraph, CHUNK_MAX_CHARS);
      for (let p = 0; p < pieces.length; p++) {
        segments.push(pieces[p]);
      }
    }
    return segments;
  }

  private splitParagraphs(body: string): string[] {
    const paragraphs: string[] = [];
    const lines = body.split(NEWLINE);
    let buffer = '';
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();
      if (line.length === 0) {
        if (buffer.length > 0) {
          paragraphs.push(buffer);
          buffer = '';
        }
        continue;
      }
      buffer = buffer.length > 0 ? `${buffer}${NEWLINE}${line}` : line;
    }
    if (buffer.length > 0) {
      paragraphs.push(buffer);
    }
    return paragraphs;
  }

  /**
   * Cuts an oversized paragraph at sentence boundaries where possible. The
   * search walks backwards from the limit so the piece stays as close to
   * CHUNK_MAX_CHARS as the text allows; with no boundary in range (a long
   * unbroken token) it hard-cuts, because a chunk that exceeds the budget is
   * worse than one that splits mid-token.
   */
  private splitLongText(text: string, maxLen: number): string[] {
    const pieces: string[] = [];
    let start = 0;
    while (start < text.length) {
      const limit = start + maxLen;
      if (limit >= text.length) {
        pieces.push(text.substring(start));
        break;
      }
      let cut = limit;
      for (let i = limit; i > start; i--) {
        if (this.isBoundary(text.charAt(i - 1))) {
          cut = i;
          break;
        }
      }
      pieces.push(text.substring(start, cut));
      start = cut;
    }
    return pieces;
  }

  /** Greedily merges segments while the result stays within the target. */
  private packSegments(segments: string[]): string[] {
    const packed: string[] = [];
    let current = '';
    for (let i = 0; i < segments.length; i++) {
      const segment = segments[i];
      if (current.length === 0) {
        current = segment;
        continue;
      }
      if (current.length + 1 + segment.length <= CHUNK_TARGET_CHARS) {
        current = `${current}${NEWLINE}${segment}`;
        continue;
      }
      packed.push(current);
      current = segment;
    }
    if (current.length > 0) {
      packed.push(current);
    }
    return packed;
  }

  /**
   * Tail of the previous chunk, advanced to the next sentence boundary so the
   * overlap reads as whole clauses. Returns '' for a chunk no longer than the
   * overlap budget — repeating it in full would duplicate the whole chunk.
   */
  private tailOverlap(text: string, chars: number): string {
    if (chars <= 0 || text.length <= chars) {
      return '';
    }
    let tail = text.substring(text.length - chars);
    for (let i = 0; i < tail.length; i++) {
      if (this.isBoundary(tail.charAt(i))) {
        tail = tail.substring(i + 1);
        break;
      }
    }
    return tail.trim();
  }

  private isBoundary(ch: string): boolean {
    return ch === NEWLINE || BOUNDARY_CHARS.indexOf(ch) >= 0;
  }
}

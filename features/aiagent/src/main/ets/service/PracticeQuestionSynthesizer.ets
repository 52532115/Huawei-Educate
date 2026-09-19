/*
 * Copyright (c) 2025 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 */

import {
  isCorruptedText,
  normalizeKnowledgeTag,
  normalizeQuestionTitle,
  stableTextHash,
} from './ErrorBookPracticeSource';
import {
  AdaptivePracticeQuestion,
  PracticeDifficulty,
} from '../viewmodel/AdaptivePracticeModels';

/**
 * Marks a question the model wrote from retrieved lecture passages, as opposed
 * to the shipped bank or an error-book record. The practice page and the
 * session store treat it like any other question; only the wording of the
 * provenance chip differs.
 */
export const SOURCE_AI_GENERATED = 'ai_generated';

/**
 * Version of the prompt + response contract.
 *
 * Stored next to every cached question. Bump it and the whole cache is dropped,
 * because a question written under an older contract may have been parsed out
 * of a shape this version no longer accepts — silently mixing the two would
 * make a parsing bug look like a content problem.
 */
export const SYNTHESIS_CONTRACT_VERSION = 1;

/** How many questions one call asks for. */
export const SYNTHESIS_QUESTION_COUNT = 3;

/**
 * Fewest total characters of lecture text worth sending.
 *
 * Retrieval always returns *something* — `topK` hits, however weak — so
 * "did the search return results" is not a usable guard. A short total is the
 * honest signal that the corpus does not really cover the knowledge point, and
 * a model asked to write about material it was not given writes fiction. Below
 * this, the caller skips synthesis entirely and falls back to the shipped bank.
 */
const MIN_MATERIAL_CHARS = 80;

/** A single passage shorter than this contributes nothing worth grounding on. */
const MIN_PASSAGE_CHARS = 20;

/** Shape a generated question must have to be usable at all. */
const MIN_OPTION_COUNT = 3;
const MAX_OPTION_COUNT = 4;
const MIN_TITLE_CHARS = 8;
const MAX_TITLE_CHARS = 200;

/** Fallback advice when the model omits `recommendation`. */
const DEFAULT_RECOMMENDATION = '把这个知识点对应的讲义段落重新读一遍，再不看答案做一次。';

/**
 * How many distinct citations one question may carry.
 *
 * The model is not asked which passage it used — see `citationOf` for the
 * measurement that settled that — so a question is attributed to the whole set
 * of passages it was written from. More than a couple means the retrieval
 * scattered across unrelated documents and the attribution stops being useful,
 * so the tail is dropped rather than listed.
 */
const MAX_CITATIONS = 2;

/** One retrieved passage, reduced to what the prompt and the citation need. */
export class SynthesisPassage {
  citation: string;
  knowledgeTag: string;
  text: string;

  constructor(citation: string, knowledgeTag: string, text: string) {
    this.citation = citation;
    this.knowledgeTag = knowledgeTag;
    this.text = text;
  }
}

/** Everything one synthesis call needs. */
export class SynthesisRequest {
  tag: string;
  difficulty: PracticeDifficulty;
  passages: SynthesisPassage[];
  count: number;

  constructor(tag: string, difficulty: PracticeDifficulty, passages: SynthesisPassage[],
    count: number = SYNTHESIS_QUESTION_COUNT) {
    this.tag = tag;
    this.difficulty = difficulty;
    this.passages = passages;
    this.count = count;
  }
}

/** The two messages to send upstream. A class because ArkTS wants named literals. */
export class SynthesisPrompt {
  system: string;
  user: string;

  constructor(system: string, user: string) {
    this.system = system;
    this.user = user;
  }
}

/**
 * Turns retrieved lecture passages into practice questions.
 *
 * **Purity.** No clock, no randomness, no file system, no network: the prompt
 * goes out through `buildPrompt`, the answer comes back through `parseResponse`,
 * and everything in between is a pure function of its arguments. That is what
 * lets the whole contract — prompt shape, tolerance, rejection rules — be
 * exercised offline, which matters because this is the one place where a model
 * writes content that ends up in front of a learner.
 *
 * **The response contract was measured, not assumed.** One real call to the
 * configured backend returned a bare JSON array, four options per question,
 * `correctIndex` 0-based, no `A.` prefixes — every field as asked. It also
 * ignored `sourceIndex` completely, in all three questions, even though the
 * field was spelled out in the system prompt. Two consequences, both load
 * bearing:
 *
 *   1. `parseResponse` still peels a fenced code block and surrounding prose
 *      before parsing, because a different model behind the same server may not
 *      be as literal, and the tolerance costs one `indexOf`;
 *   2. provenance is the *set* of passages the question was written from
 *      (`citationOf`) rather than one precise index — the precise version simply
 *      does not exist in the reply. The chip says 「参考讲义」 for that reason.
 *
 * **Rejection is deliberate and per-question.** A stem with no options, an
 * answer index outside the options, a garbled title: each is dropped on its own
 * and the rest of the batch survives. Partial output is worth more than none,
 * and the caller's fallback is the shipped bank either way.
 */
export class PracticeQuestionSynthesizer {
  /**
   * True when the retrieved material is worth asking about. See
   * `MIN_MATERIAL_CHARS` for why "retrieval returned hits" is not the test.
   */
  isMaterialSufficient(passages: SynthesisPassage[]): boolean {
    return this.usablePassageChars(passages) >= MIN_MATERIAL_CHARS;
  }

  /** Total usable characters across the passages, truncated ones excluded. */
  usablePassageChars(passages: SynthesisPassage[]): number {
    let total = 0;
    for (let i = 0; i < passages.length; i++) {
      const text = this.textOf(passages[i].text);
      if (text.length >= MIN_PASSAGE_CHARS && !isCorruptedText(text)) {
        total += text.length;
      }
    }
    return total;
  }

  /**
   * Citation text for a question written from these passages: the distinct
   * passage headings, joined, capped at `MAX_CITATIONS`.
   *
   * Deliberately not "the passage this question came from" — the model is not
   * told to report that and does not, so the honest label is the material it
   * was given.
   */
  citationOf(passages: SynthesisPassage[]): string {
    const parts: string[] = [];
    for (let i = 0; i < passages.length && parts.length < MAX_CITATIONS; i++) {
      const citation = this.textOf(passages[i].citation);
      if (citation.length > 0 && !isCorruptedText(citation) && parts.indexOf(citation) < 0) {
        parts.push(citation);
      }
    }
    return parts.join('；');
  }

  /**
   * System + user messages for one call.
   *
   * The rules that matter are the grounding ones: only the passages below, no
   * outside knowledge, say nothing rather than invent. The output shape is
   * stated once, plainly, and the field list is closed — an easier contract to
   * follow than a JSON schema, and it measured 100% compliance.
   */
  buildPrompt(request: SynthesisRequest): SynthesisPrompt {
    const system = '你是一位出题老师，负责根据给定的讲义片段出单选题。\n' +
      '\n' +
      '出题规则：\n' +
      '1. 只能依据【讲义片段】出题，不得引入片段之外的知识；片段没讲到的内容不许出现。\n' +
      '2. 每题恰好 4 个选项，有且只有一个正确答案，其余 3 个是常见误解或概念混淆。\n' +
      '3. 考察理解与应用，不要出"片段第几句写了什么"这类背诵题。\n' +
      '4. 只返回一个 JSON 数组，不要任何解释文字，不要 Markdown 代码块，不要注释。\n' +
      '\n' +
      '数组里每个元素的字段：\n' +
      '- "title": 字符串，题干，一个完整的中文问句\n' +
      '- "options": 恰好 4 个字符串的数组，选项文字里不要带 A/B/C/D 前缀\n' +
      '- "correctIndex": 整数，正确选项在 options 里的下标，从 0 开始（0 表示第一个选项）\n' +
      '- "explanation": 字符串，2~3 句，说明为什么这个选项对、其他选项错在哪\n' +
      '- "recommendation": 字符串，一句话的练习建议';

    const lines: string[] = [];
    lines.push(`知识点：${this.textOf(request.tag)}`);
    lines.push(`难度：${request.difficulty}`);
    lines.push('');
    lines.push('【讲义片段】');
    for (let i = 0; i < request.passages.length; i++) {
      const passage = request.passages[i];
      const citation = this.textOf(passage.citation);
      lines.push(citation.length > 0 ? `片段 ${i}（${citation}）` : `片段 ${i}`);
      lines.push(this.textOf(passage.text));
      lines.push('');
    }
    lines.push(`请出 ${request.count} 道单选题。`);
    return new SynthesisPrompt(system, lines.join('\n'));
  }

  /**
   * Parses a model reply into questions the practice engine can serve.
   *
   * Never throws: malformed input is an empty batch, which the caller treats
   * exactly like "the model had nothing to say" and falls back from.
   */
  parseResponse(raw: string, request: SynthesisRequest): AdaptivePracticeQuestion[] {
    const questions: AdaptivePracticeQuestion[] = [];
    if (typeof raw !== 'string' || raw.length === 0) {
      return questions;
    }
    const parsed = this.parseArray(this.extractJsonArray(raw));
    if (parsed === null) {
      return questions;
    }

    const tag = normalizeKnowledgeTag(request.tag);
    const citation = this.citationOf(request.passages);
    const seenTitles: string[] = [];
    for (let i = 0; i < parsed.length; i++) {
      const question = this.buildQuestion(parsed[i], tag, request.difficulty, citation);
      if (question === null) {
        continue;
      }
      // Two questions asking the same thing in slightly different words are one
      // question as far as the learner is concerned. The id is derived from the
      // stem too, so a duplicate would collide on id anyway.
      const normalized = normalizeQuestionTitle(question.title);
      if (seenTitles.indexOf(normalized) >= 0) {
        continue;
      }
      seenTitles.push(normalized);
      questions.push(question);
    }
    return questions;
  }

  /**
   * One parsed element to one question, or null when it is not usable.
   *
   * The id is derived from the knowledge point and the stem, never from the
   * clock: the same question synthesized twice must collapse to one cache entry
   * rather than accumulate, and a test must be able to name the id it expects.
   */
  private buildQuestion(item: Object, tag: string, difficulty: PracticeDifficulty,
    citation: string): AdaptivePracticeQuestion | null {
    // `as` is a compile-time assertion and checks nothing at runtime, so a
    // reply containing null, a number or a nested array would otherwise walk
    // straight into a property read on it. Models do occasionally emit those.
    if (item === null || typeof item !== 'object' || Array.isArray(item)) {
      return null;
    }
    const record = item as Record<string, Object>;
    const title = this.textOf(record['title']);
    if (title.length < MIN_TITLE_CHARS || title.length > MAX_TITLE_CHARS ||
      isCorruptedText(title)) {
      return null;
    }

    const options = this.readOptions(record['options']);
    if (options.length < MIN_OPTION_COUNT || options.length > MAX_OPTION_COUNT) {
      return null;
    }

    const correctIndex = this.readCorrectIndex(record['correctIndex'], options.length);
    if (correctIndex < 0) {
      return null;
    }

    const explanation = this.textOf(record['explanation']);
    if (explanation.length === 0 || isCorruptedText(explanation)) {
      return null;
    }

    let recommendation = this.textOf(record['recommendation']);
    if (recommendation.length === 0 || isCorruptedText(recommendation)) {
      recommendation = DEFAULT_RECOMMENDATION;
    }

    const question = new AdaptivePracticeQuestion(
      `q_gen_${stableTextHash(`${tag}|${normalizeQuestionTitle(title)}`)}`,
      title,
      options,
      correctIndex,
      tag,
      difficulty,
      SOURCE_AI_GENERATED,
      explanation,
      recommendation,
    );
    question.citation = citation;
    return question;
  }

  /**
   * The options, or an empty array when any entry is unusable.
   *
   * All-or-nothing on purpose. Dropping one bad entry would silently shift
   * every index after it, so `correctIndex` would point at a different option
   * and the app would mark a right answer wrong — a far worse outcome than
   * declining to use the question. Four usable strings or none.
   */
  private readOptions(raw: Object | undefined): string[] {
    const options: string[] = [];
    if (!Array.isArray(raw)) {
      return options;
    }
    for (let i = 0; i < raw.length; i++) {
      const option = this.textOf(raw[i]);
      if (option.length === 0 || isCorruptedText(option)) {
        return [];
      }
      options.push(option);
    }
    return options;
  }

  /**
   * The answer index, or -1 when the reply cannot be read with confidence.
   *
   * A number is taken as-is. A single letter is the other near-universal way a
   * model spells "option B", and it is unambiguous, so it is translated.
   * A numeric string is deliberately NOT accepted: "2" could mean either the
   * second option or index 2, and guessing wrong marks a correct answer wrong —
   * a worse failure than dropping the question.
   */
  private readCorrectIndex(raw: Object | undefined, optionCount: number): number {
    let index = -1;
    if (typeof raw === 'number') {
      if (Number.isInteger(raw)) {
        index = raw;
      }
    } else if (typeof raw === 'string') {
      const text = raw.trim();
      if (text.length === 1) {
        const code = text.charCodeAt(0);
        if (code >= 65 && code <= 90) {
          index = code - 65;
        } else if (code >= 97 && code <= 122) {
          index = code - 97;
        }
      }
    }
    if (index < 0 || index >= optionCount) {
      return -1;
    }
    return index;
  }

  /** `JSON.parse` of an array literal, or null when the text is not one. */
  private parseArray(text: string): Object[] | null {
    if (text.length === 0) {
      return null;
    }
    try {
      const parsed = JSON.parse(text) as Object;
      return Array.isArray(parsed) ? parsed as Object[] : null;
    } catch (e) {
      return null;
    }
  }

  /**
   * The JSON array inside a reply, with any code fence or prose stripped.
   *
   * Fast paths first — a reply that is already a bare array is returned
   * untouched — then a fenced block, then the outermost brackets. Taking the
   * outermost `[`…`]` also recovers the array from a wrapper object such as
   * `{"questions":[…]}`. No regex: this project tokenizes and scans by hand
   * throughout, and a regex here would be the only one in the codec layer.
   */
  private extractJsonArray(raw: string): string {
    const trimmed = raw.trim();
    if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
      return trimmed;
    }

    let body = trimmed;
    const fence = body.indexOf('```');
    if (fence >= 0) {
      body = body.slice(fence + 3);
      // The language tag, when present, sits immediately after the fence.
      if (body.startsWith('json')) {
        body = body.slice(4);
      } else if (body.startsWith('JSON')) {
        body = body.slice(4);
      }
      const close = body.indexOf('```');
      if (close >= 0) {
        body = body.slice(0, close);
      }
    }

    const open = body.indexOf('[');
    const close = body.lastIndexOf(']');
    if (open < 0 || close <= open) {
      return '';
    }
    return body.slice(open, close + 1);
  }

  /** Trimmed string form of a parsed value; '' for anything that is not a string. */
  private textOf(value: Object | undefined): string {
    return typeof value === 'string' ? value.trim() : '';
  }
}

/*
 * Copyright (c) 2025 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 */

import {
  KnowledgeDocument,
  KnowledgeSourceType,
  SeedCourseInput,
  SeedLectureInput,
  SeedQuestionInput,
} from '../viewmodel/KnowledgeModels';
import { normalizeKnowledgeTag, normalizeQuestionTitle } from './ErrorBookPracticeSource';

const NEWLINE = '\n';
const OPTION_LABEL_BASE = 65;
const LECTURE_DOC_PREFIX = 'doc_note_';
const COURSE_DOC_PREFIX = 'doc_course_';
const QUESTION_DOC_PREFIX = 'doc_q_';
const SECTION_TITLE = '## 题目：';
const SECTION_ANALYSIS = '## 解析与建议';
const COURSE_SECTION = '## 课程：';
const CATEGORY_LABEL = '所属分类：';
const DESCRIPTION_LABEL = '课程简介：';

/**
 * Builds the seed corpus out of data the app already ships, so RAG has real
 * material to retrieve from.
 *
 * The input shapes are plain interfaces rather than the app's own models: that
 * keeps this a pure adapter (no `@safe/mine`, no ChatModels) and lets the
 * caller decide where the data comes from. This is deliberately the only place
 * that knows how app data maps onto document text.
 */
export class KnowledgeSeedCorpus {
  /**
   * Lectures first, then courses, then questions.
   *
   * Order matters only for readability of the built index: a long-form note
   * and the catalogue row for the same course are two different documents and
   * both stay in — the note carries the substance, the row carries the
   * category and the one-line summary. Every input is de-duplicated so a
   * course listed twice, a note authored twice, or the same question saved
   * twice all yield exactly one document.
   */
  buildDocuments(courses: SeedCourseInput[], questions: SeedQuestionInput[],
    lectures: SeedLectureInput[] = []): KnowledgeDocument[] {
    const documents: KnowledgeDocument[] = [];
    this.appendLectureDocuments(lectures, documents);
    this.appendCourseDocuments(courses, documents);
    this.appendQuestionDocuments(questions, documents);
    return documents;
  }

  /**
   * Long-form notes are indexed verbatim: the Markdown *is* the document, so
   * the chunker can cut it on its own headings and quote a real chapter title.
   * Wrapping or summarising here would only invent a second structure.
   */
  private appendLectureDocuments(lectures: SeedLectureInput[], out: KnowledgeDocument[]): void {
    if (!Array.isArray(lectures)) {
      return;
    }
    const seen = new Set<string>();

    for (let i = 0; i < lectures.length; i++) {
      const lecture = lectures[i];
      if (!lecture) {
        continue;
      }
      const courseId = typeof lecture.courseId === 'string' ? lecture.courseId.trim() : '';
      const title = typeof lecture.title === 'string' ? lecture.title.trim() : '';
      const markdown = typeof lecture.markdown === 'string' ? lecture.markdown.trim() : '';
      if (courseId.length === 0 || title.length === 0 || markdown.length === 0) {
        continue;
      }
      if (seen.has(courseId)) {
        continue;
      }
      seen.add(courseId);

      const tag = typeof lecture.knowledgeTag === 'string' ? lecture.knowledgeTag.trim() : '';
      const document = new KnowledgeDocument();
      document.docId = `${LECTURE_DOC_PREFIX}${courseId}`;
      document.title = title;
      document.courseId = courseId;
      document.knowledgeTag = normalizeKnowledgeTag(tag.length > 0 ? tag : title);
      document.sourceType = KnowledgeSourceType.COURSE_NOTE;
      document.text = markdown;
      out.push(document);
    }
  }

  private appendCourseDocuments(courses: SeedCourseInput[], out: KnowledgeDocument[]): void {
    if (!Array.isArray(courses)) {
      return;
    }
    const seen = new Set<string>();

    for (let i = 0; i < courses.length; i++) {
      const course = courses[i];
      if (!course) {
        continue;
      }
      const courseId = typeof course.courseId === 'string' ? course.courseId.trim() : '';
      const title = typeof course.title === 'string' ? course.title.trim() : '';
      const description = typeof course.description === 'string' ? course.description.trim() : '';
      if (courseId.length === 0 || title.length === 0 || description.length === 0) {
        continue;
      }
      if (seen.has(courseId)) {
        continue;
      }
      seen.add(courseId);

      const category = typeof course.category === 'string' ? course.category.trim() : '';
      const lines: string[] = [`${COURSE_SECTION}${title}`, ''];
      if (category.length > 0) {
        lines.push(`${CATEGORY_LABEL}${category}`);
      }
      lines.push(`${DESCRIPTION_LABEL}${description}`);

      const document = new KnowledgeDocument();
      document.docId = `${COURSE_DOC_PREFIX}${courseId}`;
      document.title = title;
      document.courseId = courseId;
      // The category is the closest thing a course has to a knowledge tag, and
      // it is the tag the error book uses for the same subject.
      document.knowledgeTag = normalizeKnowledgeTag(category.length > 0 ? category : title);
      document.sourceType = KnowledgeSourceType.COURSE;
      document.text = lines.join(NEWLINE);
      out.push(document);
    }
  }

  private appendQuestionDocuments(questions: SeedQuestionInput[], out: KnowledgeDocument[]): void {
    if (!Array.isArray(questions)) {
      return;
    }
    const seen = new Set<string>();

    for (let i = 0; i < questions.length; i++) {
      const question = questions[i];
      if (!question) {
        continue;
      }
      const questionId = typeof question.questionId === 'string' ? question.questionId.trim() : '';
      const title = typeof question.title === 'string' ? question.title.trim() : '';
      if (questionId.length === 0 || title.length === 0) {
        continue;
      }
      const dedupeKey = normalizeQuestionTitle(title);
      if (seen.has(dedupeKey)) {
        continue;
      }
      seen.add(dedupeKey);

      const lines: string[] = [`${SECTION_TITLE}${title}`, ''];
      let options: string[] = [];
      if (Array.isArray(question.options)) {
        options = question.options;
      }
      for (let o = 0; o < options.length; o++) {
        const option = typeof options[o] === 'string' ? options[o].trim() : '';
        if (option.length === 0) {
          continue;
        }
        lines.push(`${String.fromCharCode(OPTION_LABEL_BASE + o)}. ${option}`);
      }

      const explanation = typeof question.explanation === 'string' ? question.explanation.trim() : '';
      const recommendation =
        typeof question.recommendation === 'string' ? question.recommendation.trim() : '';
      if (explanation.length > 0 || recommendation.length > 0) {
        lines.push('', SECTION_ANALYSIS, '');
        if (explanation.length > 0) {
          lines.push(explanation);
        }
        if (recommendation.length > 0) {
          if (explanation.length > 0) {
            lines.push('');
          }
          lines.push(recommendation);
        }
      }

      const document = new KnowledgeDocument();
      document.docId = `${QUESTION_DOC_PREFIX}${questionId}`;
      document.title = title;
      document.courseId = '';
      document.knowledgeTag = normalizeKnowledgeTag(question.knowledgeTag);
      document.sourceType = KnowledgeSourceType.QUESTION_BANK;
      document.text = lines.join(NEWLINE);
      out.push(document);
    }
  }
}

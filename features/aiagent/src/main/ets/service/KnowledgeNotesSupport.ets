/*
 * Copyright (c) 2025 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 */

import { SeedLectureInput } from '../viewmodel/KnowledgeModels';

/**
 * Builds one course-notes row.
 *
 * The notes are embedded in code for the same reason the course catalogue is:
 * the corpus path then needs no rawfile, no resource manager and no file
 * permission, which is what keeps the whole retrieval chain offline testable.
 * Splitting the prose across several files is only about keeping each file
 * readable — the data shape is identical everywhere.
 *
 * `knowledgeTag` defaults to a sensible value rather than being optional, and
 * the adapter normalises whatever arrives, so a blank tag degrades to the
 * course title instead of to "未分类".
 */
export function makeLecture(courseId: string, title: string, category: string, markdown: string,
  knowledgeTag: string = ''): SeedLectureInput {
  const lecture = new SeedLectureInput();
  lecture.courseId = courseId;
  lecture.title = title;
  lecture.category = category;
  lecture.knowledgeTag = knowledgeTag.length > 0 ? knowledgeTag : title;
  lecture.markdown = markdown;
  return lecture;
}

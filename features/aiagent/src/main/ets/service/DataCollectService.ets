/*
 * Copyright (c) 2025 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import fileIo from '@ohos.file.fs';
import { MineCourseList, MineCourseListModel } from '@safe/mine';
import {
  LearningAnalysisData,
  LearningDataSnapshot,
  ScoreTrendItem,
  KnowledgePoint,
  CourseProgressItem,
  ExamScoreItem,
  ErrorQuestionItem,
  CourseProgressDataItem,
  KnowledgeStats,
} from '../viewmodel/ChatModels';

const EXAM_HISTORY_KEY = 'ExamHistory';
const EXAM_HISTORY_FILE = '/examHistory.json';
const COURSE_PROGRESS_KEY = 'CourseProgress';
const COURSE_PROGRESS_FILE = '/courseProgress.json';
const STUDY_TIME_KEY = 'TotalStudyTimeMinutes';
const ERROR_STORE_KEY = 'ErrorQuestions';
const ERROR_BOOK_FILE = '/errorBook.json';

export class DataCollectService {
  collectAllData(): LearningDataSnapshot {
    const snapshot: LearningDataSnapshot = {
      examScores: [],
      errorQuestions: [],
      courseProgress: [],
      totalStudyTime: 0,
    };

    this.collectExamScores(snapshot);
    this.collectErrorQuestions(snapshot);
    this.collectCourseProgress(snapshot);
    this.collectStudyTime(snapshot);

    return snapshot;
  }

  private collectExamScores(snapshot: LearningDataSnapshot): void {
    const historyJson = this.readStorageOrFile(EXAM_HISTORY_KEY, EXAM_HISTORY_FILE);
    if (historyJson.length === 0) {
      return;
    }

    try {
      const parsed = JSON.parse(historyJson) as Array<Record<string, Object>>;
      for (let i = 0; i < parsed.length; i++) {
        const record = parsed[i];
        const score = record['score'] as number;
        if (typeof score !== 'number' || !Number.isFinite(score) || score < 0 || score > 100) {
          continue;
        }

        const name = (record['name'] as string) || `第 ${i + 1} 次考试`;
        const date = (record['date'] as string) || '';
        snapshot.examScores.push(new ExamScoreItem(name, Math.round(score), date));
      }
      snapshot.examScores.sort((a: ExamScoreItem, b: ExamScoreItem) => a.date.localeCompare(b.date));
    } catch (e) {
      // Invalid history is treated as unavailable data, never replaced with mock scores.
    }
  }

  private collectErrorQuestions(snapshot: LearningDataSnapshot): void {
    const labels: string[] = ['A', 'B', 'C', 'D', 'E', 'F'];
    const errorJson = this.readStorageOrFile(ERROR_STORE_KEY, ERROR_BOOK_FILE);
    if (errorJson.length === 0) {
      return;
    }

    try {
      const parsed = JSON.parse(errorJson) as Array<Record<string, Object>>;
      for (const eq of parsed) {
        const title = ((eq['title'] as string) || '').trim();
        if (title.length === 0) {
          continue;
        }

        const category = ((eq['knowledgeTag'] as string) || '未分类').trim() || '未分类';
        const item = new ErrorQuestionItem(title, category);
        const options = eq['option'] as string[];
        if (options) {
          item.options = options;
        }

        const rightQues = eq['rightQues'] as number;
        if (typeof rightQues === 'number' && rightQues >= 0) {
          item.correctIndex = rightQues;
          item.correctLabel = rightQues < labels.length ? labels[rightQues] : String(rightQues);
        }

        const answer = eq['answer'] as number;
        if (typeof answer === 'number' && answer >= 0) {
          item.userIndex = answer;
          item.userLabel = answer < labels.length ? labels[answer] : String(answer);
        }

        item.userNote = (eq['userNote'] as string) || '';
        item.mistakeReason = (eq['mistakeReason'] as string) || '';
        item.createTime = (eq['createTime'] as number) || 0;
        snapshot.errorQuestions.push(item);
      }
    } catch (e) {
      // Invalid data is ignored so the UI can explicitly show that data is unavailable.
    }
  }

  private collectCourseProgress(snapshot: LearningDataSnapshot): void {
    const progressMap = new Map<string, CourseProgressDataItem>();
    const progressJson = this.readStorageOrFile(COURSE_PROGRESS_KEY, COURSE_PROGRESS_FILE);

    if (progressJson.length > 0) {
      try {
        const parsed = JSON.parse(progressJson) as Array<Record<string, Object>>;
        for (const record of parsed) {
          const name = ((record['name'] as string) || '').trim();
          const progress = record['progress'] as number;
          if (name.length === 0 || typeof progress !== 'number' || !Number.isFinite(progress)) {
            continue;
          }
          const teacher = (record['teacher'] as string) || '';
          progressMap.set(name, new CourseProgressDataItem(name, this.clampPercent(progress), teacher));
        }
      } catch (e) {
        // Fall back to the current course data exported by the mine module.
      }
    }

    if (progressMap.size === 0) {
      for (const course of MineCourseList as MineCourseListModel[]) {
        const name = course.name.trim();
        if (name.length === 0) {
          continue;
        }
        const rawProgress = course.process <= 1 ? course.process * 100 : course.process;
        progressMap.set(name, new CourseProgressDataItem(
          name,
          this.clampPercent(rawProgress),
          course.tec,
        ));
      }
    }

    progressMap.forEach((item: CourseProgressDataItem) => {
      snapshot.courseProgress.push(item);
    });
  }

  private collectStudyTime(snapshot: LearningDataSnapshot): void {
    try {
      const storedMinutes = AppStorage.get<number>(STUDY_TIME_KEY);
      if (typeof storedMinutes === 'number' && Number.isFinite(storedMinutes) && storedMinutes >= 0) {
        snapshot.totalStudyTime = Math.round(storedMinutes);
        return;
      }
    } catch (e) {
      // Fall through and derive time from real exam history if available.
    }

    const historyJson = this.readStorageOrFile(EXAM_HISTORY_KEY, EXAM_HISTORY_FILE);
    if (historyJson.length === 0) {
      return;
    }

    try {
      const parsed = JSON.parse(historyJson) as Array<Record<string, Object>>;
      let totalDurationMs = 0;
      for (const record of parsed) {
        const duration = record['duration'] as number;
        if (typeof duration === 'number' && Number.isFinite(duration) && duration > 0) {
          totalDurationMs += duration;
        }
      }
      snapshot.totalStudyTime = Math.round(totalDurationMs / 60000);
    } catch (e) {
      // Keep zero to represent that no trustworthy study-time data is available.
    }
  }

  analyzeData(snapshot: LearningDataSnapshot): LearningAnalysisData {
    const totalExams = snapshot.examScores.length;
    let avgScore = 0;
    if (totalExams > 0) {
      let total = 0;
      for (const item of snapshot.examScores) {
        total += item.score;
      }
      avgScore = Math.round(total / totalExams);
    }

    const scoreTrend: ScoreTrendItem[] = [];
    for (const score of snapshot.examScores) {
      scoreTrend.push(new ScoreTrendItem(score.name, score.score, score.date));
    }

    const knowledgeMap = new Map<string, KnowledgeStats>();
    for (const errorQuestion of snapshot.errorQuestions) {
      if (!knowledgeMap.has(errorQuestion.category)) {
        knowledgeMap.set(errorQuestion.category, new KnowledgeStats(0, 0));
      }
      const stats = knowledgeMap.get(errorQuestion.category)!;
      stats.total += 1;
    }

    const knowledgePoints: KnowledgePoint[] = [];
    knowledgeMap.forEach((stats: KnowledgeStats, name: string) => {
      // Only wrong-question counts are currently available. Use a transparent,
      // deterministic diagnostic estimate instead of inventing correct answers.
      const mastery = Math.max(20, 75 - Math.max(0, stats.total - 1) * 10);
      knowledgePoints.push(new KnowledgePoint(name, mastery, stats.total, 0));
    });
    knowledgePoints.sort((a: KnowledgePoint, b: KnowledgePoint) => {
      if (a.mastery !== b.mastery) {
        return a.mastery - b.mastery;
      }
      return a.name.localeCompare(b.name);
    });

    const weakPoints: string[] = [];
    const strengths: string[] = [];
    for (const knowledgePoint of knowledgePoints) {
      if (knowledgePoint.mastery < 60) {
        this.pushUnique(weakPoints, knowledgePoint.name);
      }
    }

    const courseProgress: CourseProgressItem[] = [];
    for (const course of snapshot.courseProgress) {
      courseProgress.push(new CourseProgressItem(course.name, course.progress, course.teacher));
      if (course.progress < 60) {
        this.pushUnique(weakPoints, course.name);
      } else if (course.progress >= 85 && !knowledgeMap.has(course.name)) {
        this.pushUnique(strengths, course.name);
      }
    }

    return {
      totalExams: totalExams,
      avgScore: avgScore,
      totalStudyTime: snapshot.totalStudyTime,
      scoreTrend: scoreTrend,
      knowledgePoints: knowledgePoints,
      courseProgress: courseProgress,
      weakPoints: weakPoints,
      strengths: strengths,
    };
  }

  private readStorageOrFile(storageKey: string, fileName: string): string {
    let json = '';
    try {
      json = AppStorage.get<string>(storageKey) || '';
    } catch (e) {
      // AppStorage may not be initialized during preview or unit tests.
    }

    if (json.length > 0) {
      return json;
    }

    try {
      const filesDir = AppStorage.get<string>('filesDir');
      if (filesDir) {
        return fileIo.readTextSync(filesDir + fileName);
      }
    } catch (e) {
      // Missing files represent unavailable data.
    }
    return '';
  }

  private clampPercent(value: number): number {
    return Math.max(0, Math.min(100, Math.round(value)));
  }

  private pushUnique(values: string[], value: string): void {
    if (values.indexOf(value) < 0) {
      values.push(value);
    }
  }
}

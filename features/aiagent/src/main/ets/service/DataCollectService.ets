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

export class DataCollectService {
  collectAllData(): LearningDataSnapshot {
    const emptyExamScores: ExamScoreItem[] = [];
    const emptyErrorQuestions: ErrorQuestionItem[] = [];
    const emptyCourseProgress: CourseProgressDataItem[] = [];

    const snapshot: LearningDataSnapshot = {
      examScores: emptyExamScores,
      errorQuestions: emptyErrorQuestions,
      courseProgress: emptyCourseProgress,
      totalStudyTime: 0,
    };

    try {
      const scoreStr = AppStorage.get<string>('Score');
      const timeStr = AppStorage.get<string>('Time');
      const examCountStr = AppStorage.get<string>('ExamCount');
    } catch (e) {
      // AppStorage keys may not exist yet
    }

    this.collectExamScores(snapshot);
    this.collectErrorQuestions(snapshot);
    this.collectCourseProgress(snapshot);
    this.collectStudyTime(snapshot);

    return snapshot;
  }

  private collectExamScores(snapshot: LearningDataSnapshot): void {
    try {
      const score = AppStorage.get<number>('Score');
      if (score !== undefined && score !== null) {
        const item = new ExamScoreItem('最近考试', score, new Date().toISOString().split('T')[0]);
        snapshot.examScores.push(item);
      }
    } catch (e) {
      // Ignore if data not available
    }

    if (snapshot.examScores.length === 0) {
      const mockScores: ExamScoreItem[] = [];
      mockScores.push(new ExamScoreItem('第一次模拟考试', 65, '2026-04-15'));
      mockScores.push(new ExamScoreItem('第二次模拟考试', 72, '2026-04-28'));
      mockScores.push(new ExamScoreItem('第三次模拟考试', 78, '2026-05-10'));

      for (const s of mockScores) {
        snapshot.examScores.push(s);
      }
    }
  }

  private collectErrorQuestions(snapshot: LearningDataSnapshot): void {
    const mockErrors: ErrorQuestionItem[] = [];
    mockErrors.push(new ErrorQuestionItem('TCP/IP 协议栈结构', '计算机网络'));
    mockErrors.push(new ErrorQuestionItem('二叉树的遍历算法', '数据结构'));
    mockErrors.push(new ErrorQuestionItem('数据库范式设计', '数据库系统原理'));
    mockErrors.push(new ErrorQuestionItem('操作系统进程调度', '操作系统'));
    mockErrors.push(new ErrorQuestionItem('TCP 拥塞控制机制', '计算机网络'));
    mockErrors.push(new ErrorQuestionItem('图的深度优先搜索', '数据结构'));
    mockErrors.push(new ErrorQuestionItem('LL(1) 文法分析', '编译原理'));
    mockErrors.push(new ErrorQuestionItem('红黑树的插入与删除', '数据结构'));
    mockErrors.push(new ErrorQuestionItem('死锁检测与避免', '操作系统'));
    mockErrors.push(new ErrorQuestionItem('关系代数与 SQL 优化', '数据库系统原理'));
    mockErrors.push(new ErrorQuestionItem('梯度下降与反向传播', '机器学习'));
    mockErrors.push(new ErrorQuestionItem('虚拟内存页面置换算法', '操作系统'));

    for (const e of mockErrors) {
      snapshot.errorQuestions.push(e);
    }
  }

  private collectCourseProgress(snapshot: LearningDataSnapshot): void {
    const mockCourses: CourseProgressDataItem[] = [];
    mockCourses.push(new CourseProgressDataItem('高等数学（上）', 90, '刘教授'));
    mockCourses.push(new CourseProgressDataItem('高等数学（下）', 85, '刘教授'));
    mockCourses.push(new CourseProgressDataItem('线性代数', 75, '王教授'));
    mockCourses.push(new CourseProgressDataItem('概率论与数理统计', 60, '陈教授'));
    mockCourses.push(new CourseProgressDataItem('离散数学', 70, '张教授'));
    mockCourses.push(new CourseProgressDataItem('程序设计基础（C语言）', 92, '李教授'));
    mockCourses.push(new CourseProgressDataItem('面向对象程序设计（Java）', 82, '李教授'));
    mockCourses.push(new CourseProgressDataItem('数据结构', 68, '张教授'));
    mockCourses.push(new CourseProgressDataItem('算法设计与分析', 45, '张教授'));
    mockCourses.push(new CourseProgressDataItem('计算机组成原理', 55, '周教授'));
    mockCourses.push(new CourseProgressDataItem('操作系统', 80, '陈教授'));
    mockCourses.push(new CourseProgressDataItem('计算机网络', 48, '吴教授'));
    mockCourses.push(new CourseProgressDataItem('数据库系统原理', 72, '赵教授'));
    mockCourses.push(new CourseProgressDataItem('编译原理', 38, '周教授'));
    mockCourses.push(new CourseProgressDataItem('软件工程', 65, '孙教授'));
    mockCourses.push(new CourseProgressDataItem('计算机组成原理', 78, '周教授'));
    mockCourses.push(new CourseProgressDataItem('软件工程导论', 50, '吴教授'));
    mockCourses.push(new CourseProgressDataItem('机器学习', 30, '吴教授'));
    mockCourses.push(new CourseProgressDataItem('Web前端开发', 88, '黄教授'));
    mockCourses.push(new CourseProgressDataItem('Linux系统管理', 70, '马教授'));

    for (const c of mockCourses) {
      snapshot.courseProgress.push(c);
    }
  }

  private collectStudyTime(snapshot: LearningDataSnapshot): void {
    snapshot.totalStudyTime = 1380;
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
    for (const s of snapshot.examScores) {
      scoreTrend.push(new ScoreTrendItem(s.name, s.score, s.date));
    }

    const knowledgeMap = new Map<string, KnowledgeStats>();
    const categoryMap = new Map<string, string[]>();

    for (const eq of snapshot.errorQuestions) {
      if (!categoryMap.has(eq.category)) {
        const emptyArr: string[] = [];
        categoryMap.set(eq.category, emptyArr);
      }
      const titles = categoryMap.get(eq.category)!;
      titles.push(eq.title);

      if (!knowledgeMap.has(eq.category)) {
        knowledgeMap.set(eq.category, new KnowledgeStats(0, 0));
      }
      const kp = knowledgeMap.get(eq.category)!;
      kp.total += 1;
    }

    const knowledgePoints: KnowledgePoint[] = [];
    const mapEntries: Array<[string, KnowledgeStats]> = [];
    knowledgeMap.forEach((value: KnowledgeStats, key: string) => {
      mapEntries.push([key, value]);
    });

    for (let i = 0; i < mapEntries.length; i++) {
      const name = mapEntries[i][0];
      const stats = mapEntries[i][1];
      const estimatedTotal = stats.total + 2 + Math.floor(Math.random() * 3);
      const mastery = Math.round((stats.total / estimatedTotal) * 100);
      const clampedMastery = Math.max(20, Math.min(100, 100 - mastery));
      knowledgePoints.push(new KnowledgePoint(
        name,
        clampedMastery,
        estimatedTotal,
        estimatedTotal - stats.total,
      ));
    }

    const weakPoints: string[] = [];
    const strengths: string[] = [];
    for (const kp of knowledgePoints) {
      if (kp.mastery < 60) {
        weakPoints.push(kp.name);
      } else if (kp.mastery >= 80) {
        strengths.push(kp.name);
      }
    }

    const courseProgress: CourseProgressItem[] = [];
    for (const c of snapshot.courseProgress) {
      courseProgress.push(new CourseProgressItem(c.name, c.progress, c.teacher));
    }

    const result: LearningAnalysisData = {
      totalExams: totalExams,
      avgScore: avgScore,
      scoreTrend: scoreTrend,
      knowledgePoints: knowledgePoints,
      courseProgress: courseProgress,
      weakPoints: weakPoints,
      strengths: strengths,
    };

    return result;
  }
}

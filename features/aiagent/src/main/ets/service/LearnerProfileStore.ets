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
import { LearningAnalysisData } from '../viewmodel/ChatModels';
import { Logger } from '@safe/basic';

const PROFILE_STORE_KEY = 'LearnerProfile';
const PROFILE_FILE = '/learnerProfile.json';
const MAX_WEAK_POINTS = 8;
const MAX_STRENGTHS = 5;
const MAX_FOCUS_TOPICS = 6;
const MAX_SUMMARIES = 3;
const SUMMARY_MAX_CHARS = 200;
const MIN_SUMMARY_CHARS = 20;

/**
 * Long-term, cross-session memory of one learner — the "越用越懂你" piece.
 * Every field is derived deterministically from real local data or from the
 * tutor's own analysis conclusions; nothing is invented and no extra API
 * call is made. Persisted on-device only (AppStorage + JSON file, same
 * pattern as SessionStore).
 */
export class LearnerProfile {
  weakPoints: string[] = [];
  strengths: string[] = [];
  /** Topics the learner recently practiced or asked about. */
  focusTopics: string[] = [];
  examCount: number = 0;
  avgScore: number = 0;
  totalStudyTime: number = 0;
  /** The tutor's own recent analysis conclusions, newest last. */
  analysisSummaries: string[] = [];
  updatedAt: number = 0;
}

interface PersistedProfileRecord {
  weakPoints: string[];
  strengths: string[];
  focusTopics: string[];
  examCount: number;
  avgScore: number;
  totalStudyTime: number;
  analysisSummaries: string[];
  updatedAt: number;
}

export class LearnerProfileStore {
  loadProfile(): LearnerProfile {
    let json = '';
    try {
      json = AppStorage.get<string>(PROFILE_STORE_KEY) || '';
    } catch (e) {
      // AppStorage may not be initialized during preview or unit tests.
    }

    if (json.length === 0) {
      const filePath = this.getProfileFilePath();
      if (filePath) {
        try {
          json = fileIo.readTextSync(filePath);
        } catch (e) {
          // No persisted profile yet.
        }
      }
    }

    if (json.length === 0) {
      return new LearnerProfile();
    }

    try {
      const record = JSON.parse(json) as PersistedProfileRecord;
      return this.recordToProfile(record);
    } catch (e) {
      Logger.error(`Failed to parse learner profile: ${json.length}`);
      return new LearnerProfile();
    }
  }

  saveProfile(profile: LearnerProfile): void {
    const record: PersistedProfileRecord = {
      weakPoints: profile.weakPoints,
      strengths: profile.strengths,
      focusTopics: profile.focusTopics,
      examCount: profile.examCount,
      avgScore: profile.avgScore,
      totalStudyTime: profile.totalStudyTime,
      analysisSummaries: profile.analysisSummaries,
      updatedAt: profile.updatedAt,
    };
    const json = JSON.stringify(record);
    AppStorage.setOrCreate(PROFILE_STORE_KEY, json);

    const filePath = this.getProfileFilePath();
    if (!filePath) {
      return;
    }
    try {
      const file: fileIo.File = fileIo.openSync(filePath, 0o2 | 0o100 | 0o1000);
      fileIo.writeSync(file.fd, json);
      fileIo.closeSync(file);
    } catch (e) {
      // Persist failure must not interrupt the chat.
    }
  }

  /** Recomputes the data-derived fields from a fresh learning analysis. */
  updateFromAnalysis(data: LearningAnalysisData): void {
    const profile = this.loadProfile();
    profile.weakPoints = data.weakPoints.slice(0, MAX_WEAK_POINTS);
    profile.strengths = data.strengths.slice(0, MAX_STRENGTHS);
    profile.examCount = data.totalExams;
    profile.avgScore = data.avgScore;
    profile.totalStudyTime = data.totalStudyTime;
    profile.updatedAt = Date.now();
    this.saveProfile(profile);
  }

  /** Merges recently practiced/attributed topics into the focus list (unique, capped). */
  recordFocusTopics(topics: string[]): void {
    if (topics.length === 0) {
      return;
    }
    const profile = this.loadProfile();
    for (const topic of topics) {
      if (profile.focusTopics.length >= MAX_FOCUS_TOPICS) {
        break;
      }
      if (profile.focusTopics.indexOf(topic) < 0) {
        profile.focusTopics.push(topic);
      }
    }
    profile.updatedAt = Date.now();
    this.saveProfile(profile);
  }

  /** Wipes the profile (user-visible "reset" action on the profile page). */
  clearProfile(): void {
    this.saveProfile(new LearnerProfile());
  }

  /** Stores the tutor's own analysis conclusion as memory (last N, each truncated). */
  recordAnalysisSummary(text: string): void {
    const trimmed = text.trim();
    if (trimmed.length < MIN_SUMMARY_CHARS) {
      return;
    }
    const profile = this.loadProfile();
    profile.analysisSummaries.push(trimmed.substring(0, SUMMARY_MAX_CHARS));
    if (profile.analysisSummaries.length > MAX_SUMMARIES) {
      profile.analysisSummaries =
        profile.analysisSummaries.slice(profile.analysisSummaries.length - MAX_SUMMARIES);
    }
    profile.updatedAt = Date.now();
    this.saveProfile(profile);
  }

  /**
   * Builds the system-message fragment injected into every conversation so
   * the tutor "remembers" the learner across sessions. Returns '' when the
   * profile carries nothing meaningful yet.
   */
  buildProfilePrompt(): string {
    const profile = this.loadProfile();
    if (profile.weakPoints.length === 0 && profile.strengths.length === 0 &&
      profile.focusTopics.length === 0 && profile.examCount === 0 &&
      profile.totalStudyTime === 0 && profile.analysisSummaries.length === 0) {
      return '';
    }

    let prompt = '【该学生的长期学习档案（跨会话记忆，来自本地真实数据与历史分析）】\n';
    if (profile.weakPoints.length > 0) {
      prompt += `- 薄弱点：${profile.weakPoints.join('、')}\n`;
    }
    if (profile.strengths.length > 0) {
      prompt += `- 优势：${profile.strengths.join('、')}\n`;
    }
    if (profile.focusTopics.length > 0) {
      prompt += `- 近期练习/关注主题：${profile.focusTopics.join('、')}\n`;
    }
    if (profile.examCount > 0) {
      prompt += `- 成绩概况：共 ${profile.examCount} 次考试，平均 ${profile.avgScore} 分`;
      if (profile.totalStudyTime > 0) {
        prompt += `，累计学习 ${profile.totalStudyTime} 分钟`;
      }
      prompt += '\n';
    } else if (profile.totalStudyTime > 0) {
      prompt += `- 累计学习时长：${profile.totalStudyTime} 分钟\n`;
    }
    if (profile.analysisSummaries.length > 0) {
      prompt += '- 近期分析结论：\n';
      for (let i = 0; i < profile.analysisSummaries.length; i++) {
        prompt += `  ${i + 1}. ${profile.analysisSummaries[i]}\n`;
      }
    }
    prompt += '回答时自然地结合这些历史情况，避免重复询问已知信息。';
    return prompt;
  }

  private recordToProfile(record: PersistedProfileRecord): LearnerProfile {
    const profile = new LearnerProfile();
    if (!record) {
      return profile;
    }
    profile.weakPoints = Array.isArray(record.weakPoints) ? record.weakPoints : [];
    profile.strengths = Array.isArray(record.strengths) ? record.strengths : [];
    profile.focusTopics = Array.isArray(record.focusTopics) ? record.focusTopics : [];
    profile.analysisSummaries = Array.isArray(record.analysisSummaries) ? record.analysisSummaries : [];
    profile.examCount = typeof record.examCount === 'number' ? record.examCount : 0;
    profile.avgScore = typeof record.avgScore === 'number' ? record.avgScore : 0;
    profile.totalStudyTime = typeof record.totalStudyTime === 'number' ? record.totalStudyTime : 0;
    profile.updatedAt = typeof record.updatedAt === 'number' ? record.updatedAt : 0;
    return profile;
  }

  private getProfileFilePath(): string | null {
    const filesDir = AppStorage.get<string>('filesDir');
    if (!filesDir) {
      return null;
    }
    return filesDir + PROFILE_FILE;
  }
}

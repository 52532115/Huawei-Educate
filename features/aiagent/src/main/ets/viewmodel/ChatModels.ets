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

export enum MessageRole {
  USER = 'user',
  AI = 'ai',
  SYSTEM = 'system',
  ANALYSIS = 'analysis',
}

export enum MessageStatus {
  SENDING = 'sending',
  SUCCESS = 'success',
  FAILED = 'failed',
}

export class ChatMessage {
  id: string;
  role: MessageRole;
  content: string;
  timestamp: number;
  status: MessageStatus;
  analysisData?: LearningAnalysisData;

  constructor(
    id: string,
    role: MessageRole,
    content: string,
    status: MessageStatus = MessageStatus.SUCCESS,
    analysisData?: LearningAnalysisData,
  ) {
    this.id = id;
    this.role = role;
    this.content = content;
    this.timestamp = Date.now();
    this.status = status;
    this.analysisData = analysisData;
  }
}

@Observed
export class ChatSession {
  id: string;
  title: string;
  messages: ChatMessage[];
  createTime: number;
  updateTime: number;

  constructor(id: string, title: string) {
    this.id = id;
    this.title = title;
    this.messages = [];
    this.createTime = Date.now();
    this.updateTime = Date.now();
  }
}

export interface LearningAnalysisData {
  totalExams: number;
  avgScore: number;
  scoreTrend: ScoreTrendItem[];
  knowledgePoints: KnowledgePoint[];
  courseProgress: CourseProgressItem[];
  weakPoints: string[];
  strengths: string[];
}

export class ScoreTrendItem {
  examName: string;
  score: number;
  date: string;

  constructor(examName: string, score: number, date: string) {
    this.examName = examName;
    this.score = score;
    this.date = date;
  }
}

export class KnowledgePoint {
  name: string;
  mastery: number;
  total: number;
  correct: number;

  constructor(name: string, mastery: number, total: number, correct: number) {
    this.name = name;
    this.mastery = mastery;
    this.total = total;
    this.correct = correct;
  }
}

export class CourseProgressItem {
  courseName: string;
  progress: number;
  teacher: string;

  constructor(courseName: string, progress: number, teacher: string) {
    this.courseName = courseName;
    this.progress = progress;
    this.teacher = teacher;
  }
}

export class AiApiRequest {
  model: string;
  messages: AiMessage[];
  stream: boolean;
  temperature?: number;
  max_tokens?: number;

  constructor(model: string, messages: AiMessage[], stream: boolean) {
    this.model = model;
    this.messages = messages;
    this.stream = stream;
  }
}

export class AiMessage {
  role: string = '';
  content: string = '';
}

export class AiChoiceMessage {
  content: string = '';
}

export class AiChoiceDelta {
  content: string = '';
}

export class AiChoice {
  message: AiChoiceMessage = new AiChoiceMessage();
  delta?: AiChoiceDelta = undefined;
}

export interface AiApiResponse {
  choices: AiChoice[];
}

export class ExamScoreItem {
  name: string;
  score: number;
  date: string;

  constructor(name: string, score: number, date: string) {
    this.name = name;
    this.score = score;
    this.date = date;
  }
}

export class ErrorQuestionItem {
  title: string;
  category: string;
  options: string[];
  correctIndex: number;
  userIndex: number;
  correctLabel: string;
  userLabel: string;
  userNote: string;
  mistakeReason: string;
  createTime: number;

  constructor(title: string, category: string) {
    this.title = title;
    this.category = category;
    this.options = [];
    this.correctIndex = -1;
    this.userIndex = -1;
    this.correctLabel = '';
    this.userLabel = '';
    this.userNote = '';
    this.mistakeReason = '';
    this.createTime = 0;
  }
}

export class CourseProgressDataItem {
  name: string;
  progress: number;
  teacher: string;

  constructor(name: string, progress: number, teacher: string) {
    this.name = name;
    this.progress = progress;
    this.teacher = teacher;
  }
}

export class KnowledgeStats {
  total: number;
  correct: number;

  constructor(total: number, correct: number) {
    this.total = total;
    this.correct = correct;
  }
}

export interface LearningDataSnapshot {
  examScores: ExamScoreItem[];
  errorQuestions: ErrorQuestionItem[];
  courseProgress: CourseProgressDataItem[];
  totalStudyTime: number;
}

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
  AiMessage,
  AiToolCall,
  ApiToolSchema,
  ApiToolFunctionSchema,
  ApiToolParameters,
  ExamScoreItem,
  ErrorQuestionItem,
  CourseProgressDataItem,
} from '../viewmodel/ChatModels';
import { DataCollectService } from './DataCollectService';
import { ErrorAttributionService } from './ErrorAttributionService';
import { AdaptivePracticeService } from './AdaptivePracticeService';
import { PracticeSessionStore } from './PracticeSessionStore';
import { LearnerProfileStore } from './LearnerProfileStore';

interface AttributionToolResult {
  updatedCount: number;
  message: string;
}

interface LearnerProfileToolResult {
  weakPoints: string[];
  strengths: string[];
  focusTopics: string[];
  examCount: number;
  avgScore: number;
  totalStudyTime: number;
  analysisSummaries: string[];
  message: string;
}

interface PracticeToolResult {
  questionCount: number;
  topics: string[];
  message: string;
}

interface ExamHistoryToolResult {
  count: number;
  exams: ExamScoreItem[];
  message: string;
}

interface CourseProgressToolResult {
  count: number;
  courses: CourseProgressDataItem[];
  message: string;
}

interface ErrorQuestionsToolResult {
  count: number;
  errorQuestions: ErrorQuestionItem[];
  message: string;
}

/** Tool result used when a tool name is unknown or execution failed. */
export class ToolErrorResult {
  error: string = '';
}

/**
 * Tool registry for the AI tutor agent.
 *
 * Each tool wraps an existing local service (DataCollect / ErrorAttribution /
 * AdaptivePractice) behind a stable name + JSON Schema description that the
 * LLM uses to decide when to call it. Tools return JSON strings so their
 * output can be fed back into the conversation as tool messages.
 */
export class AgentToolRegistry {
  private dataService: DataCollectService = new DataCollectService();
  private attributionService: ErrorAttributionService = new ErrorAttributionService();
  private practiceService: AdaptivePracticeService = new AdaptivePracticeService();
  private profileStore: LearnerProfileStore = new LearnerProfileStore();

  execute(name: string, argsJson: string): Promise<string> {
    switch (name) {
      case 'get_learning_stats':
        return Promise.resolve(this.toolGetLearningStats());
      case 'analyze_error_book':
        return Promise.resolve(this.toolAnalyzeErrorBook());
      case 'generate_practice':
        return Promise.resolve(this.toolGeneratePractice());
      case 'get_exam_history':
        return Promise.resolve(this.toolGetExamHistory());
      case 'get_course_progress':
        return Promise.resolve(this.toolGetCourseProgress());
      case 'get_error_questions':
        return Promise.resolve(this.toolGetErrorQuestions());
      case 'get_learner_profile':
        return Promise.resolve(this.toolGetLearnerProfile());
      default: {
        const errorResult = new ToolErrorResult();
        errorResult.error = `未知工具：${name}`;
        return Promise.resolve(JSON.stringify(errorResult));
      }
    }
  }

  private toolGetLearningStats(): string {
    const snapshot = this.dataService.collectAllData();
    const analysis = this.dataService.analyzeData(snapshot);
    // Keep the cross-session learner profile in sync with the latest real data.
    this.profileStore.updateFromAnalysis(analysis);
    return JSON.stringify(analysis);
  }

  private toolAnalyzeErrorBook(): string {
    const updatedCount = this.attributionService.updateErrorBookAttributions();
    // Refresh the profile after attributions are written back.
    const snapshot = this.dataService.collectAllData();
    this.profileStore.updateFromAnalysis(this.dataService.analyzeData(snapshot));
    const payload: AttributionToolResult = {
      updatedCount: updatedCount,
      message: updatedCount > 0 ?
        `已完成 ${updatedCount} 道错题的智能归因，并同步写入错题本。` :
        '错题本里暂时没有需要补充归因的题目。',
    };
    return JSON.stringify(payload);
  }

  private toolGeneratePractice(): string {
    const session = this.practiceService.generateSession(6);
    // Hand the generated session to the practice page so the action button
    // opens exactly the questions the agent produced.
    const sessionStore = new PracticeSessionStore();
    sessionStore.savePendingSession(session);

    const topics: string[] = [];
    for (let i = 0; i < session.questions.length; i++) {
      topics.push(session.questions[i].title);
    }
    // Remember what the learner is currently working on.
    this.profileStore.recordFocusTopics(topics);
    const payload: PracticeToolResult = {
      questionCount: session.questions.length,
      topics: topics,
      message: '已按当前薄弱知识点生成一组自适应练习题，练习页将直接使用这组题目。',
    };
    return JSON.stringify(payload);
  }

  private toolGetLearnerProfile(): string {
    const profile = this.profileStore.loadProfile();
    const hasData = profile.weakPoints.length > 0 || profile.strengths.length > 0 ||
      profile.focusTopics.length > 0 || profile.examCount > 0 ||
      profile.totalStudyTime > 0 || profile.analysisSummaries.length > 0;
    const payload: LearnerProfileToolResult = {
      weakPoints: profile.weakPoints,
      strengths: profile.strengths,
      focusTopics: profile.focusTopics,
      examCount: profile.examCount,
      avgScore: profile.avgScore,
      totalStudyTime: profile.totalStudyTime,
      analysisSummaries: profile.analysisSummaries,
      message: hasData ? '' : '学习档案暂无内容，请基于当前对话中的真实数据回答。',
    };
    return JSON.stringify(payload);
  }

  private toolGetExamHistory(): string {
    const snapshot = this.dataService.collectAllData();
    const payload: ExamHistoryToolResult = {
      count: snapshot.examScores.length,
      exams: snapshot.examScores,
      message: snapshot.examScores.length === 0 ? '暂无考试记录。' : '',
    };
    return JSON.stringify(payload);
  }

  private toolGetCourseProgress(): string {
    const snapshot = this.dataService.collectAllData();
    const payload: CourseProgressToolResult = {
      count: snapshot.courseProgress.length,
      courses: snapshot.courseProgress,
      message: snapshot.courseProgress.length === 0 ? '暂无课程进度记录。' : '',
    };
    return JSON.stringify(payload);
  }

  private toolGetErrorQuestions(): string {
    const snapshot = this.dataService.collectAllData();
    const payload: ErrorQuestionsToolResult = {
      count: snapshot.errorQuestions.length,
      errorQuestions: snapshot.errorQuestions,
      message: snapshot.errorQuestions.length === 0 ? '错题本为空。' : '',
    };
    return JSON.stringify(payload);
  }
}

/**
 * Builds the OpenAI-style tools array exposed to the LLM. Returned as a real
 * array (not a JSON string) so the request body serializes correctly.
 */
export function buildToolDefinitions(): ApiToolSchema[] {
  const definitions: ApiToolSchema[] = [];
  definitions.push(makeTool('get_learning_stats',
    '获取学生整体学习统计：考试次数与平均分、累计学习时长、成绩趋势、知识点掌握度、课程进度、薄弱点与优势。当学生询问学习情况、薄弱环节、学习建议或复习计划时调用。'));
  definitions.push(makeTool('analyze_error_book',
    '对错题本中尚未归因的错题执行智能归因（概念偏差/公式错误/方法不完整/计算错误/审题失误），并把归因结果写回错题本。当学生要求分析错题本或做错题归因时调用。'));
  definitions.push(makeTool('generate_practice',
    '根据当前薄弱知识点生成一组自适应练习题目。当学生想要练习、刷题或巩固薄弱知识点时调用。注意：真正的答题需要学生进入应用中的「自适应练习」页面。'));
  definitions.push(makeTool('get_exam_history',
    '获取学生的历次考试成绩记录（考试名称、分数、日期）。当学生询问考试成绩、成绩趋势或某次考试表现时调用。'));
  definitions.push(makeTool('get_course_progress',
    '获取学生各门课程的学习进度百分比。当学生询问课程进度、推荐课程或学习任务安排时调用。'));
  definitions.push(makeTool('get_error_questions',
    '获取错题本中的错题明细（题干、知识点、正确/错误选项、错误思路、笔记）。当学生询问错题详情或特定错题时调用。'));
  definitions.push(makeTool('get_learner_profile',
    '获取该学生的长期学习档案（跨会话记忆）：薄弱点、优势、近期练习主题、考试次数与平均分、累计学习时长、近期分析结论。当学生询问你对他/她的了解、之前聊过的内容、学习目标，或需要结合历史情况给出个性化建议时调用。'));
  return definitions;
}

/** Builds a single parameterless function tool entry. */
function makeTool(name: string, description: string): ApiToolSchema {
  const parameters: ApiToolParameters = { type: 'object' };
  const fn: ApiToolFunctionSchema = {
    name: name,
    description: description,
    parameters: parameters,
  };
  const tool: ApiToolSchema = { type: 'function', function: fn };
  return tool;
}

/** Human-readable status text shown in the chat UI while a tool runs. */
export function getToolStepLabel(toolName: string): string {
  switch (toolName) {
    case 'get_learning_stats':
      return '正在分析你的学习数据…';
    case 'analyze_error_book':
      return '正在为错题本做智能归因…';
    case 'generate_practice':
      return '正在生成自适应练习题…';
    case 'get_exam_history':
      return '正在查看你的考试记录…';
    case 'get_course_progress':
      return '正在查看你的课程进度…';
    case 'get_error_questions':
      return '正在整理你的错题明细…';
    case 'get_learner_profile':
      return '正在读取你的学习档案…';
    default:
      return `正在执行 ${toolName}…`;
  }
}

/** Builds an assistant message carrying tool calls, as the chat API expects. */
export function buildToolCallsMessage(toolCalls: AiToolCall[] | undefined): AiMessage {
  const msg = new AiMessage();
  msg.role = 'assistant';
  msg.content = '';
  msg.tool_calls = toolCalls;
  return msg;
}

/** Builds a tool result message that feeds a tool execution back to the LLM. */
export function buildToolResultMessage(toolCallId: string, resultContent: string): AiMessage {
  const msg = new AiMessage();
  msg.role = 'tool';
  msg.content = resultContent;
  msg.tool_call_id = toolCallId;
  return msg;
}

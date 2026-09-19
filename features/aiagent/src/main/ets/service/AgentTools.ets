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
  ApiToolProperty,
  ApiToolSchema,
  ApiToolFunctionSchema,
  ApiToolParameters,
  ExamScoreItem,
  ErrorQuestionItem,
  CourseProgressDataItem,
} from '../viewmodel/ChatModels';
import { KnowledgeHit } from '../viewmodel/KnowledgeModels';
import { DataCollectService } from './DataCollectService';
import { ErrorAttributionService } from './ErrorAttributionService';
import { AdaptivePracticeService } from './AdaptivePracticeService';
import { PracticeSessionStore } from './PracticeSessionStore';
import { LearnerProfileStore } from './LearnerProfileStore';
import { KnowledgeStore, describeKnowledgeSource } from './KnowledgeStore';

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

/** One retrieved course passage, numbered to match the citation the answer uses. */
interface KnowledgePassage {
  index: number;
  citation: string;
  source: string;
  knowledgeTag: string;
  text: string;
}

interface KnowledgeSearchToolResult {
  query: string;
  count: number;
  passages: KnowledgePassage[];
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
 * AdaptivePractice / KnowledgeStore) behind a stable name + JSON Schema
 * description that the LLM uses to decide when to call it. Tools return JSON
 * strings so their output can be fed back into the conversation as tool
 * messages.
 */
export class AgentToolRegistry {
  private dataService: DataCollectService = new DataCollectService();
  private attributionService: ErrorAttributionService = new ErrorAttributionService();
  private practiceService: AdaptivePracticeService = new AdaptivePracticeService();
  private profileStore: LearnerProfileStore = new LearnerProfileStore();
  /**
   * Shared instance: the agent and the chat fast path must hit the same index,
   * otherwise the corpus is built (and held in memory) twice.
   */
  private knowledgeStore: KnowledgeStore = KnowledgeStore.getInstance();

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
      case 'search_course_knowledge':
        return this.toolSearchCourseKnowledge(argsJson);
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

  /**
   * Retrieval over the local course corpus. Read-only and local: no API call,
   * no personal data, so it is safe to run on every round the model asks for it.
   *
   * A miss is reported as an explicit "not in the course material" message
   * rather than an empty list. That phrasing is the point: it tells the model
   * to say so instead of inventing a passage, which is the same "no data, no
   * fiction" contract the learning-data tools already follow.
   *
   * `searchBest` is the hybrid retriever, so this returns the fused ranking
   * whenever a dense side is available and the lexical one otherwise. Awaiting
   * it costs nothing when there is no embedder configured — the promise settles
   * without a request — and the failure path is silent by construction, so a
   * broken embedder can never turn into a failed tool call.
   */
  private async toolSearchCourseKnowledge(argsJson: string): Promise<string> {
    const query = parseToolQuery(argsJson);
    if (query.length === 0) {
      const errorResult = new ToolErrorResult();
      errorResult.error = '缺少 query 参数：请传入要检索的知识点关键词，例如 {"query":"三次握手"}。';
      return JSON.stringify(errorResult);
    }

    const hits = await this.knowledgeStore.searchBest(query);
    const passages: KnowledgePassage[] = [];
    for (let i = 0; i < hits.length; i++) {
      const hit: KnowledgeHit = hits[i];
      const passage: KnowledgePassage = {
        index: i + 1,
        citation: this.knowledgeStore.citationOf(hit),
        source: describeKnowledgeSource(hit.chunk.sourceType),
        knowledgeTag: hit.chunk.knowledgeTag,
        text: hit.chunk.text,
      };
      passages.push(passage);
    }

    const payload: KnowledgeSearchToolResult = {
      query: query,
      count: passages.length,
      passages: passages,
      message: passages.length === 0 ?
        `课程知识库中没有匹配「${query}」的内容。请如实告知学生课程资料未覆盖该知识点，` +
        '可以给出通用解释，但要说明这部分不在课程资料中，且不得编造出处。' :
        '以上为课程知识库中的原文片段，回答时请用【出处】标注引用来源，并只依据这些内容陈述课程观点。',
    };
    return JSON.stringify(payload);
  }
}

/**
 * Reads the `query` argument out of a tool call's raw JSON.
 *
 * Models occasionally send empty or malformed arguments; both are reported as
 * "missing query" rather than throwing, so a bad tool call costs one round
 * instead of the whole turn.
 */
function parseToolQuery(argsJson: string): string {
  if (typeof argsJson !== 'string' || argsJson.trim().length === 0) {
    return '';
  }
  try {
    const parsed = JSON.parse(argsJson) as Record<string, Object>;
    const raw = parsed['query'];
    return typeof raw === 'string' ? raw.trim() : '';
  } catch (e) {
    return '';
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
  definitions.push(makeQueryTool('search_course_knowledge',
    '检索本地课程知识库（各门课程的教学大纲要点与题库解析），返回带出处的原文片段。当学生询问学科知识本身时调用，例如"什么是X""X和Y的区别""X的原理/定义/作用"。不用于查询学生个人学习数据。',
    '要检索的知识点关键词，用课程里的术语，例如"三次握手""二叉树的遍历""进程与线程的区别"。'));
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

/**
 * Builds a function tool entry taking one required string argument named
 * `query`. The seven data tools are parameterless; retrieval is the first tool
 * that needs input from the model, so the argument name is fixed here rather
 * than generic — one caller, one shape.
 */
function makeQueryTool(name: string, description: string, paramDescription: string): ApiToolSchema {
  const queryProperty: ApiToolProperty = { type: 'string', description: paramDescription };
  const properties: Record<string, ApiToolProperty> = { 'query': queryProperty };
  const parameters: ApiToolParameters = {
    type: 'object',
    properties: properties,
    required: ['query'],
  };
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
    case 'search_course_knowledge':
      return '正在检索课程知识…';
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

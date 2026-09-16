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
  ChatMessage,
  ChatSession,
  MessageRole,
  MessageStatus,
  LearningAnalysisData,
  AiMessage,
  ErrorQuestionItem,
} from './ChatModels';
import { AiService, ApiKeyMissingError } from '../service/AiService';
import { AgentService, AgentLimitError, AgentTimeoutError } from '../service/AgentService';
import { SessionStore } from '../service/SessionStore';
import { DataCollectService } from '../service/DataCollectService';
import { ErrorAttributionService } from '../service/ErrorAttributionService';
import { AdaptivePracticeService } from '../service/AdaptivePracticeService';
import { PracticeSessionStore } from '../service/PracticeSessionStore';
import { IntentRouter, ChatIntent } from '../service/IntentRouter';
import { ContextCompressor } from '../service/ContextCompressor';
import { LearnerProfileStore } from '../service/LearnerProfileStore';
import { Logger } from '@safe/basic';
import { AiConstants } from '../utils/AiConstants';

const ACTION_START_PRACTICE = '{"action":"start_practice"}';

@Observed
export class ChatViewModel {
  currentSession: ChatSession;
  sessionList: ChatSession[];
  isLoading: boolean;
  isStreaming: boolean;
  inputText: string;
  private aiService: AiService;
  private agentService: AgentService;
  private sessionStore: SessionStore;
  private intentRouter: IntentRouter;
  private contextCompressor: ContextCompressor;
  private profileStore: LearnerProfileStore;
  private messageIdCounter: number;
  private sessionIdCounter: number;
  private activeStepId: string = '';
  private onStateChange?: () => void;
  /** Bumped on every send/cancel so a stale run can't clobber newer state. */
  private runSeq: number = 0;
  /** True when the user pressed the stop button for the in-flight run. */
  private userCancelled: boolean = false;

  constructor() {
    this.aiService = new AiService();
    this.agentService = new AgentService();
    this.sessionStore = new SessionStore();
    this.intentRouter = new IntentRouter();
    this.contextCompressor = new ContextCompressor();
    this.profileStore = new LearnerProfileStore();
    this.sessionList = [];
    this.messageIdCounter = 0;
    this.sessionIdCounter = 0;
    this.isLoading = false;
    this.isStreaming = false;
    this.inputText = '';

    const restored = this.sessionStore.loadSessions();
    if (restored.length > 0) {
      this.sessionList = restored;
      this.currentSession = restored[0];
    } else {
      this.currentSession = this.createNewSession();
      this.sessionList = [...this.sessionList, this.currentSession];
      this.initWelcomeMessage();
    }
  }

  setStateChangeCallback(cb: () => void): void {
    this.onStateChange = cb;
  }

  private notifyChange(): void {
    if (this.onStateChange) {
      this.onStateChange();
    }
  }

  private createNewSession(): ChatSession {
    // Counter suffix keeps ids unique even when sessions are created within
    // the same millisecond (fast taps), otherwise switching/deleting would
    // address the wrong session.
    this.sessionIdCounter += 1;
    const id = `session_${Date.now()}_${this.sessionIdCounter}`;
    return new ChatSession(id, '新对话');
  }

  private initWelcomeMessage(): void {
    const welcomeMsg = new ChatMessage(
      this.generateMessageId(),
      MessageRole.AI,
      AiConstants.WELCOME_MESSAGE,
      MessageStatus.SUCCESS,
    );
    this.currentSession.messages = [...this.currentSession.messages, welcomeMsg];
    this.notifyChange();
  }

  private generateMessageId(): string {
    this.messageIdCounter += 1;
    return `msg_${Date.now()}_${this.messageIdCounter}`;
  }

  newSession(): void {
    if (this.currentSession.messages.length <= 1) {
      return;
    }
    this.currentSession = this.createNewSession();
    this.sessionList = [...this.sessionList, this.currentSession];
    this.initWelcomeMessage();
    this.saveSessions();
    this.notifyChange();
  }

  switchSession(sessionId: string): void {
    const target = this.sessionList.find((s) => s.id === sessionId);
    if (target) {
      this.currentSession = target;
      this.notifyChange();
    }
  }

  deleteSession(sessionId: string): void {
    const index = this.sessionList.findIndex((s) => s.id === sessionId);
    if (index !== -1) {
      this.sessionList = this.sessionList.filter((s) => s.id !== sessionId);
      if (this.currentSession.id === sessionId) {
        if (this.sessionList.length > 0) {
          this.currentSession = this.sessionList[0];
        } else {
          this.newSession();
        }
      }
      this.saveSessions();
      this.notifyChange();
    }
  }

  async sendMessage(text: string, includeAnalysis: boolean = false): Promise<void> {
    if (text.trim() === '' || this.isLoading) {
      return;
    }
    this.userCancelled = false;
    this.runSeq += 1;
    const runId = this.runSeq;

    const userMessage = new ChatMessage(
      this.generateMessageId(),
      MessageRole.USER,
      text.trim(),
      MessageStatus.SUCCESS,
    );
    this.currentSession.messages = [...this.currentSession.messages, userMessage];
    this.currentSession.updateTime = Date.now();
    this.notifyChange();

    if (this.currentSession.title === '新对话') {
      this.currentSession.title = text.trim().substring(0, 20);
    }

    const aiMessage = new ChatMessage(
      this.generateMessageId(),
      MessageRole.AI,
      '',
      MessageStatus.SENDING,
    );
    this.currentSession.messages = [...this.currentSession.messages, aiMessage];
    this.isLoading = true;
    this.isStreaming = true;
    this.notifyChange();

    const intent = this.intentRouter.route(text.trim());
    try {
      if (intent === ChatIntent.PRACTICE) {
        this.replyPracticeReady(aiMessage);
      } else if (intent === ChatIntent.CHAT) {
        await this.runPlainChat(text.trim(), aiMessage);
      } else {
        await this.runAgentChat(text.trim(), aiMessage);
      }
    } catch (err) {
      if (this.userCancelled) {
        // The pending bubble was already dropped by cancelRequest().
        Logger.info(`[ChatViewModel] send cancelled by user (${intent})`);
      } else {
        Logger.error(`[ChatViewModel] send failed (${intent}): ${err instanceof Error ? err.message : err}`);
        aiMessage.content = this.buildErrorMessage(err);
        aiMessage.status = MessageStatus.FAILED;
      }
    } finally {
      if (this.runSeq === runId) {
        this.isLoading = false;
        this.isStreaming = false;
        this.currentSession.updateTime = Date.now();
        this.saveSessions();
        this.notifyChange();
      }
    }
  }

  /**
   * Stops the in-flight request (user pressed the stop button). The pending
   * SENDING bubble is dropped so the user never sees a fake error for their
   * own cancellation. runSeq is bumped so the stale run's finally block does
   * not clobber the state of whatever the user starts next.
   */
  cancelRequest(): void {
    if (!this.isLoading) {
      return;
    }
    this.userCancelled = true;
    this.runSeq += 1;
    this.aiService.cancelRequest();
    this.agentService.cancel();

    const kept: ChatMessage[] = [];
    for (const m of this.currentSession.messages) {
      if (m.status !== MessageStatus.SENDING) {
        kept.push(m);
      }
    }
    this.currentSession.messages = kept;
    this.isLoading = false;
    this.isStreaming = false;
    this.currentSession.updateTime = Date.now();
    this.saveSessions();
    this.notifyChange();
  }

  /** PRACTICE intent: generate locally, hand off to the practice page, no API call. */
  private replyPracticeReady(aiMessage: ChatMessage): void {
    const practiceService = new AdaptivePracticeService();
    const session = practiceService.generateSession(6);
    new PracticeSessionStore().savePendingSession(session);
    // Same profile write-back as the agent's generate_practice tool.
    const topics: string[] = [];
    for (let i = 0; i < session.questions.length; i++) {
      topics.push(session.questions[i].title);
    }
    this.profileStore.recordFocusTopics(topics);
    aiMessage.content = `已按你的薄弱知识点生成一组共 ${session.questions.length} 道练习题，点击下方按钮开始吧！`;
    aiMessage.action = 'start_practice';
    aiMessage.status = MessageStatus.SUCCESS;
  }

  /** CHAT intent: plain conversation without tools (fast & cheap), with streaming + fallback. */
  private async runPlainChat(userText: string, aiMessage: ChatMessage): Promise<void> {
    const messages = this.buildContextMessages(AiConstants.SYSTEM_PROMPT);
    const userMsg = new AiMessage();
    userMsg.role = 'user';
    userMsg.content = userText;
    messages.push(userMsg);

    let fullContent = '';
    const delivered = await this.aiService.chatWithFallback(
      messages,
      (chunk: string) => {
        fullContent += chunk;
        aiMessage.content = fullContent;
        this.currentSession.messages = [...this.currentSession.messages];
        this.notifyChange();
      },
    );

    if (delivered === 0) {
      throw new Error('AI 未返回有效回答，请稍后重试。');
    }
    aiMessage.status = MessageStatus.SUCCESS;
  }

  /** ANALYTICS intent: full agent loop with tool access. */
  private async runAgentChat(userText: string, aiMessage: ChatMessage): Promise<void> {
    let fullContent = '';
    await this.agentService.run(
      this.buildAgentMessages(userText),
      (stepText: string, isDone: boolean) => {
        this.showStepMessage(stepText, isDone);
      },
      (chunk: string) => {
        fullContent += chunk;
        aiMessage.content = fullContent;
        this.currentSession.messages = [...this.currentSession.messages];
        this.notifyChange();
      },
    );
    if (fullContent.trim().length === 0) {
      throw new Error('AI 未返回有效回答，请稍后重试。');
    }
    this.extractAction(aiMessage);
    // The tutor's own conclusion becomes part of its cross-session memory.
    this.profileStore.recordAnalysisSummary(aiMessage.content);
    aiMessage.status = MessageStatus.SUCCESS;
  }

  async requestAnalysis(analysisData: LearningAnalysisData): Promise<void> {
    if (this.isLoading) {
      return;
    }

    const userMessage = new ChatMessage(
      this.generateMessageId(),
      MessageRole.USER,
      '帮我分析一下我的学习情况',
      MessageStatus.SUCCESS,
    );
    this.currentSession.messages = [...this.currentSession.messages, userMessage];
    this.notifyChange();

    const aiMessage = new ChatMessage(
      this.generateMessageId(),
      MessageRole.ANALYSIS,
      '',
      MessageStatus.SENDING,
      analysisData,
    );
    this.currentSession.messages = [...this.currentSession.messages, aiMessage];
    this.isLoading = true;
    this.isStreaming = true;
    this.notifyChange();

    try {
      const analysisPrompt = this.buildAnalysisPrompt(analysisData);
      const sysMsg = new AiMessage();
      sysMsg.role = 'system';
      sysMsg.content = AiConstants.SYSTEM_PROMPT;

      const usrMsg = new AiMessage();
      usrMsg.role = 'user';
      usrMsg.content = analysisPrompt;

      const messages: AiMessage[] = [sysMsg, usrMsg];

      let fullContent = '';
      await this.aiService.chatStream(
        messages,
        (chunk: string) => {
          fullContent += chunk;
          aiMessage.content = fullContent;
          this.currentSession.messages = [...this.currentSession.messages];
          this.notifyChange();
        },
      );

      if (fullContent.trim().length === 0) {
        aiMessage.content = this.generateLocalAnalysisText(analysisData);
      }
      aiMessage.status = MessageStatus.SUCCESS;
    } catch (err) {
      aiMessage.content = this.generateLocalAnalysisText(analysisData);
      aiMessage.status = MessageStatus.SUCCESS;
    } finally {
      this.isLoading = false;
      this.isStreaming = false;
      this.currentSession.updateTime = Date.now();
      this.saveSessions();
      this.notifyChange();
    }
  }

  async requestErrorBookAnalysis(): Promise<void> {
    if (this.isLoading) {
      return;
    }

    const dataService = new DataCollectService();
    const snapshot = dataService.collectAllData();
    const errorQuestions = snapshot.errorQuestions;

    if (errorQuestions.length === 0) {
      const emptyMsg = new ChatMessage(
        this.generateMessageId(),
        MessageRole.AI,
        '你还没有错题记录哦～先去添加一些错题，我就能帮你分析啦！',
        MessageStatus.SUCCESS,
      );
      this.currentSession.messages = [...this.currentSession.messages, emptyMsg];
      this.notifyChange();
      return;
    }

    const userMessage = new ChatMessage(
      this.generateMessageId(),
      MessageRole.USER,
      '帮我详细分析我的错题本，找出薄弱知识点并给出学习建议',
      MessageStatus.SUCCESS,
    );
    this.currentSession.messages = [...this.currentSession.messages, userMessage];
    this.notifyChange();

    const aiMessage = new ChatMessage(
      this.generateMessageId(),
      MessageRole.ANALYSIS,
      '',
      MessageStatus.SENDING,
    );
    this.currentSession.messages = [...this.currentSession.messages, aiMessage];
    this.isLoading = true;
    this.isStreaming = true;
    this.notifyChange();

    try {
      const analysisPrompt = this.buildErrorBookAnalysisPrompt(errorQuestions);
      const sysMsg = new AiMessage();
      sysMsg.role = 'system';
      sysMsg.content = AiConstants.ERROR_BOOK_ANALYSIS_PROMPT;

      const usrMsg = new AiMessage();
      usrMsg.role = 'user';
      usrMsg.content = analysisPrompt;

      const messages: AiMessage[] = [sysMsg, usrMsg];

      let fullContent = '';
      await this.aiService.chatStream(
        messages,
        (chunk: string) => {
          fullContent += chunk;
          aiMessage.content = fullContent;
          this.currentSession.messages = [...this.currentSession.messages];
          this.notifyChange();
        },
      );

      if (fullContent.trim().length === 0) {
        aiMessage.content = this.generateLocalErrorAnalysisText(errorQuestions);
      }
      aiMessage.status = MessageStatus.SUCCESS;
    } catch (err) {
      aiMessage.content = this.generateLocalErrorAnalysisText(errorQuestions);
      aiMessage.status = MessageStatus.SUCCESS;
    } finally {
      this.isLoading = false;
      this.isStreaming = false;
      this.currentSession.updateTime = Date.now();
      this.saveSessions();
      this.notifyChange();
    }
  }

  requestErrorAttribution(): void {
    if (this.isLoading) {
      return;
    }

    const userMessage = new ChatMessage(
      this.generateMessageId(),
      MessageRole.USER,
      '帮我对错题本做智能归因',
      MessageStatus.SUCCESS,
    );
    this.currentSession.messages = [...this.currentSession.messages, userMessage];
    this.notifyChange();

    const service = new ErrorAttributionService();
    const updatedCount = service.updateErrorBookAttributions();
    const content = updatedCount > 0 ?
      `已完成 ${updatedCount} 道错题的智能归因，并同步写入错题本。\n\n你现在可以回到错题本查看每道题的「AI分析」结果。建议优先处理归因为“概念理解偏差”和“公式/规则使用错误”的题目。` :
      '错题本里暂时没有需要补充归因的题目。如果你新增错题或补充错误思路，我可以继续帮你分析。';

    const aiMessage = new ChatMessage(
      this.generateMessageId(),
      MessageRole.AI,
      content,
      MessageStatus.SUCCESS,
    );
    this.currentSession.messages = [...this.currentSession.messages, aiMessage];
    this.currentSession.updateTime = Date.now();
    this.notifyChange();
  }

  private buildErrorBookAnalysisPrompt(errorQuestions: ErrorQuestionItem[]): string {
    let prompt = '请根据以下错题记录，进行详细的错题分析并给出学习指导：\n\n';

    prompt += `【错题总数】共 ${errorQuestions.length} 道错题\n\n`;

    // Group by category
    const categoryMap = new Map<string, ErrorQuestionItem[]>();
    for (const eq of errorQuestions) {
      if (!categoryMap.has(eq.category)) {
        categoryMap.set(eq.category, []);
      }
      categoryMap.get(eq.category)!.push(eq);
    }

    prompt += '【按知识点分类统计】\n';
    const entries: Array<[string, ErrorQuestionItem[]]> = [];
    categoryMap.forEach((v, k) => {
      entries.push([k, v]);
    });
    entries.sort((a, b) => b[1].length - a[1].length);
    for (let i = 0; i < entries.length; i++) {
      const cat = entries[i][0];
      const items = entries[i][1];
      prompt += `  - ${cat}: ${items.length} 道错题（占比 ${Math.round(items.length / errorQuestions.length * 100)}%）\n`;
    }

    prompt += '\n【错题详情】\n';
    for (let i = 0; i < errorQuestions.length; i++) {
      const eq = errorQuestions[i];
      prompt += `\n${i + 1}. [${eq.category}] ${eq.title}`;
      // Show options with correct/wrong markers
      if (eq.options.length > 0) {
        prompt += '\n   选项：';
        for (let j = 0; j < eq.options.length; j++) {
          let marker = '';
          if (j === eq.correctIndex) {
            marker = '✓';
          }
          if (j === eq.userIndex && j !== eq.correctIndex) {
            marker = '✗';
          }
          const label = String.fromCharCode(65 + j);
          prompt += `${label}.${eq.options[j]}${marker ? '(' + marker + ')' : ''}  `;
        }
      }
      // Answer comparison
      if (eq.correctLabel && eq.userLabel) {
        prompt += `\n   正确答案：${eq.correctLabel}  用户答案：${eq.userLabel}`;
      } else if (eq.correctLabel) {
        prompt += `\n   正确答案：${eq.correctLabel}`;
      }
      if (eq.mistakeReason) {
        prompt += `\n   错误思路：${eq.mistakeReason}`;
      }
      if (eq.userNote) {
        prompt += `\n   学习笔记：${eq.userNote}`;
      }
      prompt += '\n';
    }

    prompt += '\n请从以下几个方面给出详细分析：\n';
    prompt += '1. 错题分布分析：哪些知识点错题最多？可能的原因是什么？\n';
    prompt += '2. 常见错误模式：从错误思路和用户选择的错误选项中，总结常犯的错误类型（概念混淆、公式记错、计算失误、审题不清等）\n';
    prompt += '3. 薄弱环节诊断：明确指出当前最薄弱的2-3个知识点，结合正确率和错误类型分析\n';
    prompt += '4. 针对性学习建议：针对每个薄弱知识点，给出具体的复习方法、经典习题推荐和易错点提醒\n';
    prompt += '5. 学习路径规划：建议接下来1-2周的学习优先级和每日时间分配方案\n';

    return prompt;
  }

  private generateLocalErrorAnalysisText(errorQuestions: ErrorQuestionItem[]): string {
    let text = '📊 **错题本分析报告**\n\n';

    // Category stats
    const categoryMap = new Map<string, number>();
    for (const eq of errorQuestions) {
      const count = categoryMap.get(eq.category) || 0;
      categoryMap.set(eq.category, count + 1);
    }

    const entries: Array<[string, number]> = [];
    categoryMap.forEach((v, k) => {
      entries.push([k, v]);
    });
    entries.sort((a, b) => b[1] - a[1]);

    text += `**错题总数：** ${errorQuestions.length} 道\n`;
    text += `**涉及知识点：** ${entries.length} 个\n\n`;

    text += '**📈 知识点错误分布：**\n';
    for (let i = 0; i < entries.length; i++) {
      const pct = Math.round(entries[i][1] / errorQuestions.length * 100);
      const bar = '█'.repeat(Math.max(1, Math.floor(pct / 10)));
      text += `  ${bar} ${entries[i][0]}: ${entries[i][1]}道 (${pct}%)\n`;
    }

    // Answer accuracy analysis
    let totalAnswered = 0;
    let totalWrong = 0;
    for (const eq of errorQuestions) {
      if (eq.userIndex >= 0) {
        totalAnswered++;
        if (eq.userIndex !== eq.correctIndex) {
          totalWrong++;
        }
      }
    }
    if (totalAnswered > 0) {
      const accuracy = Math.round((totalAnswered - totalWrong) / totalAnswered * 100);
      text += `\n**🎯 答题准确率：** ${accuracy}%（${totalAnswered - totalWrong}/${totalAnswered}）\n`;
    }

    // Error type analysis
    const hasNotes = errorQuestions.filter((eq) => eq.userNote.length > 0).length;
    const hasReasons = errorQuestions.filter((eq) => eq.mistakeReason.length > 0).length;
    if (hasReasons > 0) {
      text += `\n**📝 已记录错误思路：** ${hasReasons}/${errorQuestions.length} 道\n`;
      text += '常见的错误思路总结：\n';
      const reasonList: string[] = [];
      for (const eq of errorQuestions) {
        if (eq.mistakeReason && reasonList.length < 5) {
          reasonList.push(`  • [${eq.category}] ${eq.mistakeReason}`);
        }
      }
      for (const r of reasonList) {
        text += r + '\n';
      }
    }

    text += '\n**⚠️ 薄弱环节诊断：**\n';
    const topWeak = entries.slice(0, Math.min(3, entries.length));
    for (let i = 0; i < topWeak.length; i++) {
      text += `  ${i + 1}. ${topWeak[i][0]}：${topWeak[i][1]}道错题，需重点突破\n`;
    }

    text += '\n**💡 学习建议：**\n';
    if (entries.length > 0) {
      text += `  1. 优先攻克「${entries[0][0]}」，这是当前错误最多的知识点\n`;
      text += '  2. 每道错题做到"三清"：清概念、清算理、清解法\n';
      text += '  3. 对同类错题进行变式训练，避免机械记忆\n';
      text += '  4. 每周回顾一次错题本，自测是否真正掌握\n';
    }
    if (hasNotes < errorQuestions.length) {
      text += `  5. 还有 ${errorQuestions.length - hasNotes} 道错题没有记录学习笔记，建议补充\n`;
    }

    text += '\n**📅 建议学习优先级：**\n';
    for (let i = 0; i < Math.min(5, entries.length); i++) {
      const priority = entries[i][1] >= 3 ? '高' : (entries[i][1] >= 2 ? '中' : '低');
      const minutes = entries[i][1] >= 3 ? '45' : '30';
      text += `  ${i + 1}. [${priority}优先] ${entries[i][0]}：建议每日练习${minutes}分钟\n`;
    }

    return text;
  }

  private buildContextMessages(systemPrompt: string): AiMessage[] {
    const sysMsg = new AiMessage();
    sysMsg.role = 'system';
    sysMsg.content = systemPrompt;

    const messages: AiMessage[] = [sysMsg];

    // Inject the learner's cross-session profile as a second system message so
    // both the plain chat path and the agent loop "remember" the learner.
    const profilePrompt = this.profileStore.buildProfilePrompt();
    if (profilePrompt.length > 0) {
      const profileMsg = new AiMessage();
      profileMsg.role = 'system';
      profileMsg.content = profilePrompt;
      messages.push(profileMsg);
    }

    const allChat = this.currentSession.messages
      .filter((m) => m.role === MessageRole.USER || m.role === MessageRole.AI);
    const windowSize = AiConstants.MAX_HISTORY_MESSAGES;
    let recentMessages = allChat.slice(-windowSize);

    // Compress older turns into a local summary so early context survives
    // the history window instead of being hard-truncated.
    if (allChat.length > windowSize) {
      const older = allChat.slice(0, allChat.length - windowSize);
      const summary = this.contextCompressor.buildHistorySummary(older);
      if (summary.length > 0) {
        const summaryMsg = new AiMessage();
        summaryMsg.role = 'system';
        summaryMsg.content = summary;
        messages.push(summaryMsg);
      }
    }

    for (const msg of recentMessages) {
      if (msg.role === MessageRole.USER) {
        const userMsg = new AiMessage();
        userMsg.role = 'user';
        userMsg.content = msg.content;
        messages.push(userMsg);
      } else if (msg.role === MessageRole.AI && msg.status === MessageStatus.SUCCESS) {
        const aiMsg = new AiMessage();
        aiMsg.role = 'assistant';
        aiMsg.content = msg.content;
        messages.push(aiMsg);
      }
    }

    return messages;
  }

  /**
   * Builds the message list handed to the agent loop: agent system prompt,
   * recent conversation history, and the user's latest input.
   */
  private buildAgentMessages(userText: string): AiMessage[] {
    const messages = this.buildContextMessages(this.buildAgentSystemPrompt());
    const userMsg = new AiMessage();
    userMsg.role = 'user';
    userMsg.content = userText;
    messages.push(userMsg);
    return messages;
  }

  /**
   * System prompt for the agent loop. Tool usage rules and the action-JSON
   * protocol keep the model grounded in real learner data and let the UI
   * turn "suggestions" into tap-through actions.
   */
  private buildAgentSystemPrompt(): string {
    return `你是专业的教育学习助教"小智"，拥有以下工具，回答前按需调用：
1. get_learning_stats：查询学生整体学习统计（考试、时长、成绩趋势、知识点掌握、课程进度、薄弱点与优势）。当学生问学习情况、薄弱环节、复习建议、学习计划时调用。
2. get_exam_history：查询历次考试成绩。学生问成绩或成绩趋势时调用。
3. get_course_progress：查询各课程学习进度。学生问课程进度或学习任务安排时调用。
4. get_error_questions：查询错题本明细。学生问具体错题时调用。
5. analyze_error_book：对错题本做智能归因并写回错题本。学生要求分析错题本或做错题归因时调用。
6. generate_practice：根据薄弱知识点生成一组自适应练习题。学生想练习、刷题时调用。
7. get_learner_profile：查询该学生的长期学习档案（跨会话记忆）。学生询问你对他/她的了解、历史分析结论，或需要结合历史情况回答时调用。

工作规则：
- 涉及学生个人学习数据的问题，必须先调用对应工具获取真实数据，严禁凭空编造成绩、课程、时长或错题。
- 数据不足时如实说明，不要虚构。
- 回答简洁、具体、可执行，多用真实数据说话，语气亲切鼓励。
- 每个工具调用不要超过一次。
- 学生的长期学习档案会以系统消息提供，回答时自然结合这些历史情况，避免重复询问已知信息。
- 当你的建议包含"开始练习"且学生尚未练习时，在回答正文之后另起一行输出一行 JSON 指令：{"action":"start_practice"}；其余情况不要输出 JSON。`;
  }

  /**
   * Detects the action JSON in the model reply, strips it from the visible
   * content and stores it on the message so the UI can render a tap-through.
   */
  private extractAction(message: ChatMessage): void {
    const idx = message.content.indexOf(ACTION_START_PRACTICE);
    if (idx < 0) {
      return;
    }
    message.action = 'start_practice';
    const lineStart = message.content.lastIndexOf('\n', idx);
    const lineEnd = message.content.indexOf('\n', idx);
    if (lineStart >= 0 && lineEnd >= 0) {
      message.content = message.content.substring(0, lineStart) + message.content.substring(lineEnd);
    } else if (lineStart >= 0) {
      message.content = message.content.substring(0, lineStart);
    } else if (lineEnd >= 0) {
      message.content = message.content.substring(lineEnd + 1);
    } else {
      message.content = message.content.replace(ACTION_START_PRACTICE, '');
    }
    message.content = message.content.trim();
  }

  /**
   * Inserts a lightweight progress message while a tool is running. When the
   * tool completes, the SAME message is updated in place (never duplicated)
   * so the UI shows exactly one spinner per tool, then a checkmark.
   */
  private showStepMessage(stepText: string, isDone: boolean): void {
    if (isDone && this.activeStepId !== '') {
      const updated: ChatMessage[] = [];
      for (const m of this.currentSession.messages) {
        if (m.id === this.activeStepId) {
          m.stepDone = true;
        }
        updated.push(m);
      }
      this.currentSession.messages = updated;
      this.activeStepId = '';
      this.notifyChange();
      return;
    }

    const stepMsg = new ChatMessage(
      this.generateMessageId(),
      MessageRole.STEP,
      stepText,
      MessageStatus.SUCCESS,
    );
    stepMsg.stepDone = false;
    this.activeStepId = stepMsg.id;
    this.currentSession.messages = [...this.currentSession.messages, stepMsg];
    this.notifyChange();
  }

  /**
   * Maps agent failures to user-facing text. AgentLimitError and
   * AgentTimeoutError keep their own messages; anything else shows a generic
   * hint plus the raw error detail (temporarily, to ease debugging — remove
   * the detail for release).
   */
  private buildErrorMessage(err: Object): string {
    if (err instanceof AgentLimitError || err instanceof AgentTimeoutError ||
      err instanceof ApiKeyMissingError) {
      return (err as Error).message;
    }
    const errMsg = err instanceof Error ? err.message : 'Unknown error';
    return `抱歉，我暂时无法回复你的问题。\n\n错误详情：${errMsg}`;
  }

  /** Persists sessions that contain at least one user message. */
  private saveSessions(): void {
    const meaningful = this.sessionList.filter((s: ChatSession) => {
      for (let i = 0; i < s.messages.length; i++) {
        if (s.messages[i].role === MessageRole.USER) {
          return true;
        }
      }
      return false;
    });
    this.sessionStore.saveSessions(meaningful);
  }

  private buildAnalysisPrompt(data: LearningAnalysisData): string {
    let prompt = '请根据以下学习数据进行分析，给出详细的学习指导建议：\n\n';

    if (data.totalExams > 0) {
      prompt += `【考试情况】共参加 ${data.totalExams} 次考试，平均分 ${data.avgScore} 分。\n`;
    } else {
      prompt += '【考试情况】暂无真实考试记录，请不要推测或虚构成绩。\n';
    }

    if (data.totalStudyTime > 0) {
      prompt += `【累计学习时长】${data.totalStudyTime} 分钟。\n`;
    } else {
      prompt += '【累计学习时长】暂无可靠记录。\n';
    }

    if (data.scoreTrend.length > 0) {
      prompt += '成绩趋势：\n';
      for (const item of data.scoreTrend) {
        prompt += `  - ${item.examName}(${item.date}): ${item.score}分\n`;
      }
    }

    if (data.weakPoints.length > 0) {
      prompt += `\n【薄弱知识点】${data.weakPoints.join('、')}\n`;
    }

    if (data.strengths.length > 0) {
      prompt += `\n【优势领域】${data.strengths.join('、')}\n`;
    }

    if (data.knowledgePoints.length > 0) {
      prompt += '\n【知识点掌握详情】\n';
      for (const kp of data.knowledgePoints) {
        prompt += `  - ${kp.name}: 错题 ${kp.total} 道，基于错题频次估算掌握度 ${kp.mastery}%\n`;
      }
    }

    if (data.courseProgress.length > 0) {
      prompt += '\n【课程进度】\n';
      for (const cp of data.courseProgress) {
        prompt += `  - ${cp.courseName}: ${cp.progress}% (教师: ${cp.teacher})\n`;
      }
    }

    prompt += '\n请给出：\n1. 整体学习评估\n2. 薄弱环节分析\n3. 具体的学习建议\n4. 推荐的学习路径';
    prompt += '\n必须只依据上述真实数据；数据不足时请明确说明，不得补造考试、课程或学习时长。';

    return prompt;
  }

  private generateLocalAnalysisText(data: LearningAnalysisData): string {
    let text = '📊 **学习分析报告**\n\n';

    if (data.totalExams > 0) {
      text += `**考试情况：** 共参加 ${data.totalExams} 次考试，平均分 ${data.avgScore} 分。\n\n`;
    } else {
      text += '**考试情况：** 暂无真实考试记录。\n\n';
    }

    text += data.totalStudyTime > 0 ?
      `**累计学习时长：** ${data.totalStudyTime} 分钟。\n\n` :
      '**累计学习时长：** 暂无可靠记录。\n\n';

    if (data.scoreTrend.length > 0) {
      text += '**成绩趋势：**\n';
      for (const st of data.scoreTrend) {
        text += `  - ${st.examName}: ${st.score}分\n`;
      }
      text += '\n';
    }

    if (data.weakPoints.length > 0) {
      text += `**⚠ 薄弱环节：** ${data.weakPoints.join('、')}\n\n`;
    }

    if (data.strengths.length > 0) {
      text += `**✅ 优势领域：** ${data.strengths.join('、')}\n\n`;
    }

    text += '**💡 学习建议：**\n';
    if (data.weakPoints.length > 0) {
      text += `1. 重点复习：${data.weakPoints[0]}，这是当前最需要加强的知识点。\n`;
      text += '2. 建议每天安排 30-60 分钟的专项练习时间。\n';
    } else if (data.totalExams === 0 && data.knowledgePoints.length === 0) {
      text += '1. 当前数据不足，建议先完成一次考试或练习，以便生成可靠分析。\n';
      text += '2. 记录错题原因和课程进度，可提升后续建议的针对性。\n';
    } else {
      text += '1. 继续保持当前学习节奏，并定期用练习检验掌握情况。\n';
      text += '2. 优先完成进度较低的课程，避免学习任务长期积压。\n';
    }
    text += '3. 定期进行模拟考试，检验学习效果。\n';
    text += '4. 关注课程学习进度，按时完成线上培训任务。\n';

    return text;
  }

  getRecommendQuestions(): string[] {
    return AiConstants.RECOMMEND_QUESTIONS;
  }
}

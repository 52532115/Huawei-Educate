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
import { AiService } from '../service/AiService';
import { DataCollectService } from '../service/DataCollectService';
import { AiConstants } from '../utils/AiConstants';

@Observed
export class ChatViewModel {
  currentSession: ChatSession;
  sessionList: ChatSession[];
  isLoading: boolean;
  isStreaming: boolean;
  inputText: string;
  private aiService: AiService;
  private messageIdCounter: number;
  private onStateChange?: () => void;

  constructor() {
    this.aiService = new AiService();
    this.sessionList = [];
    this.messageIdCounter = 0;
    this.isLoading = false;
    this.isStreaming = false;
    this.inputText = '';
    this.currentSession = this.createNewSession();
    this.sessionList = [...this.sessionList, this.currentSession];
    this.initWelcomeMessage();
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
    const id = `session_${Date.now()}`;
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
      this.notifyChange();
    }
  }

  async sendMessage(text: string, includeAnalysis: boolean = false): Promise<void> {
    if (text.trim() === '' || this.isLoading) {
      return;
    }

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

    try {
      const contextMessages = this.buildContextMessages(includeAnalysis);
      const userMsg = new AiMessage();
      userMsg.role = 'user';
      userMsg.content = text.trim();
      contextMessages.push(userMsg);

      let fullContent = '';
      await this.aiService.sendChatMessage(
        contextMessages,
        (chunk: string) => {
          fullContent += chunk;
          aiMessage.content = fullContent;
          this.currentSession.messages = [...this.currentSession.messages];
          this.notifyChange();
        },
      );

      aiMessage.status = MessageStatus.SUCCESS;
    } catch (err) {
      aiMessage.content = '抱歉，我暂时无法回复你的问题。请检查网络连接后重试。';
      aiMessage.status = MessageStatus.FAILED;
    } finally {
      this.isLoading = false;
      this.isStreaming = false;
      this.currentSession.updateTime = Date.now();
      this.notifyChange();
    }
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
      await this.aiService.sendChatMessage(
        messages,
        (chunk: string) => {
          fullContent += chunk;
          aiMessage.content = fullContent;
          this.currentSession.messages = [...this.currentSession.messages];
          this.notifyChange();
        },
      );

      aiMessage.status = MessageStatus.SUCCESS;
    } catch (err) {
      aiMessage.content = this.generateLocalAnalysisText(analysisData);
      aiMessage.status = MessageStatus.SUCCESS;
    } finally {
      this.isLoading = false;
      this.isStreaming = false;
      this.currentSession.updateTime = Date.now();
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
      await this.aiService.sendChatMessage(
        messages,
        (chunk: string) => {
          fullContent += chunk;
          aiMessage.content = fullContent;
          this.currentSession.messages = [...this.currentSession.messages];
          this.notifyChange();
        },
      );

      aiMessage.status = MessageStatus.SUCCESS;
    } catch (err) {
      aiMessage.content = this.generateLocalErrorAnalysisText(errorQuestions);
      aiMessage.status = MessageStatus.SUCCESS;
    } finally {
      this.isLoading = false;
      this.isStreaming = false;
      this.currentSession.updateTime = Date.now();
      this.notifyChange();
    }
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

  private buildContextMessages(includeAnalysis: boolean): AiMessage[] {
    const sysMsg = new AiMessage();
    sysMsg.role = 'system';
    sysMsg.content = AiConstants.SYSTEM_PROMPT;

    const messages: AiMessage[] = [sysMsg];

    const recentMessages = this.currentSession.messages
      .filter((m) => m.role === MessageRole.USER || m.role === MessageRole.AI)
      .slice(-(AiConstants.MAX_HISTORY_MESSAGES));

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

  private buildAnalysisPrompt(data: LearningAnalysisData): string {
    let prompt = '请根据以下学习数据进行分析，给出详细的学习指导建议：\n\n';

    prompt += `【考试情况】共参加 ${data.totalExams} 次考试，平均分 ${data.avgScore} 分。\n`;

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
        prompt += `  - ${kp.name}: 掌握度 ${kp.mastery}%（${kp.correct}/${kp.total}）\n`;
      }
    }

    if (data.courseProgress.length > 0) {
      prompt += '\n【课程进度】\n';
      for (const cp of data.courseProgress) {
        prompt += `  - ${cp.courseName}: ${cp.progress}% (教师: ${cp.teacher})\n`;
      }
    }

    prompt += '\n请给出：\n1. 整体学习评估\n2. 薄弱环节分析\n3. 具体的学习建议\n4. 推荐的学习路径';

    return prompt;
  }

  private generateLocalAnalysisText(data: LearningAnalysisData): string {
    let text = '📊 **学习分析报告**\n\n';

    text += `**考试情况：** 共参加 ${data.totalExams} 次考试，平均分 ${data.avgScore} 分。\n\n`;

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
    }
    text += '3. 定期进行模拟考试，检验学习效果。\n';
    text += '4. 关注课程学习进度，按时完成线上培训任务。\n';

    return text;
  }

  getRecommendQuestions(): string[] {
    return AiConstants.RECOMMEND_QUESTIONS;
  }
}

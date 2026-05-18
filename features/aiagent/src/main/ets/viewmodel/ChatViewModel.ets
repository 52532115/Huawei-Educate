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
} from './ChatModels';
import { AiService } from '../service/AiService';
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

  constructor() {
    this.aiService = new AiService();
    this.sessionList = [];
    this.messageIdCounter = 0;
    this.isLoading = false;
    this.isStreaming = false;
    this.inputText = '';
    this.currentSession = this.createNewSession();
    this.sessionList.push(this.currentSession);
    this.initWelcomeMessage();
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
    this.currentSession.messages.push(welcomeMsg);
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
    this.sessionList.push(this.currentSession);
    this.initWelcomeMessage();
  }

  switchSession(sessionId: string): void {
    const target = this.sessionList.find((s) => s.id === sessionId);
    if (target) {
      this.currentSession = target;
    }
  }

  deleteSession(sessionId: string): void {
    const index = this.sessionList.findIndex((s) => s.id === sessionId);
    if (index !== -1) {
      this.sessionList.splice(index, 1);
      if (this.currentSession.id === sessionId) {
        if (this.sessionList.length > 0) {
          this.currentSession = this.sessionList[0];
        } else {
          this.newSession();
        }
      }
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
    this.currentSession.messages.push(userMessage);
    this.currentSession.updateTime = Date.now();

    if (this.currentSession.title === '新对话') {
      this.currentSession.title = text.trim().substring(0, 20);
    }

    const aiMessage = new ChatMessage(
      this.generateMessageId(),
      MessageRole.AI,
      '',
      MessageStatus.SENDING,
    );
    this.currentSession.messages.push(aiMessage);
    this.isLoading = true;
    this.isStreaming = true;

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
    this.currentSession.messages.push(userMessage);

    const aiMessage = new ChatMessage(
      this.generateMessageId(),
      MessageRole.ANALYSIS,
      '',
      MessageStatus.SENDING,
      analysisData,
    );
    this.currentSession.messages.push(aiMessage);
    this.isLoading = true;
    this.isStreaming = true;

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
    }
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

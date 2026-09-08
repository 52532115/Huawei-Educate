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

export enum ChatIntent {
  /** 用户想做题/练习：本地直接生成练习，不发 API 请求。 */
  PRACTICE = 'practice',
  /** 涉及学习数据：走 agent 循环，由模型决定调用哪些工具。 */
  ANALYTICS = 'analytics',
  /** 纯知识问答/闲聊：直接流式对话，不带工具（更快更省）。 */
  CHAT = 'chat',
}

const PRACTICE_KEYWORDS: string[] = [
  '练习', '刷题', '做题', '巩固', '训练题', '练一组', '练几道', '来几题', '出几道', '几道题', '练练',
];

const ANALYTICS_KEYWORDS: string[] = [
  '学习情况', '学习数据', '学习分析', '学习报告', '分析', '薄弱', '成绩', '考试',
  '错题', '归因', '课程', '学习计划', '学习建议', '复习计划', '掌握度',
];

/**
 * Cheap local intent routing. PRACTICE is checked first so sentences like
 * "针对错题出几道练习题" resolve to practice instead of analytics.
 */
export class IntentRouter {
  route(text: string): ChatIntent {
    if (this.containsAny(text, PRACTICE_KEYWORDS)) {
      return ChatIntent.PRACTICE;
    }
    if (this.containsAny(text, ANALYTICS_KEYWORDS)) {
      return ChatIntent.ANALYTICS;
    }
    return ChatIntent.CHAT;
  }

  private containsAny(text: string, keywords: string[]): boolean {
    for (const keyword of keywords) {
      if (text.indexOf(keyword) >= 0) {
        return true;
      }
    }
    return false;
  }
}

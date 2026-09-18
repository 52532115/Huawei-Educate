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
  /** 学科知识问答：先本地检索课程知识库，再带着资料流式作答，不进 agent 循环。 */
  KNOWLEDGE = 'knowledge',
  /** 纯闲聊：直接流式对话，不带工具、不检索（更快更省）。 */
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
 * Question forms that ask for subject knowledge rather than for the learner's
 * own data.
 *
 * Deliberately broad on the "asking" side: a false positive only costs one
 * local search, and an empty result degrades to ordinary chat, so precision
 * here is far cheaper than the recall it buys. The one thing these keywords
 * must never do is outrank ANALYTICS — "为什么我的成绩下降" has to reach the
 * tools, and it does, because 成绩 is matched first.
 */
const KNOWLEDGE_KEYWORDS: string[] = [
  '什么是', '是什么', '什么叫', '什么意思', '为什么', '为何', '怎么', '怎样', '如何',
  '区别', '原理', '解释', '讲解', '介绍一下', '讲讲', '说说', '含义', '定义', '概念',
  '作用', '特点', '举例', '证明', '推导', '公式',
];

/**
 * Cheap local intent routing. Order matters and is the whole design:
 *
 *   1. PRACTICE  — so "针对错题出几道练习题" is practice, not analytics.
 *   2. ANALYTICS — so "为什么我的成绩下降" reaches the tools, not the retriever.
 *   3. KNOWLEDGE — subject questions get grounded on the local course corpus.
 *   4. CHAT      — everything else stays a plain, tool-free, search-free reply.
 *
 * Only questions that clearly ask *about a subject* take the knowledge path; a
 * retrieval miss there falls back to plain chat, so a stray keyword can never
 * turn a casual message into a wrong citation.
 */
export class IntentRouter {
  route(text: string): ChatIntent {
    if (this.containsAny(text, PRACTICE_KEYWORDS)) {
      return ChatIntent.PRACTICE;
    }
    if (this.containsAny(text, ANALYTICS_KEYWORDS)) {
      return ChatIntent.ANALYTICS;
    }
    if (this.containsAny(text, KNOWLEDGE_KEYWORDS)) {
      return ChatIntent.KNOWLEDGE;
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

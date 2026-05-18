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

export class AiConstants {
  static readonly AI_API_URL: string = 'https://api.example.com/v1/chat/completions';
  static readonly AI_MODEL: string = 'ai-tutor-v1';
  static readonly MAX_HISTORY_MESSAGES: number = 20;
  static readonly REQUEST_TIMEOUT: number = 30000;
  static readonly MAX_RETRY_COUNT: number = 3;

  static readonly SYSTEM_PROMPT: string =
    `你是一个专业的教育助教，名叫"小智"。你的职责是：
1. 分析学生的学习数据（考试成绩、错题记录、课程进度等），给出个性化的学习建议。
2. 解答学生提出的学科知识问题，使用通俗易懂的语言。
3. 根据学生的学习情况，制定合理的学习计划。
4. 鼓励学生，给予正面的学习动力。

注意事项：
- 回答要简洁明了，避免过长。
- 如果学生问的问题不在你的知识范围内，诚实地告知并尝试给出相关建议。
- 学习建议要结合学生的实际数据，避免空泛的建议。
- 语气要亲切友好。`;

  static readonly WELCOME_MESSAGE: string =
    '你好！我是你的 AI 学习助教小智 🤖\n\n' +
    '我可以帮你：\n' +
    '📊 分析学习成绩，找出薄弱环节\n' +
    '📝 解答学习中的疑难问题\n' +
    '📅 制定个性化的学习计划\n\n' +
    '试试下面的快捷提问，或者直接输入你的问题吧！';

  static readonly RECOMMEND_QUESTIONS: string[] = [
    '帮我分析一下我的学习情况',
    '我最近考试中哪些知识点比较薄弱？',
    '帮我制定一个本周的学习计划',
    '如何提高考试成绩？',
    '推荐适合我当前水平的课程',
  ];
}

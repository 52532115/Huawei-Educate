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
  static readonly AI_API_URL: string = 'https://api.deepseek.com/v1/chat/completions';
  /**
   * The direct-path model. Ignored when a backend is configured, because there
   * the model is chosen server-side — which is the point of having one: swapping
   * model or provider must not require shipping a new build.
   *
   * The previous value, `deepseek-v4-flash`, is a retired model name. Requests
   * under it still succeed, but DeepSeek routes them to V4.1-Flash regardless;
   * `deepseek-flash` is the name the vendor documents today.
   */
  static readonly AI_MODEL: string = 'deepseek-flash';
  /**
   * The API key is NOT compiled into the app. It is entered by the user at
   * runtime (⚙️ on the chat page) and persisted by ApiKeyStore inside the
   * app sandbox only, so no build artifact ever contains a usable key.
   *
   * With a backend configured this key is not used at all: the vendor
   * credential lives on the server and the app presents only its own session
   * token. See AiBackend.
   */
  static readonly MAX_HISTORY_MESSAGES: number = 20;
  static readonly REQUEST_TIMEOUT: number = 60000;
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
    '你好！我是你的 AI 学习助教小智\n\n' +
    '我可以帮你：\n' +
    '📊 分析学习数据，找出薄弱环节\n' +
    '📝 分析错题本，诊断知识盲区\n' +
    '📅 解答学习中的疑难问题\n' +
    '🎯 制定个性化的学习计划\n\n' +
    '试试下面的快捷提问，或者直接输入你的问题吧！';

  static readonly ERROR_BOOK_ANALYSIS_PROMPT: string =
    `你是一个专业的教育助教，名叫"小智"，擅长分析学生的错题记录。你的职责是：
1. 根据学生的错题数据分析其知识薄弱点，找出错误模式和共性问题。
2. 针对学生的错误思路和学习笔记，给出个性化改进建议。
3. 按照知识点分类统计错题分布，指出最需要加强的领域。
4. 制定具体可执行的学习计划，包括时间分配和复习策略。

分析要点：
- 重点关注高频错误知识点，这些是优先攻克目标。
- 分析错误思路中反映出的深层问题（概念不清、方法错误、审题不仔细等）。
- 建议要具体、可量化，例如"每天做3道XX类型的题"而不仅是"多练习"。
- 结合不同知识点的难度和考试权重，给出合理的学习优先级。
- 用鼓励的语气，帮助学生建立信心。`;

  /**
   * System prompt for the knowledge path (a subject question answered from the
   * local course corpus).
   *
   * The grounding rules are the point of this prompt, not the tone: the model
   * is told to treat the retrieved block as its only source of *course*
   * claims, to cite it, and to say plainly when the corpus does not cover the
   * question. That mirrors the "no data, no fiction" rule the learning-data
   * tools already enforce — the difference is that here the missing thing is
   * course material rather than exam scores.
   */
  static readonly KNOWLEDGE_SYSTEM_PROMPT: string =
    `你是一个专业的教育助教，名叫"小智"。学生问的是学科知识问题。

回答规则：
1. 优先依据下方【检索到的课程资料】作答，凡是从资料中得出的结论，都用【出处】标注来源，出处写资料的标题路径（例如【数据结构 › 树 › 二叉搜索树】）。
2. 资料没有覆盖这个问题时，如实说明"课程资料里没有这部分内容"，然后可以给出通用解释，但要注明这是补充说明，不得编造课程出处，也不得把补充内容和资料混为一谈。
3. 资料只覆盖一部分时，先讲清楚资料里的部分，再说明还需要补充什么。
4. 讲解通俗易懂、分点陈述，必要时举一个具体例子；回答保持简洁，不要复述整段资料。
5. 如果学生的问题其实和他的学习数据有关（成绩、错题、进度等），提醒他可以让我去查他的学习数据。
`;

  static readonly RECOMMEND_QUESTIONS: string[] = [
    '帮我分析一下我的学习情况',
    '开始一组自适应练习',
    '帮我详细分析我的错题本',
    '帮我给错题本做智能归因',
    '我最近考试中哪些知识点比较薄弱？',
    '帮我制定一个本周的学习计划',
    '如何提高考试成绩？',
    '推荐适合我当前水平的课程',
  ];
}

// Offline tests for P1: IntentRouter routing, ContextCompressor summary,
// and PracticeSessionStore round-trip.
const fs = require('fs');
const path = require('path');
const ts = require('D:/devecostudio-windows-6.0.2.650/DevEco Studio/tools/hvigor/hvigor/node_modules/typescript');

const root = path.resolve(__dirname, '..');
const results = [];
let failures = 0;

function check(group, name, condition, actual, expected) {
  results.push({ group, name, status: condition ? 'PASS' : 'FAIL', actual, expected });
  if (!condition) failures++;
}

function loadArkTs(relativePath, prelude = '') {
  const filePath = path.join(root, relativePath);
  let source = fs.readFileSync(filePath, 'utf8');
  source = source.replace(/import[\s\S]*?from\s+['"][^'"]+['"];\s*/g, '');
  const compiled = ts.transpileModule(source, {
    compilerOptions: {
      module: ts.ModuleKind.CommonJS,
      target: ts.ScriptTarget.ES2020,
      esModuleInterop: true,
    },
  }).outputText;
  const module = { exports: {} };
  new Function('module', 'exports', `${prelude}\n${compiled}`)(module, module.exports);
  return module.exports;
}

// ---------- IntentRouter ----------
const routerMod = loadArkTs('features/aiagent/src/main/ets/service/IntentRouter.ets');
const router = new routerMod.IntentRouter();
// "什么是导数" now routes to KNOWLEDGE (a local course-corpus search before the
// reply) instead of CHAT. That is the intended change of the RAG work, not a
// regression: the question is a subject question, and an empty retrieval falls
// back to plain chat anyway. The data-driven cases below are unchanged, which is
// the property that actually matters — no analytics question lost its tools.
const routeCases = [
  ['帮我出几道极限题练练手', routerMod.ChatIntent.PRACTICE],
  ['针对我的错题出几道练习题', routerMod.ChatIntent.PRACTICE],
  ['开始一组自适应练习', routerMod.ChatIntent.PRACTICE],
  ['帮我分析一下我的学习情况', routerMod.ChatIntent.ANALYTICS],
  ['我最近考试中哪些知识点比较薄弱', routerMod.ChatIntent.ANALYTICS],
  ['帮我详细分析我的错题本', routerMod.ChatIntent.ANALYTICS],
  ['我的课程进度怎么样', routerMod.ChatIntent.ANALYTICS],
  ['什么是导数', routerMod.ChatIntent.KNOWLEDGE],
  ['你好呀', routerMod.ChatIntent.CHAT],
  ['如何提高考试成绩', routerMod.ChatIntent.ANALYTICS],
  ['三次握手的原理是什么', routerMod.ChatIntent.KNOWLEDGE],
  ['栈和队列的区别', routerMod.ChatIntent.KNOWLEDGE],
  ['今天有点累', routerMod.ChatIntent.CHAT],
];
for (const [text, expected] of routeCases) {
  const got = router.route(text);
  check('意图路由', `"${text}" -> ${expected}`, got === expected, got, expected);
}

// Ordering rule: PRACTICE and ANALYTICS must keep outranking KNOWLEDGE, or a
// stray knowledge keyword would steal a question that needs real learner data.
check('意图路由', '知识问句里出现「练习」仍归 PRACTICE',
  router.route('讲讲这道练习题涉及的知识点') === routerMod.ChatIntent.PRACTICE,
  router.route('讲讲这道练习题涉及的知识点'), routerMod.ChatIntent.PRACTICE);
check('意图路由', '「为什么我的成绩下降」仍归 ANALYTICS（数据词优先于问句词）',
  router.route('为什么我的成绩下降了') === routerMod.ChatIntent.ANALYTICS,
  router.route('为什么我的成绩下降了'), routerMod.ChatIntent.ANALYTICS);

// ---------- ContextCompressor ----------
const compressPrelude = `
const MessageRole = { USER: 'user', AI: 'ai', SYSTEM: 'system', ANALYSIS: 'analysis', STEP: 'step' };
`;
const compressorMod = loadArkTs(
  'features/aiagent/src/main/ets/service/ContextCompressor.ets',
  compressPrelude,
);
const compressor = new compressorMod.ContextCompressor();

const older = [
  { role: 'user', content: '什么是极限？' },
  { role: 'ai', content: '极限是……' },
  { role: 'user', content: '帮我分析一下我的学习情况' },
];
const summary = compressor.buildHistorySummary(older);
check('历史摘要', '包含用户问题要点', summary.indexOf('什么是极限？') >= 0 && summary.indexOf('帮我分析一下我的学习情况') >= 0, summary, 'contains both questions');
check('历史摘要', '不包含 AI 回复内容', summary.indexOf('极限是') < 0, summary, 'no AI content');
check('历史摘要', '空输入返回空串', compressor.buildHistorySummary([]) === '', compressor.buildHistorySummary([]), '');

// 超长截断
const longQuestion = '这是一个特别特别长的问题用来测试摘要截断'.repeat(10);
const longSummary = compressor.buildHistorySummary([{ role: 'user', content: longQuestion }]);
check('历史摘要', '超长问题被截断', longSummary.indexOf(longQuestion) < 0 && longSummary.indexOf('…') >= 0, longSummary, 'truncated');

// ---------- PracticeSessionStore ----------
const practicePrelude = `
const PracticeDifficulty = { BASIC: '基础', MEDIUM: '进阶', HARD: '挑战' };
class AdaptivePracticeQuestion {
  constructor(id, title, options, correctIndex, knowledgeTag, difficulty, source, explanation, recommendation) {
    Object.assign(this, { id, title, options, correctIndex, knowledgeTag, difficulty, source, explanation, recommendation });
    this.selectedIndex = -1; this.isSubmitted = false; this.syncedToErrorBook = false;
  }
}
class KnowledgePracticeProfile {
  constructor(tag, errorCount, mastery, priority, reason) { Object.assign(this, { tag, errorCount, mastery, priority, reason }); }
}
class AdaptivePracticeSession {
  constructor(id, questions, profiles) { Object.assign(this, { id, questions, profiles }); }
}
global.AppStorage = {
  data: new Map(),
  get(key) { return this.data.get(key); },
  setOrCreate(key, value) { this.data.set(key, value); }
};
`;
const storeMod = loadArkTs(
  'features/aiagent/src/main/ets/service/PracticeSessionStore.ets',
  practicePrelude,
);
const store = new storeMod.PracticeSessionStore();

// Build session with plain constructors instead
function buildSession() {
  const PracticeQuestion = (function () {
    return function Q(id, title, options, correctIndex, knowledgeTag, difficulty, source, explanation, recommendation) {
      return { id, title, options, correctIndex, knowledgeTag, difficulty, source, explanation, recommendation };
    };
  })();
  const Profile = (function () {
    return function P(tag, errorCount, mastery, priority, reason) { return { tag, errorCount, mastery, priority, reason }; };
  })();
  return {
    id: 'practice_test_1',
    questions: [
      PracticeQuestion('q1', '极限题', ['A', 'B'], 0, '函数与极限', '基础', 'src', '解析', '建议'),
      PracticeQuestion('q2', '积分题', ['A', 'B'], 1, '不定积分', '进阶', 'src', '解析', '建议'),
    ],
    profiles: [
      Profile('函数与极限', 2, 55, 90, '错题集中出现'),
      Profile('不定积分', 1, 68, 70, '课程进度低'),
    ],
  };
}

store.savePendingSession(buildSession());
const loaded = store.loadPendingSession();
check('练习交接', '会话往返保存/加载', loaded !== null, loaded, 'session');
if (loaded) {
  check('练习交接', '题目数量正确', loaded.questions.length === 2, loaded.questions.length, 2);
  check('练习交接', '题目字段完整', loaded.questions[0].title === '极限题' && loaded.questions[0].options.length === 2 && loaded.questions[0].correctIndex === 0, JSON.stringify(loaded.questions[0]), 'q1 intact');
  check('练习交接', '难度枚举恢复', loaded.questions[1].difficulty === '进阶', loaded.questions[1].difficulty, '进阶');
  check('练习交接', 'profile 恢复', loaded.profiles.length === 2 && loaded.profiles[0].tag === '函数与极限', JSON.stringify(loaded.profiles), 'profiles intact');
}
check('练习交接', '一次性消费(再取为 null)', store.loadPendingSession() === null, store.loadPendingSession(), 'null');
check('练习交接', '无数据返回 null', store.loadPendingSession() === null, store.loadPendingSession(), 'null');
// 损坏数据
global.AppStorage.setOrCreate('PendingPracticeSession', 'not-json');
check('练习交接', '损坏数据返回 null', store.loadPendingSession() === null, store.loadPendingSession(), 'null');

fs.writeFileSync(path.join(__dirname, 'ai_agent_p1_test_result.json'), JSON.stringify(results, null, 2));
console.log(`${results.length - failures}/${results.length} passed`);
process.exit(failures > 0 ? 1 : 0);

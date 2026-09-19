// Offline tests for P8: questions written by the model from retrieved lecture
// passages (RAG + LLM).
//
// Groups:
//   A  prompt contract          — what the model is told, asserted on the text
//   B  response parsing         — the measured reply, plus the ways a reply can
//                                 be malformed and still be survivable
//   C  material sufficiency     — when there is nothing worth asking about
//   D  the pool                 — caching, invalidation, eviction, round-trip
//   E  service integration      — where synthesized questions land in a session
//   F  static guards            — the invariants that must not drift silently
//
// The fixture in group B is the *verbatim* body of a real reply from the
// configured backend (see _probe_question_gen.log). Parsing the measured shape
// rather than an invented one is the point: the first probe showed the model
// ignores `sourceIndex` entirely, which is why provenance is the set of
// passages a question was written from and not a per-question index.
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

function transpileArkTs(relativePath) {
  const filePath = path.join(root, relativePath);
  const source = fs.readFileSync(filePath, 'utf8');
  const stripped = source.replace(/import[\s\S]*?from\s+['"][^'"]+['"];\s*/g, '');
  return ts.transpileModule(stripped, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020, esModuleInterop: true },
  }).outputText;
}

function loadArkTs(relativePath, prelude = '') {
  const compiled = transpileArkTs(relativePath);
  const module = { exports: {} };
  new Function('module', 'exports', `${prelude}\n${compiled}`)(module, module.exports);
  return module.exports;
}

// 2025-01-01T00:00:00Z — injected everywhere so nothing depends on the wall clock.
const NOW = 1735689600000;
const DAY = 86400000;
const SERVICE_DIR = 'features/aiagent/src/main/ets/service/';

// Shared in-memory AppStorage + fileIo, so pool instances share state. Both have
// to be globals: a compiled module runs inside `new Function` and only sees the
// global scope.
const fileMap = new Map();
let lastOpenedPath = '';
let openSyncShouldThrow = false;
global.AppStorage = {
  data: new Map(),
  get(key) { return this.data.get(key); },
  setOrCreate(key, value) { this.data.set(key, value); },
};
global.fileIo = {
  readTextSync(p) {
    if (!fileMap.has(p)) { throw new Error('ENOENT'); }
    return fileMap.get(p);
  },
  openSync(p) {
    if (openSyncShouldThrow) { throw new Error('disk full'); }
    lastOpenedPath = p;
    return { fd: 1 };
  },
  writeSync(fd, text) { fileMap.set(lastOpenedPath, text); },
  closeSync() {},
  unlinkSync(p) { fileMap.delete(p); },
};
const FILES_DIR = '/tmp/p8test';
function publishFilesDir(enabled) {
  if (enabled) {
    global.AppStorage.setOrCreate('filesDir', FILES_DIR);
  } else {
    global.AppStorage.data.delete('filesDir');
  }
}
publishFilesDir(true);

// ---------- model stubs ----------
const modelsPrelude = `
const PracticeDifficulty = { BASIC: '基础', MEDIUM: '进阶', HARD: '挑战' };
class AdaptivePracticeQuestion {
  constructor(id, title, options, correctIndex, knowledgeTag, difficulty, source, explanation, recommendation,
    sourceRecordId = '') {
    Object.assign(this, { id, title, options, correctIndex, knowledgeTag, difficulty, source, explanation,
      recommendation, selectedIndex: -1, isSubmitted: false, syncedToErrorBook: false, sourceRecordId,
      masteryRecorded: false, citation: '' });
  }
}
class KnowledgePracticeProfile {
  constructor(tag, errorCount, mastery, priority, reason) {
    Object.assign(this, { tag, errorCount, mastery, priority, reason, attempts: 0, correct: 0, lastPracticeTime: 0 });
  }
}
class ErrorBookPracticeCandidate {
  constructor() {
    Object.assign(this, { recordId: '', title: '', normalizedTitle: '', options: [], correctIndex: -1,
      knowledgeTag: '', userNote: '', mistakeReason: '', analysis: '', createTime: 0, lastActivityTime: 0,
      repeatCount: 1, isDemo: false, score: 0, difficulty: PracticeDifficulty.BASIC });
  }
}
class ErrorQuestionItem {
  constructor(title, category, id = '') {
    this.id = id; this.title = title; this.category = category;
    this.options = []; this.correctIndex = -1; this.userIndex = -1;
    this.correctLabel = ''; this.userLabel = ''; this.userNote = '';
    this.mistakeReason = ''; this.createTime = 0; this.analysis = '';
    this.wrongCount = 0; this.lastReviewTime = 0;
  }
}
class AdaptivePracticeSession {
  constructor(id, questions, profiles) {
    Object.assign(this, { id, questions, profiles, summary: { totalCount: 0, correctCount: 0, score: 0,
      weakTags: [], masteredTags: [], advice: '', generatedAt: 0, historyAttempts: 0, historyCorrect: 0,
      historyTags: 0, historyWeakTags: [] } });
  }
}
class AiMessage {
  constructor() { this.role = ''; this.content = ''; }
}
global.AdaptivePracticeQuestion = AdaptivePracticeQuestion;
global.AdaptivePracticeSession = AdaptivePracticeSession;
global.PracticeDifficulty = PracticeDifficulty;
global.KnowledgePracticeProfile = KnowledgePracticeProfile;
`;

// The real source module: the synthesizer reuses its normalization + hash, and
// this suite asserts that reuse rather than a copy.
const sourceMod = loadArkTs(`${SERVICE_DIR}ErrorBookPracticeSource.ets`, modelsPrelude);
global.__sourceModule = sourceMod;
const { isCorruptedText, normalizeQuestionTitle } = sourceMod;
// A prelude's lexical scope is invisible out here, so the model classes it
// defines reach the test through the global it published.
const { PracticeDifficulty, AdaptivePracticeQuestion, KnowledgePracticeProfile } = global;

const synthMod = loadArkTs(`${SERVICE_DIR}PracticeQuestionSynthesizer.ets`, `
${modelsPrelude}
const { isCorruptedText, normalizeKnowledgeTag, normalizeQuestionTitle, stableTextHash } = global.__sourceModule;
`);
const {
  PracticeQuestionSynthesizer, SynthesisPassage, SynthesisRequest,
  SOURCE_AI_GENERATED, SYNTHESIS_CONTRACT_VERSION, SYNTHESIS_QUESTION_COUNT,
} = synthMod;
const synthesizer = new PracticeQuestionSynthesizer();
// Published before the pool loads: the pool's prelude reads the contract
// version and the batch size from here rather than restating them.
global.__synthModule = synthMod;

// ---------- fixtures ----------

const PASSAGES = [
  new SynthesisPassage('数据结构 › 树 › 二叉搜索树', '二叉搜索树',
    '二叉搜索树的性质是：对任意结点，其左子树上所有结点的值都小于它，右子树上所有结点的值都大于它。'
    + '因此查找时每次比较都能排除一半子树，平均时间复杂度为 O(log n)。当插入序列已经有序时，'
    + '树会退化成一条链，此时查找退化为 O(n)，这也是平衡树（AVL、红黑树）存在的理由。'),
  new SynthesisPassage('计算机网络 › 传输层 › TCP 三次握手', 'TCP',
    'TCP 建立连接需要三次握手：客户端发送 SYN，服务端回复 SYN+ACK，客户端再发送 ACK。'
    + '第三次握手不是为了确认服务端的接收能力，而是为了让服务端确认客户端确实收到了自己的 SYN+ACK。'),
];

const REQUEST = new SynthesisRequest('二叉搜索树', PracticeDifficulty.BASIC, PASSAGES, 3);

// Verbatim from a real backend reply — see _probe_question_gen.log.
const REAL_REPLY = `[
  {
    "title": "在二叉搜索树中查找一个值时，为什么每次比较都能排除一半子树？",
    "options": [
      "因为对任意结点，其左子树所有结点的值都小于它，右子树上所有结点的值都大于它",
      "因为树的高度被强制维持在 log n 层",
      "因为每次查找都会把树重新平衡一次",
      "因为二叉搜索树的所有结点值都是互不相同的随机数"
    ],
    "correctIndex": 0,
    "explanation": "正是左小右大的有序性质使得比较后可以确定目标只可能落在其中一侧子树，从而排除另一半。",
    "recommendation": "练习时给定一组数，手动画出二叉搜索树并模拟查找路径。"
  },
  {
    "title": "将一组已经按升序排好的数据依次插入二叉搜索树，会出现什么后果？",
    "options": [
      "树会退化成一条链，查找时间复杂度退化为 O(n)",
      "树的查找复杂度仍保持平均 O(log n)",
      "树会自动变成平衡树，性能不受影响",
      "插入顺序不影响树的结构，结果与随机插入相同"
    ],
    "correctIndex": 0,
    "explanation": "有序插入会让每个新结点都落在同一侧，树退化成链，查找也因此退化为 O(n)。",
    "recommendation": "分别用有序序列和随机序列插入同一组数据，对比两种情况下的树高。"
  },
  {
    "title": "既然有序插入会让二叉搜索树退化成链，为什么还需要平衡树（AVL、红黑树）？",
    "options": [
      "为了在动态插入删除过程中维持较矮的树高，避免查找退化为 O(n)",
      "为了把查找时间复杂度降到比 O(log n) 更低",
      "为了允许左子树结点的值大于根结点",
      "为了让树退化成链时仍能保持 O(log n) 查找"
    ],
    "correctIndex": 0,
    "explanation": "平衡树的意义在于通过旋转等机制控制树高，使其接近 log n，从而避免退化带来的 O(n) 查找。",
    "recommendation": "复习 AVL 树和红黑树的旋转操作，思考它们分别在什么场景下维持树高。"
  }
]`;

/** One question object with every field valid, for mutation in single-field tests. */
function validItem(overrides = {}) {
  return Object.assign({
    title: '这是一个足够长的测试题干吗？',
    options: ['选项甲', '选项乙', '选项丙', '选项丁'],
    correctIndex: 1,
    explanation: '因为选项乙才是对的。',
    recommendation: '复习一下。',
  }, overrides);
}

function replyOf(items) {
  return JSON.stringify(items);
}

// ================= A. prompt contract =================

const prompt = synthesizer.buildPrompt(REQUEST);
check('A 提示词', '系统提示把语料约束写成硬规则（只用片段、不得引入片段外知识）',
  prompt.system.indexOf('只能依据【讲义片段】出题') >= 0 &&
  prompt.system.indexOf('不得引入片段之外的知识') >= 0,
  { hasGroundingRule: prompt.system.indexOf('只能依据【讲义片段】出题') >= 0 },
  { hasGroundingRule: true });

check('A 提示词', '系统提示写明输出契约：裸 JSON 数组、无代码块',
  prompt.system.indexOf('只返回一个 JSON 数组') >= 0 &&
  prompt.system.indexOf('不要 Markdown 代码块') >= 0,
  { json: prompt.system.indexOf('只返回一个 JSON 数组') >= 0 },
  { json: true });

check('A 提示词', 'correctIndex 明确要求 0 起始，避免 1-based 误判',
  prompt.system.indexOf('"correctIndex"') >= 0 && prompt.system.indexOf('从 0 开始') >= 0,
  { hasField: prompt.system.indexOf('"correctIndex"') >= 0, zeroBased: prompt.system.indexOf('从 0 开始') >= 0 },
  { hasField: true, zeroBased: true });

check('A 提示词', '用户消息带知识点、难度、片段编号出处与正文',
  prompt.user.indexOf('知识点：二叉搜索树') >= 0 &&
  prompt.user.indexOf('难度：基础') >= 0 &&
  prompt.user.indexOf('片段 0（数据结构 › 树 › 二叉搜索树）') >= 0 &&
  prompt.user.indexOf('片段 1（计算机网络 › 传输层 › TCP 三次握手）') >= 0 &&
  prompt.user.indexOf('退化成一条链') >= 0,
  {
    tag: prompt.user.indexOf('知识点：二叉搜索树') >= 0,
    difficulty: prompt.user.indexOf('难度：基础') >= 0,
    fragment0: prompt.user.indexOf('片段 0（数据结构 › 树 › 二叉搜索树）') >= 0,
    body: prompt.user.indexOf('退化成一条链') >= 0,
  },
  { tag: true, difficulty: true, fragment0: true, body: true });

check('A 提示词', '题量写在用户消息末尾，随请求变化',
  prompt.user.endsWith('请出 3 道单选题。') &&
  synthesizer.buildPrompt(new SynthesisRequest('二叉树', PracticeDifficulty.HARD, PASSAGES, 1))
    .user.endsWith('请出 1 道单选题。'),
  prompt.user.slice(-12), '请出 3 道单选题。');

check('A 提示词', '片段缺出处时仍编号，不产生空括号',
  synthesizer.buildPrompt(new SynthesisRequest('二叉树', PracticeDifficulty.BASIC,
    [new SynthesisPassage('', '二叉树', '二叉树每个结点最多有两个子结点，分别称为左子结点和右子结点，这是它的基本结构性质。')], 1))
    .user.indexOf('片段 0\n') >= 0,
  'numbered without a citation', 'numbered without a citation');

// ================= B. response parsing =================

const realParsed = synthesizer.parseResponse(REAL_REPLY, REQUEST);
check('B 解析', '实测的真实回复逐题通过解析',
  realParsed.length === 3,
  realParsed.map((q) => q.title.slice(0, 12)),
  '3 questions');

check('B 解析', '选项、答案、解析、出处、来源、难度、知识点逐项落位',
  realParsed[0].options.length === 4 &&
  realParsed[0].correctIndex === 0 &&
  realParsed[0].explanation.length > 0 &&
  realParsed[0].source === SOURCE_AI_GENERATED &&
  realParsed[0].difficulty === PracticeDifficulty.BASIC &&
  realParsed[0].knowledgeTag === '二叉搜索树' &&
  realParsed[0].citation === '数据结构 › 树 › 二叉搜索树；计算机网络 › 传输层 › TCP 三次握手',
  {
    options: realParsed[0].options.length, correctIndex: realParsed[0].correctIndex,
    source: realParsed[0].source, citation: realParsed[0].citation,
  },
  { options: 4, correctIndex: 0, source: 'ai_generated', citation: '数据结构 › 树 › 二叉搜索树；计算机网络 › 传输层 › TCP 三次握手' });

const again = synthesizer.parseResponse(REAL_REPLY, REQUEST);
check('B 解析', 'id 由知识点与题干派生，确定性且带 q_gen_ 前缀',
  realParsed[0].id === again[0].id && realParsed[0].id.startsWith('q_gen_') &&
  realParsed[0].id !== realParsed[1].id,
  { first: realParsed[0].id, stable: realParsed[0].id === again[0].id, distinct: realParsed[0].id !== realParsed[1].id },
  { first: realParsed[0].id, stable: true, distinct: true });

check('B 解析', '同一题干在不同批次里得到同一个 id（缓存去重的前提）',
  synthesizer.parseResponse(replyOf([validItem()]), REQUEST)[0].id ===
  synthesizer.parseResponse(replyOf([validItem()]), REQUEST)[0].id,
  synthesizer.parseResponse(replyOf([validItem()]), REQUEST)[0].id, 'stable across calls');

check('B 解析', 'Markdown 代码块包裹也能解析',
  synthesizer.parseResponse('```json\n' + replyOf([validItem()]) + '\n```', REQUEST).length === 1 &&
  synthesizer.parseResponse('```\n' + replyOf([validItem()]) + '\n```', REQUEST).length === 1,
  'fenced', 1);

check('B 解析', '前后有解释文字、或包在对象里，都能取到数组',
  synthesizer.parseResponse('好的，这是题目：\n' + replyOf([validItem()]) + '\n希望有帮助！', REQUEST).length === 1 &&
  synthesizer.parseResponse('{"questions":' + replyOf([validItem()]) + '}', REQUEST).length === 1,
  { prose: 'ok', wrapped: 'ok' }, { prose: 1, wrapped: 1 });

check('B 解析', '空串、纯文本、空数组、非数组对象一律返回空批次',
  synthesizer.parseResponse('', REQUEST).length === 0 &&
  synthesizer.parseResponse('抱歉，我无法完成。', REQUEST).length === 0 &&
  synthesizer.parseResponse('[]', REQUEST).length === 0 &&
  synthesizer.parseResponse('{"error":"x"}', REQUEST).length === 0,
  'all empty', 0);

check('B 解析', '选项少于 3 个的题被丢弃，同批其他题保留',
  synthesizer.parseResponse(replyOf([
    validItem({ options: ['甲', '乙'] }),
    validItem({ title: '这一题有四个选项应该被保留下来' }),
  ]), REQUEST).length === 1,
  synthesizer.parseResponse(replyOf([
    validItem({ options: ['甲', '乙'] }),
    validItem({ title: '这一题有四个选项应该被保留下来' }),
  ]), REQUEST).map((q) => q.title),
  1);

check('B 解析', 'correctIndex 越界（4 个选项给 4）被丢弃',
  synthesizer.parseResponse(replyOf([validItem({ correctIndex: 4 })]), REQUEST).length === 0,
  'out of range rejected', 0);

check('B 解析', 'correctIndex 为单字母时按 A=0 换算',
  synthesizer.parseResponse(replyOf([validItem({ correctIndex: 'B' })]), REQUEST)[0].correctIndex === 1 &&
  synthesizer.parseResponse(replyOf([validItem({ correctIndex: 'd' })]), REQUEST)[0].correctIndex === 3,
  synthesizer.parseResponse(replyOf([validItem({ correctIndex: 'B' })]), REQUEST)[0].correctIndex,
  1);

check('B 解析', '数字字符串（"1"）被拒绝：0-based 与 1-based 无法区分',
  synthesizer.parseResponse(replyOf([validItem({ correctIndex: '1' })]), REQUEST).length === 0,
  'ambiguous rejected', 0);

check('B 解析', '题干乱码或过短的题被丢弃',
  synthesizer.parseResponse(replyOf([validItem({ title: '������' })]), REQUEST).length === 0 &&
  synthesizer.parseResponse(replyOf([validItem({ title: '短' })]), REQUEST).length === 0,
  { corrupted: true, tooShort: true }, { corrupted: 0, tooShort: 0 });

check('B 解析', '选项或解析出现乱码时丢弃该题（不给学习者半成品）',
  synthesizer.parseResponse(replyOf([validItem({ options: ['正常选项', '��������', '选项丙', '选项丁'] })]), REQUEST).length === 0 &&
  synthesizer.parseResponse(replyOf([validItem({ explanation: '' })]), REQUEST).length === 0,
  { option: 0, explanation: 0 }, { option: 0, explanation: 0 });

check('B 解析', '解析为空则整题丢弃（无解析的选择题不构成一道题）',
  synthesizer.parseResponse(replyOf([validItem({ explanation: '   ' })]), REQUEST).length === 0,
  'blank explanation rejected', 0);

check('B 解析', '建议为空不影响采纳，回落到默认建议',
  synthesizer.parseResponse(replyOf([validItem({ recommendation: '' })]), REQUEST)[0].recommendation.length > 0,
  'default applied', 'non-empty');

check('B 解析', '同批重复题干去重，只保留先出现的',
  synthesizer.parseResponse(replyOf([validItem(), validItem()]), REQUEST).length === 1,
  synthesizer.parseResponse(replyOf([validItem(), validItem()]), REQUEST).length, 1);

check('B 解析', '出处最多两段且去重',
  synthesizer.parseResponse(replyOf([validItem()]),
    new SynthesisRequest('二叉树', PracticeDifficulty.BASIC, [
      new SynthesisPassage('A', 'x', '甲'.repeat(40)),
      new SynthesisPassage('A', 'x', '乙'.repeat(40)),
      new SynthesisPassage('B', 'x', '丙'.repeat(40)),
      new SynthesisPassage('C', 'x', '丁'.repeat(40)),
    ], 1))[0].citation === 'A；B',
  'A；B', 'A；B');

check('B 解析', '知识点 tag 走既有归一化（空 tag → 未分类）',
  synthesizer.parseResponse(replyOf([validItem()]),
    new SynthesisRequest('   ', PracticeDifficulty.BASIC, PASSAGES, 1))[0].knowledgeTag === '未分类',
  '未分类', '未分类');

check('B 解析', '非对象元素被跳过，不影响同批其他题',
  synthesizer.parseResponse('[' + 'null, 42, "文本", ' + replyOf([validItem()]).slice(1), REQUEST).length === 1,
  'junk entries skipped', 1);

// ================= C. material sufficiency =================

check('C 语料', '合计正文不足 80 字时判定材料不足（检索必然有返回，长度才是信号）',
  synthesizer.isMaterialSufficient([new SynthesisPassage('A', 'x', '短'.repeat(30))]) === false &&
  synthesizer.isMaterialSufficient([new SynthesisPassage('A', 'x', '足'.repeat(90))]) === true,
  { short: false, long: true }, { short: false, long: true });

check('C 语料', '单段不足 20 字的片段不计入合计',
  synthesizer.usablePassageChars([new SynthesisPassage('A', 'x', '短'.repeat(19))]) === 0 &&
  synthesizer.usablePassageChars([new SynthesisPassage('A', 'x', '合'.repeat(20))]) === 20,
  synthesizer.usablePassageChars([new SynthesisPassage('A', 'x', '短'.repeat(19))]), 0);

check('C 语料', '乱码片段不计入合计（不拿乱码去出题）',
  synthesizer.usablePassageChars([new SynthesisPassage('A', 'x', '���'.repeat(60))]) === 0,
  'corrupted excluded', 0);

check('C 语料', '空片段列表判定为不足',
  synthesizer.isMaterialSufficient([]) === false, false, false);

check('C 语料', '出处拼接跳过空值与乱码',
  synthesizer.citationOf([new SynthesisPassage('', 'x', '正文'.repeat(14)),
    new SynthesisPassage('���', 'x', '正文'.repeat(14)),
    new SynthesisPassage('数据结构 › 树', 'x', '正文'.repeat(14))]) === '数据结构 › 树',
  '数据结构 › 树', '数据结构 › 树');

// ================= D. the pool =================

const poolMod = loadArkTs(`${SERVICE_DIR}GeneratedQuestionPool.ets`, `
${modelsPrelude}
const SOURCE_AI_GENERATED = 'ai_generated';
const SYNTHESIS_CONTRACT_VERSION = ${SYNTHESIS_CONTRACT_VERSION};
const { SYNTHESIS_QUESTION_COUNT } = global.__synthModule;
`);
const { GeneratedQuestionPool, MAX_QUESTIONS_PER_TAG, MAX_TAGS } = poolMod;

function freshPool() {
  fileMap.clear();
  global.AppStorage.data.delete('filesDir');
  const pool = new GeneratedQuestionPool();
  global.AppStorage.setOrCreate('filesDir', FILES_DIR);
  return pool;
}

/** A synthesized-looking question with a caller-chosen id and tag. */
function generatedQuestion(id, tag, title = `题目 ${id}`) {
  const question = new AdaptivePracticeQuestion(
    id, title, ['甲', '乙', '丙', '丁'], 0, tag, PracticeDifficulty.BASIC,
    SOURCE_AI_GENERATED, '解析', '建议',
  );
  question.citation = '数据结构 › 树';
  return question;
}

const pool = freshPool();
check('D 缓存', '入池后按知识点可读，计数与总量一致',
  pool.add('二叉树', [generatedQuestion('q1', '二叉树'), generatedQuestion('q2', '二叉树')]) === 2 &&
  pool.countForTag('二叉树') === 2 && pool.size() === 2 && pool.tagCount() === 1,
  { size: pool.size(), tags: pool.tagCount() }, { size: 2, tags: 1 });

check('D 缓存', '重复入池同一 id 不增加（id 由题干派生，二次生成应折叠）',
  pool.add('二叉树', [generatedQuestion('q1', '二叉树')]) === 0 && pool.size() === 2,
  pool.size(), 2);

check('D 缓存', '取题遵守排除列表（与其余各层的换一组语义一致）',
  pool.getForTag('二叉树', ['q1'], 5).map((q) => q.id).join('|') === 'q2',
  pool.getForTag('二叉树', ['q1'], 5).map((q) => q.id),
  ['q2']);

check('D 缓存', '取出的题是副本：改会话状态不会污染缓存',
  (function () {
    const taken = pool.getForTag('二叉树', [], 1)[0];
    taken.selectedIndex = 3;
    taken.isSubmitted = true;
    const reread = pool.getForTag('二叉树', [], 1)[0];
    return reread.selectedIndex === -1 && reread.isSubmitted === false;
  })(),
  'copy is clean', 'copy is clean');

check('D 缓存', '出处的字段随题一起缓存与返回',
  pool.getForTag('二叉树', [], 1)[0].citation === '数据结构 › 树',
  pool.getForTag('二叉树', [], 1)[0].citation, '数据结构 › 树');

// The caps are spelled out here instead of being read from the module. An
// assertion whose expected value comes from the very constant under test stays
// green when that constant changes — precisely what it exists to catch. The
// two are cross-checked below so they cannot drift apart either.
const TAG_CAP = 8;
const TAG_COUNT_CAP = 24;

check('D 缓存', '源码里的上限与断言写死的一致（不同步会静默放宽）',
  MAX_QUESTIONS_PER_TAG === TAG_CAP && MAX_TAGS === TAG_COUNT_CAP,
  { perTag: MAX_QUESTIONS_PER_TAG, tags: MAX_TAGS },
  { perTag: TAG_CAP, tags: TAG_COUNT_CAP });

check('D 缓存', `每个知识点上限 ${TAG_CAP} 道，超出时淘汰最早的`,
  (function () {
    const local = freshPool();
    const batch = [];
    for (let i = 0; i < TAG_CAP + 2; i += 1) { batch.push(generatedQuestion(`p${i}`, '操作系统')); }
    local.add('操作系统', batch);
    const kept = local.getForTag('操作系统', [], 99).map((q) => q.id);
    return local.countForTag('操作系统') === TAG_CAP &&
      kept[0] === 'p2' && kept[kept.length - 1] === 'p9';
  })(),
  'oldest eight evicted', 'keep p2..p9 of 10');

check('D 缓存', `知识点数量上限 ${TAG_COUNT_CAP}，超出时淘汰最久未写入的整组`,
  (function () {
    const local = freshPool();
    for (let i = 0; i < TAG_COUNT_CAP + 1; i += 1) {
      local.add(`知识点${i}`, [generatedQuestion(`t${i}`, `知识点${i}`)]);
    }
    return local.tagCount() === TAG_COUNT_CAP && local.countForTag('知识点0') === 0 &&
      local.countForTag(`知识点${TAG_COUNT_CAP}`) === 1;
  })(),
  `tags capped at ${TAG_COUNT_CAP}`, '知识点0 dropped');

check('D 缓存', '语料指纹变化时整池作废',
  (function () {
    const local = freshPool();
    local.setCorpusFingerprint('corpus-a');
    local.add('二叉树', [generatedQuestion('q1', '二叉树')]);
    local.setCorpusFingerprint('corpus-a');
    const survived = local.size();
    local.setCorpusFingerprint('corpus-b');
    return survived === 1 && local.size() === 0 && local.getCorpusFingerprint() === 'corpus-b';
  })(),
  'dropped on change', 'dropped on change');

check('D 缓存', '空指纹视为未知，不清空（否则每次冷启动首帧都会清缓存）',
  (function () {
    const local = freshPool();
    local.setCorpusFingerprint('corpus-a');
    local.add('二叉树', [generatedQuestion('q1', '二叉树')]);
    local.setCorpusFingerprint('');
    return local.size() === 1 && local.getCorpusFingerprint() === 'corpus-a';
  })(),
  'kept', 'kept');

check('D 缓存', '落盘后可被新实例读回，指纹与题目都在',
  (function () {
    const writer = freshPool();
    writer.setCorpusFingerprint('corpus-x');
    writer.add('二叉树', [generatedQuestion('q1', '二叉树', '落盘的题目')]);
    const reader = new GeneratedQuestionPool();
    return reader.getCorpusFingerprint() === 'corpus-x' && reader.countForTag('二叉树') === 1 &&
      reader.getForTag('二叉树', [], 1)[0].title === '落盘的题目' &&
      reader.getForTag('二叉树', [], 1)[0].citation === '数据结构 › 树';
  })(),
  'round-trip ok', 'round-trip ok');

check('D 缓存', '写盘成功计入统计；无 filesDir 时既不写也不失败',
  (function () {
    const withDir = freshPool();
    withDir.add('二叉树', [generatedQuestion('q1', '二叉树')]);
    const statsWithDir = withDir.getSaveStats().join('|');
    publishFilesDir(false);
    const withoutDir = new GeneratedQuestionPool();
    withoutDir.add('二叉树', [generatedQuestion('q2', '二叉树')]);
    const statsWithoutDir = withoutDir.getSaveStats().join('|');
    publishFilesDir(true);
    return statsWithDir === '1|1' && statsWithoutDir === '0|0' && withoutDir.size() === 1;
  })(),
  'with dir 1|1, without 0|0', 'with dir 1|1, without 0|0');

check('D 缓存', '写盘抛异常时静默降级为纯内存',
  (function () {
    const local = freshPool();
    openSyncShouldThrow = true;
    const added = local.add('二叉树', [generatedQuestion('q1', '二叉树')]);
    openSyncShouldThrow = false;
    return added === 1 && local.size() === 1 && local.getSaveStats().join('|') === '1|0';
  })(),
  'memory only', '1|0');

check('D 缓存', '文件里的契约版本不匹配时整份丢弃',
  (function () {
    const path0 = `${FILES_DIR}/generatedQuestions.json`;
    fileMap.set(path0, JSON.stringify({
      version: SYNTHESIS_CONTRACT_VERSION + 1, fingerprint: 'corpus-x', nextSeq: 1,
      tags: [{ tag: '二叉树', seq: 1, questions: [generatedQuestion('q1', '二叉树')] }],
    }));
    const reader = new GeneratedQuestionPool();
    return reader.countForTag('二叉树') === 0 && reader.getCorpusFingerprint() === '';
  })(),
  'version mismatch dropped', 'version mismatch dropped');

check('D 缓存', '文件损坏或字段缺失时逐项丢弃，不整份信任',
  (function () {
    const path0 = `${FILES_DIR}/generatedQuestions.json`;
    fileMap.set(path0, '{ not json');
    const broken = new GeneratedQuestionPool();
    const brokenOk = broken.size() === 0;

    fileMap.set(path0, JSON.stringify({
      version: SYNTHESIS_CONTRACT_VERSION, fingerprint: 'corpus-x', nextSeq: 2,
      tags: [
        { tag: '二叉树', seq: 1, questions: [generatedQuestion('q1', '二叉树')] },
        { tag: '', seq: 2, questions: [] },
        // Everything valid except the stem. The record decoders layer several
        // checks, so an entry that fails only the last one is what tells the
        // mutation apart: with several faults, removing one guard changes
        // nothing and the assertion looks unfalsifiable when it is not.
        { tag: '操作系统', seq: 3, questions: [{ id: 'bad', title: '', options: ['甲', '乙'], correctIndex: 0 }] },
      ],
    }));
    const partial = new GeneratedQuestionPool();
    return brokenOk && partial.tagCount() === 2 && partial.countForTag('二叉树') === 1 &&
      partial.getForTag('操作系统', [], 5).length === 0;
  })(),
  'partial load', 'partial load');

// ================= E. service integration =================

const aiState = { calls: 0, prompts: [], reply: REAL_REPLY, fail: false };
const knowledgeState = { hits: [], queries: [], fingerprint: '' };

/**
 * The synthesis path's two collaborators, defined out here rather than inside a
 * prelude so the test hands the service the very instances it counts calls on.
 * Both record what they were asked — "did it ask at all" is the question these
 * checks care about, not "did it avoid crashing".
 */
class StubAiService {
  getMode() { return 'stub'; }
  async chat(messages) {
    aiState.calls += 1;
    aiState.prompts.push(messages[messages.length - 1].content);
    if (aiState.fail) { throw new Error('upstream down'); }
    return { content: aiState.reply, toolCalls: [] };
  }
}
class StubKnowledgeStore {
  getFingerprint() { return knowledgeState.fingerprint; }
  async searchBest(query) {
    knowledgeState.queries.push(query);
    return knowledgeState.hits;
  }
  citationOf(hit) { return hit.citation; }
}
global.__aiClass = StubAiService;
global.__knowledgeClass = StubKnowledgeStore;

function servicePrelude(poolInstance) {
  return `
${modelsPrelude}
const { ErrorBookPracticeSource, normalizeQuestionTitle, SOURCE_ERROR_BOOK, normalizeKnowledgeTag,
  stableTextHash } = global.__sourceModule;
const { PracticeHistoryStore, DEFAULT_SEED_MASTERY, buildPracticeHistoryLine } = global.__historyModule;
const { LearnerProfileStore } = global.__profileModule;
const { PracticeQuestionSynthesizer, SynthesisPassage, SynthesisRequest,
  SYNTHESIS_QUESTION_COUNT } = global.__synthModule;
const GeneratedQuestionPool = global.__poolClass;
class DataCollectService {
  collectAllData() {
    return global.__snapshot || { examScores: [], errorQuestions: [], courseProgress: [], totalStudyTime: 0 };
  }
}
class ErrorAttributionService {
  diagnosePracticeQuestion() { return { causeLabel: '测试归因', confidence: 80, remediation: '复习', evidence: '答错' }; }
}
const AiService = global.__aiClass;
const KnowledgeStore = global.__knowledgeClass;
`;
}

global.__synthModule = synthMod;
global.__aiState = aiState;
global.__knowledgeState = knowledgeState;

const historyMod = loadArkTs(`${SERVICE_DIR}PracticeHistoryStore.ets`,
  'const { reviewAgeLevel } = global.__sourceModule;');
global.__historyModule = historyMod;
global.__profileModule = loadArkTs(`${SERVICE_DIR}LearnerProfileStore.ets`,
  'const Logger = { error() {}, info() {} };');
global.__poolClass = GeneratedQuestionPool;

function serviceModule() {
  global.__poolClass = GeneratedQuestionPool;
  const prelude = servicePrelude();
  return loadArkTs(`${SERVICE_DIR}AdaptivePracticeService.ets`, prelude);
}

function resetWorld() {
  global.AppStorage.data.delete('PracticeHistory');
  global.AppStorage.data.delete('LearnerProfile');
  global.AppStorage.data.delete('ErrorQuestions');
  fileMap.clear();
  aiState.calls = 0;
  aiState.prompts = [];
  aiState.reply = REAL_REPLY;
  aiState.fail = false;
  knowledgeState.queries = [];
  knowledgeState.fingerprint = '';
  knowledgeState.hits = PASSAGES.map((p) => ({
    chunk: { knowledgeTag: p.knowledgeTag, text: p.text }, citation: p.citation,
  }));
  global.__snapshot = { examScores: [], errorQuestions: [], courseProgress: [], totalStudyTime: 0 };
}

function makeService(poolInstance) {
  const mod = serviceModule();
  return new mod.AdaptivePracticeService(new StubAiService(), new StubKnowledgeStore(), poolInstance);
}

resetWorld();
const emptyPoolService = makeService(new GeneratedQuestionPool());
const baseline = emptyPoolService.generateSession(6, NOW);
check('E 接线', '池为空时行为与改造前一致：仍满 6 题、全部非生成题',
  baseline.questions.length === 6 &&
  baseline.questions.every((q) => q.source !== SOURCE_AI_GENERATED),
  { count: baseline.questions.length, generated: baseline.questions.filter((q) => q.source === SOURCE_AI_GENERATED).length },
  { count: 6, generated: 0 });

const stockedPool = new GeneratedQuestionPool();
stockedPool.add('计算机网络', [generatedQuestion('gen_w1', '计算机网络', '模型写的网络题')]);
stockedPool.add('数据结构', [generatedQuestion('gen_d1', '数据结构', '模型写的数据结构题')]);
const stockedService = makeService(stockedPool);
const stocked = stockedService.generateSession(6, NOW);
check('E 接线', '池里有题时生成题进入会话，并按最弱知识点优先排在前面',
  stocked.questions[0].id === 'gen_w1' &&
  stocked.questions[1].id === 'gen_d1' &&
  stocked.questions[0].source === SOURCE_AI_GENERATED,
  stocked.questions.slice(0, 3).map((q) => `${q.id}:${q.source}`),
  'gen_w1, gen_d1 first');

check('E 接线', '每个知识点最多贡献一道生成题（不挤占题库的讲解材料）',
  (function () {
    const local = freshPool();
    const batch = [];
    for (let i = 0; i < 4; i += 1) { batch.push(generatedQuestion(`n${i}`, '计算机网络')); }
    local.add('计算机网络', batch);
    const service = makeService(local);
    const session = service.generateSession(6, NOW);
    return session.questions.filter((q) => q.source === SOURCE_AI_GENERATED).length === 1;
  })(),
  'one per tag', 1);

check('E 接线', '生成题同样遵守排除列表（换一组不会重复给出同一道）',
  (function () {
    const local = new GeneratedQuestionPool();
    local.add('计算机网络', [generatedQuestion('gen_w1', '计算机网络')]);
    const service = makeService(local);
    const second = service.generateSession(6, NOW, ['gen_w1']);
    return second.questions.every((q) => q.id !== 'gen_w1');
  })(),
  'excluded', 'excluded');

// Async assertions are collected here and awaited before the summary is
// printed, so a rejected promise shows up as a failing check rather than as a
// silent pass — and a swallowed rejection can never masquerade as green.
const asyncChecks = [];
function checkAsync(group, name, thunk, expected) {
  asyncChecks.push({ group, name, thunk, expected });
}

checkAsync('E 生成', '材料不足时不发请求（检索有返回不等于讲到了这个知识点）',
  async () => {
    resetWorld();
    knowledgeState.hits = [{ chunk: { knowledgeTag: 'x', text: '太短' }, citation: 'A' }];
    const service = makeService(new GeneratedQuestionPool());
    const added = await service.prepareQuestions([new KnowledgePracticeProfile('二叉树', 0, 70, 80, 'x')]);
    return { ok: added === 0 && aiState.calls === 0, added, calls: aiState.calls };
  },
  { added: 0, calls: 0 });

checkAsync('E 生成', '材料充足时按知识点出题并入池，返回新增数量',
  async () => {
    resetWorld();
    const pool0 = new GeneratedQuestionPool();
    const service = makeService(pool0);
    const added = await service.prepareQuestions([new KnowledgePracticeProfile('二叉搜索树', 0, 70, 80, 'x')]);
    const stats = service.getSynthesisStats();
    return {
      ok: added === 3 && pool0.countForTag('二叉搜索树') === 3 && stats.attempts === 1 &&
        stats.generated === 3 && stats.blocked === false && knowledgeState.queries.join('|') === '二叉搜索树',
      added, pooled: pool0.countForTag('二叉搜索树'), blocked: stats.blocked, lastError: stats.lastError,
    };
  },
  { added: 3, pooled: 3, blocked: false });

checkAsync('E 生成', '调用失败只试一次：置失败锁，其后不再发请求',
  async () => {
    resetWorld();
    aiState.fail = true;
    const service = makeService(new GeneratedQuestionPool());
    const first = await service.prepareQuestions([new KnowledgePracticeProfile('二叉搜索树', 0, 70, 80, 'x')]);
    const callsAfterFirst = aiState.calls;
    await service.prepareQuestions([new KnowledgePracticeProfile('二叉搜索树', 0, 70, 80, 'x')]);
    const blocked = service.getSynthesisStats().blocked;
    return { ok: first === 0 && callsAfterFirst === 1 && aiState.calls === 1 && blocked === true, first, callsAfterFirst, blocked };
  },
  { first: 0, callsAfterFirst: 1, blocked: true });

checkAsync('E 生成', '显式解除失败锁后允许重试（学习者修好配置后不必重启）',
  async () => {
    resetWorld();
    aiState.fail = true;
    const service = makeService(new GeneratedQuestionPool());
    await service.prepareQuestions([new KnowledgePracticeProfile('二叉搜索树', 0, 70, 80, 'x')]);
    const before = aiState.calls;
    aiState.fail = false;
    service.resetSynthesisBlock();
    const added = await service.prepareQuestions([new KnowledgePracticeProfile('二叉搜索树', 0, 70, 80, 'x')]);
    return { ok: before === 1 && added === 3 && aiState.calls === 2, before, added, calls: aiState.calls };
  },
  { before: 1, added: 3 });

checkAsync('E 生成', '并发调用单飞：同一知识点不会重复付费',
  async () => {
    resetWorld();
    const service = makeService(new GeneratedQuestionPool());
    const profile = new KnowledgePracticeProfile('二叉搜索树', 0, 70, 80, 'x');
    const both = await Promise.all([service.prepareQuestions([profile]), service.prepareQuestions([profile])]);
    return { ok: aiState.calls === 1 && both[0] === both[1], calls: aiState.calls, results: both };
  },
  { calls: 1 });

checkAsync('E 生成', '已覆盖的知识点不再请求（池里够一次输出就够两轮）',
  async () => {
    resetWorld();
    const pool0 = new GeneratedQuestionPool();
    const service = makeService(pool0);
    const profile = new KnowledgePracticeProfile('二叉搜索树', 0, 70, 80, 'x');
    await service.prepareQuestions([profile]);
    const callsAfterFirst = aiState.calls;
    const added = await service.prepareQuestions([profile]);
    return { ok: callsAfterFirst === 1 && added === 0 && aiState.calls === 1, callsAfterFirst, added };
  },
  { calls: 1, added: 0 });

checkAsync('E 生成', '每轮最多覆盖 tagLimit 个知识点',
  async () => {
    resetWorld();
    const service = makeService(new GeneratedQuestionPool());
    const profiles = [
      new KnowledgePracticeProfile('A', 0, 70, 90, 'x'),
      new KnowledgePracticeProfile('B', 0, 70, 80, 'x'),
      new KnowledgePracticeProfile('C', 0, 70, 70, 'x'),
    ];
    await service.prepareQuestions(profiles, 2);
    return { ok: aiState.calls === 2 && knowledgeState.queries.join('|') === 'A|B', calls: aiState.calls, queries: knowledgeState.queries };
  },
  { calls: 2 });

checkAsync('E 生成', '难度随掌握度走：薄弱给基础、中等给进阶、熟练给挑战',
  async () => {
    const seen = [];
    for (const mastery of [40, 70, 92]) {
      resetWorld();
      const service = makeService(new GeneratedQuestionPool());
      await service.prepareQuestions([new KnowledgePracticeProfile('X', 0, mastery, 80, 'x')]);
      seen.push(aiState.prompts[0].indexOf('难度：') >= 0
        ? aiState.prompts[0].slice(aiState.prompts[0].indexOf('难度：'), aiState.prompts[0].indexOf('难度：') + 5)
        : '?');
    }
    return { ok: seen.join('|') === '难度：基础|难度：进阶|难度：挑战', seen: seen.join('|') };
  },
  { seen: '难度：基础|难度：进阶|难度：挑战' });

checkAsync('E 生成', '语料指纹变化时，旧题作废并重新生成',
  async () => {
    resetWorld();
    knowledgeState.fingerprint = 'corpus-a';
    const pool0 = new GeneratedQuestionPool();
    const service = makeService(pool0);
    const profile = new KnowledgePracticeProfile('二叉搜索树', 0, 70, 80, 'x');
    await service.prepareQuestions([profile]);
    const sizeAfterFirst = pool0.size();
    knowledgeState.fingerprint = 'corpus-b';
    aiState.reply = REAL_REPLY;
    await service.prepareQuestions([profile]);
    return {
      ok: sizeAfterFirst === 3 && pool0.getCorpusFingerprint() === 'corpus-b' && pool0.size() === 3,
      sizeAfterFirst, fingerprint: pool0.getCorpusFingerprint(), size: pool0.size(),
    };
  },
  { sizeAfterFirst: 3, fingerprint: 'corpus-b', size: 3 });

checkAsync('E 生成', '生成的题目能被提交作答，答错照常写回错题本',
  async () => {
    resetWorld();
    const pool0 = new GeneratedQuestionPool();
    pool0.add('计算机网络', [generatedQuestion('gen_w1', '计算机网络', '模型写的网络题')]);
    const service = makeService(pool0);
    const session = service.generateSession(6, NOW);
    const question = session.questions[0];
    const wrongIndex = (question.correctIndex + 1) % question.options.length;
    service.submitAnswer(question, wrongIndex, NOW);
    const book = JSON.parse(global.AppStorage.data.get('ErrorQuestions'));
    return {
      ok: question.id === 'gen_w1' && question.source === SOURCE_AI_GENERATED && question.isSubmitted &&
        question.attribution !== undefined && book.length === 1 && book[0].sourceId === question.id,
      title: question.title, count: book.length, id: question.id,
    };
  },
  { count: 1 });

// ================= F. static guards =================

const synthSrc = fs.readFileSync(path.join(root, SERVICE_DIR, 'PracticeQuestionSynthesizer.ets'), 'utf8');
const poolSrc = fs.readFileSync(path.join(root, SERVICE_DIR, 'GeneratedQuestionPool.ets'), 'utf8');
const serviceSrc = fs.readFileSync(path.join(root, SERVICE_DIR, 'AdaptivePracticeService.ets'), 'utf8');
const modelsSrc = fs.readFileSync(path.join(root, 'features/aiagent/src/main/ets/viewmodel/AdaptivePracticeModels.ets'), 'utf8');

check('F 静态', '合成器不读时钟、不用随机数（可离线复现是它的全部价值）',
  synthSrc.indexOf('Date.now') < 0 && synthSrc.indexOf('Math.random') < 0 &&
  synthSrc.indexOf('fileIo') < 0,
  {
    clock: synthSrc.indexOf('Date.now') >= 0,
    random: synthSrc.indexOf('Math.random') >= 0,
    io: synthSrc.indexOf('fileIo') >= 0,
  },
  { clock: false, random: false, io: false });

check('F 静态', '题目 id 由 stableTextHash 派生，而不是第二套哈希实现',
  synthSrc.indexOf('stableTextHash') >= 0 && synthSrc.indexOf('hash * 31') < 0,
  { usesSharedHash: synthSrc.indexOf('stableTextHash') >= 0, ownLoop: synthSrc.indexOf('hash * 31') >= 0 },
  { usesSharedHash: true, ownLoop: false });

check('F 静态', '题目元数据只有一处：复用 isCorruptedText / normalizeQuestionTitle / normalizeKnowledgeTag',
  synthSrc.indexOf('import') >= 0 &&
  synthSrc.indexOf('isCorruptedText(text)') >= 0 &&
  synthSrc.indexOf('function isCorruptedText') < 0,
  'no second copy', 'no second copy');

check('F 静态', '生成层在画像层之前填充，生成题才有机会进入会话',
  (function () {
    const fill = serviceSrc.indexOf('this.fillFromPool(profiles');
    const profileLayer = serviceSrc.indexOf('this.pickQuestionForProfile(profiles[i]');
    return fill >= 0 && profileLayer >= 0 && fill < profileLayer;
  })(),
  'ordered', 'ordered');

check('F 静态', '同步出题路径不解析检索单例（首帧不该等语料索引）',
  (function () {
    const fillStart = serviceSrc.indexOf('private fillFromPool');
    const fillEnd = serviceSrc.indexOf('private corpusFingerprint');
    const body = serviceSrc.slice(fillStart, fillEnd);
    // Checking for the *call*, not for `this.knowledge()`: the fingerprint is
    // reached through `corpusFingerprint()`, so a variant that moves the call
    // into this method never spells the singleton out and would slip past a
    // narrower check.
    return fillStart >= 0 && fillEnd > fillStart &&
      body.indexOf('corpusFingerprint()') < 0 &&
      serviceSrc.indexOf('this.questionPool.setCorpusFingerprint(this.corpusFingerprint())') >= 0;
  })(),
  'fingerprint only on the write path', 'fingerprint only on the write path');

check('F 静态', 'citation 默认空串，既有调用点无需改动',
  modelsSrc.indexOf('citation: string = \'\'') >= 0,
  'default empty', 'default empty');

// ---------- report ----------

for (const r of results) {
  const mark = r.status === 'PASS' ? 'ok  ' : 'FAIL';
  console.log(`${mark} [${r.group}] ${r.name}`);
  if (r.status === 'FAIL') {
    console.log(`       actual  : ${JSON.stringify(r.actual)}`);
    console.log(`       expected: ${JSON.stringify(r.expected)}`);
  }
}

(async () => {
  for (const item of asyncChecks) {
    let outcome = { ok: false, error: 'threw' };
    try {
      outcome = await item.thunk();
    } catch (e) {
      outcome = { ok: false, error: String(e && e.message ? e.message : e) };
    }
    const mark = outcome.ok ? 'ok  ' : 'FAIL';
    console.log(`${mark} [${item.group}] ${item.name}`);
    if (!outcome.ok) {
      failures++;
      console.log(`       actual  : ${JSON.stringify(outcome)}`);
      console.log(`       expected: ${JSON.stringify(item.expected)}`);
    }
  }

  const total = results.length + asyncChecks.length;
  console.log(`\n${total - failures}/${total} passed`);
  process.exit(failures > 0 ? 1 : 0);
})();

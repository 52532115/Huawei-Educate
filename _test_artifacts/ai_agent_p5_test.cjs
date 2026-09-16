// Offline tests for P5: error-book driven practice ("方案 1").
//
// Groups A-D exercise ErrorBookPracticeSource on its own (pure, no I/O);
// groups E-F wire it into the real AdaptivePracticeService and assert the
// write-back loop leaves the error book consistent.
const fs = require('fs');
const path = require('path');
const ts = require('D:/devecostudio-windows-6.0.2.650/DevEco Studio/tools/hvigor/hvigor/node_modules/typescript');

const root = path.resolve(__dirname, '..');
const results = [];
let failures = 0;

/**
 * Masks the random suffix the service appends to newly created error-book ids.
 * It only exists to keep ids unique, so it carries no assertion value — and
 * leaving it in `actual` would rewrite the result file on every run.
 */
function maskRandomIdSuffix(id) {
  return typeof id === 'string' ? id.replace(/_[a-z0-9]{6}$/, '_<random>') : id;
}

function check(group, name, condition, actual, expected) {
  results.push({ group, name, status: condition ? 'PASS' : 'FAIL', actual, expected });
  if (!condition) failures++;
}

function transpileArkTs(relativePath) {
  const filePath = path.join(root, relativePath);
  let source = fs.readFileSync(filePath, 'utf8');
  source = source.replace(/import[\s\S]*?from\s+['"][^'"]+['"];\s*/g, '');
  return ts.transpileModule(source, {
    compilerOptions: {
      module: ts.ModuleKind.CommonJS,
      target: ts.ScriptTarget.ES2020,
      esModuleInterop: true,
    },
  }).outputText;
}

function loadArkTs(relativePath, prelude = '') {
  const compiled = transpileArkTs(relativePath);
  const module = { exports: {} };
  new Function('module', 'exports', `${prelude}\n${compiled}`)(module, module.exports);
  return module.exports;
}

const NOW = 1735689600000; // 2025-01-01T00:00:00Z, injected everywhere for determinism
const DAY = 86400000;

// Shared in-memory AppStorage + fileIo. Both must be globals: compiled modules
// run inside `new Function` and only see the global scope.
const fileMap = new Map();
let lastOpenedPath = '';
global.AppStorage = {
  data: new Map(),
  get(key) { return this.data.get(key); },
  setOrCreate(key, value) { this.data.set(key, value); },
};
global.fileIo = {
  readTextSync(p) { return fileMap.get(p) || ''; },
  openSync(p) { lastOpenedPath = p; return { fd: 1 }; },
  writeSync(fd, text) { fileMap.set(lastOpenedPath, text); },
  closeSync() {},
};
global.__snapshot = { examScores: [], errorQuestions: [], courseProgress: [], totalStudyTime: 0 };

// Model classes, shared verbatim by both module loads. Exposed on global so the
// test script can construct fixtures (a prelude's lexical scope is invisible here).
const modelsPrelude = `
const PracticeDifficulty = { BASIC: '基础', MEDIUM: '进阶', HARD: '挑战' };
class ErrorQuestionItem {
  constructor(title, category, id = '') {
    this.id = id; this.title = title; this.category = category;
    this.options = []; this.correctIndex = -1; this.userIndex = -1;
    this.correctLabel = ''; this.userLabel = ''; this.userNote = '';
    this.mistakeReason = ''; this.createTime = 0; this.analysis = '';
    this.wrongCount = 0; this.lastReviewTime = 0;
  }
}
class AdaptivePracticeQuestion {
  constructor(id, title, options, correctIndex, knowledgeTag, difficulty, source, explanation, recommendation,
    sourceRecordId = '') {
    Object.assign(this, { id, title, options, correctIndex, knowledgeTag, difficulty, source, explanation,
      recommendation, selectedIndex: -1, isSubmitted: false, syncedToErrorBook: false, sourceRecordId,
      masteryRecorded: false });
  }
}
class ErrorBookPracticeCandidate {
  constructor() {
    Object.assign(this, { recordId: '', title: '', normalizedTitle: '', options: [], correctIndex: -1,
      knowledgeTag: '', userNote: '', mistakeReason: '', analysis: '', createTime: 0, lastActivityTime: 0,
      repeatCount: 1, isDemo: false, score: 0, difficulty: PracticeDifficulty.BASIC });
  }
}
class KnowledgePracticeProfile {
  constructor(tag, errorCount, mastery, priority, reason) {
    Object.assign(this, { tag, errorCount, mastery, priority, reason, attempts: 0, correct: 0, lastPracticeTime: 0 });
  }
}
class PracticeSessionSummary {
  constructor() {
    Object.assign(this, { totalCount: 0, correctCount: 0, score: 0, weakTags: [], masteredTags: [], advice: '',
      generatedAt: Date.now(), historyAttempts: 0, historyCorrect: 0, historyTags: 0, historyWeakTags: [] });
  }
}
class AdaptivePracticeSession {
  constructor(id, questions, profiles) { Object.assign(this, { id, questions, profiles, summary: new PracticeSessionSummary() }); }
}
global.ErrorQuestionItem = ErrorQuestionItem;
global.AdaptivePracticeQuestion = AdaptivePracticeQuestion;
global.AdaptivePracticeSession = AdaptivePracticeSession;
`;

const sourceMod = loadArkTs('features/aiagent/src/main/ets/service/ErrorBookPracticeSource.ets', modelsPrelude);
global.__sourceModule = sourceMod;
const source = new sourceMod.ErrorBookPracticeSource();
const { SOURCE_ERROR_BOOK } = sourceMod;

/** Builds an ErrorQuestionItem fixture; every field overridable. */
function makeItem(overrides) {
  const o = overrides || {};
  const item = new global.ErrorQuestionItem(
    o.title === undefined ? '题目' : o.title,
    o.category === undefined ? '函数与极限' : o.category,
    o.id === undefined ? 'e1' : o.id,
  );
  item.options = o.options === undefined ? ['A', 'B', 'C', 'D'] : o.options;
  item.correctIndex = o.correctIndex === undefined ? 1 : o.correctIndex;
  item.createTime = o.createTime === undefined ? NOW - 30 * DAY : o.createTime;
  if (o.userNote !== undefined) item.userNote = o.userNote;
  if (o.mistakeReason !== undefined) item.mistakeReason = o.mistakeReason;
  if (o.analysis !== undefined) item.analysis = o.analysis;
  if (o.wrongCount !== undefined) item.wrongCount = o.wrongCount;
  if (o.lastReviewTime !== undefined) item.lastReviewTime = o.lastReviewTime;
  return item;
}

function tagOf(question) { return question.knowledgeTag; }

// ---------- Part 1: ErrorBookPracticeSource (pure) ----------

// A. cleaning
const ok = source.buildQuestions([makeItem({ title: '极限题', category: '函数与极限', id: 'e1', options: ['0', '1', '2', '不存在'], correctIndex: 2 })], 6, NOW);
check('A 清洗', '正常记录转成可作答题目',
  ok.length === 1 && ok[0].title === '极限题' && ok[0].correctIndex === 2 &&
  ok[0].knowledgeTag === '函数与极限' && ok[0].options.length === 4 && ok[0].source === SOURCE_ERROR_BOOK,
  { count: ok.length, correctIndex: ok.length ? ok[0].correctIndex : null, source: ok.length ? ok[0].source : null },
  { count: 1, correctIndex: 2, source: SOURCE_ERROR_BOOK });

const okItems = [makeItem({ id: 'e1', options: ['0', '1', '2', '不存在'], correctIndex: 2 })];
const okQs = source.buildQuestions(okItems, 6, NOW);
okQs[0].options[0] = '被改过';
check('A 清洗', '题目选项是副本，不污染错题本记录', okItems[0].options[0] === '0', okItems[0].options[0], '0');

check('A 清洗', '空题干丢弃', source.buildQuestions([makeItem({ title: '   ' })], 6, NOW).length === 0,
  source.buildQuestions([makeItem({ title: '   ' })], 6, NOW).length, 0);
check('A 清洗', '空选项数组丢弃', source.buildQuestions([makeItem({ options: [] })], 6, NOW).length === 0, 'dropped', 0);
check('A 清洗', '仅1个选项丢弃', source.buildQuestions([makeItem({ options: ['A'] })], 6, NOW).length === 0, 'dropped', 0);
check('A 清洗', '含空白选项丢弃（保留位置不合法）', source.buildQuestions([makeItem({ options: ['A', ''] })], 6, NOW).length === 0, 'dropped', 0);
check('A 清洗', '选项中部的空白会使下标错位，必须丢弃',
  source.buildQuestions([makeItem({ options: ['', 'B', 'C'], correctIndex: 1 })], 6, NOW).length === 0, 'dropped', 0);
check('A 清洗', 'rightQues 越界丢弃', source.buildQuestions([makeItem({ options: ['A', 'B', 'C'], correctIndex: 3 })], 6, NOW).length === 0, 'dropped', 0);
check('A 清洗', 'rightQues 为 -1 丢弃', source.buildQuestions([makeItem({ options: ['A', 'B', 'C'], correctIndex: -1 })], 6, NOW).length === 0, 'dropped', 0);

const notArray = makeItem({});
notArray.options = 'not-an-array';
const stringOption = makeItem({});
stringOption.options = 'not-an-array';
check('A 清洗', 'option 非数组不抛错、丢弃', source.buildQuestions([stringOption], 6, NOW).length === 0, 'dropped', 0);

const seven = source.buildQuestions([makeItem({ options: ['1', '2', '3', '4', '5', '6', '7'], correctIndex: 3 })], 6, NOW);
check('A 清洗', '超过6个选项截断且正确项不变',
  seven.length === 1 && seven[0].options.length === 6 && seven[0].correctIndex === 3,
  { options: seven.length ? seven[0].options.length : null, correctIndex: seven.length ? seven[0].correctIndex : null },
  { options: 6, correctIndex: 3 });

check('A 清洗', '乱码题干丢弃（锛）', source.buildQuestions([makeItem({ title: '锛?极限' })], 6, NOW).length === 0, 'dropped', 0);
check('A 清洗', '替换字符题干丢弃（U+FFFD）', source.buildQuestions([makeItem({ title: '极限�' })], 6, NOW).length === 0, 'dropped', 0);
check('A 清洗', '私用区字符题干丢弃（U+E11F）', source.buildQuestions([makeItem({ title: '极限' })], 6, NOW).length === 0, 'dropped', 0);

const questionMark = source.buildQuestions([makeItem({ title: '求 f(x)=? 的极限', id: 'q1' })], 6, NOW);
check('A 清洗', '半角问号不算乱码（回归旧 containsMojibake 误杀）', questionMark.length === 1, questionMark.length, 1);

const demoMath = source.buildQuestions([makeItem({ title: '定积分 ∫₀¹ (2x+1)dx 的值为？', id: 'q2' })], 6, NOW);
check('A 清洗', '数学符号（∫₀¹）不被误判为乱码', demoMath.length === 1, demoMath.length, 1);

const noTag = source.buildQuestions([makeItem({ category: '', id: 'q3' })], 6, NOW);
check('A 清洗', '空知识点归入未分类但题目保留',
  noTag.length === 1 && noTag[0].knowledgeTag === '未分类', noTag.length ? noTag[0].knowledgeTag : null, '未分类');
const badTag = source.buildQuestions([makeItem({ category: '鏁版嵁缁撴瀯', id: 'q4' })], 6, NOW);
check('A 清洗', '乱码知识点归入未分类但题目保留',
  badTag.length === 1 && badTag[0].knowledgeTag === '未分类', badTag.length ? badTag[0].knowledgeTag : null, '未分类');
check('A 清洗', 'createTime 为 0 不崩', source.buildQuestions([makeItem({ createTime: 0 })], 6, NOW).length === 1, 'ok', 1);

// B. de-duplication
const dupes = source.buildCandidates([
  makeItem({ title: '同题', id: 'old', createTime: NOW - 30 * DAY }),
  makeItem({ title: '  同题  ', id: 'new', createTime: NOW - 1 * DAY }),
], NOW);
check('B 去重', '同题干只保留一道且重做次数累加',
  dupes.length === 1 && dupes[0].repeatCount === 2 && dupes[0].difficulty === '进阶',
  { count: dupes.length, repeatCount: dupes.length ? dupes[0].repeatCount : null, difficulty: dupes.length ? dupes[0].difficulty : null },
  { count: 1, repeatCount: 2, difficulty: '进阶' });
check('B 去重', '去重保留 createTime 更早的那条', dupes.length === 1 && dupes[0].recordId === 'old',
  dupes.length ? dupes[0].recordId : null, 'old');

const noId = source.buildQuestions([
  makeItem({ title: '无ID题甲', id: '' }),
  makeItem({ title: '无ID题乙', id: '' }),
], 6, NOW);
check('B 去重', '无 id 的不同题干都保留且题目 id 稳定',
  noId.length === 2 && noId[0].id.indexOf('q_err_h_') === 0 && noId[1].id.indexOf('q_err_h_') === 0 && noId[0].id !== noId[1].id,
  noId.map((q) => q.id), 'two stable q_err_h_ ids');
const noIdAgain = source.buildQuestions([
  makeItem({ title: '无ID题乙', id: '' }),
  makeItem({ title: '无ID题甲', id: '' }),
], 6, NOW);
check('B 去重', '无 id 题目 id 与顺序无关（稳定哈希）',
  noIdAgain.map((q) => q.id).join('|') === noId.map((q) => q.id).join('|'),
  noIdAgain.map((q) => q.id), noId.map((q) => q.id));

// C. ordering
const aging = source.buildCandidates([
  makeItem({ title: '今天的题', id: 'a', createTime: NOW - 6 * 3600000 }),
  makeItem({ title: '八天前的题', id: 'b', createTime: NOW - 8 * DAY }),
  makeItem({ title: '三十天前的题', id: 'c', createTime: NOW - 30 * DAY }),
], NOW);
check('C 排序', '越久没复习的错题越靠前',
  aging.map((c) => c.recordId).join('|') === 'c|b|a', aging.map((c) => c.recordId), ['c', 'b', 'a']);
check('C 排序', '时间档打分符合预期（30天=60，8天=45，今天=0）',
  aging[0].score === 60 && aging[1].score === 45 && aging[2].score === 0,
  aging.map((c) => c.score), [60, 45, 0]);

const repeats = source.buildCandidates([
  makeItem({ title: '错一次', id: 'x', createTime: NOW - 30 * DAY, wrongCount: 1 }),
  makeItem({ title: '错三次', id: 'y', createTime: NOW - 30 * DAY, wrongCount: 3 }),
], NOW);
check('C 排序', '相同时长下错得多的更靠前',
  repeats.map((c) => c.recordId).join('|') === 'y|x' && repeats[0].score === 100,
  repeats.map((c) => `${c.recordId}:${c.score}`), ['y:100', 'x:60']);

const shuffledInput = [
  makeItem({ title: '丙', id: 'p3', createTime: NOW - 30 * DAY }),
  makeItem({ title: '甲', id: 'p1', createTime: NOW - 2 * DAY }),
  makeItem({ title: '乙', id: 'p2', createTime: NOW - 9 * DAY }),
];
const ordered = source.buildQuestions(shuffledInput, 6, NOW).map((q) => q.id);
const reversed = source.buildQuestions([...shuffledInput].reverse(), 6, NOW).map((q) => q.id);
check('C 排序', '打乱输入顺序输出不变（不依赖数组下标）', ordered.join('|') === reversed.join('|'), reversed, ordered);

const twice = source.buildQuestions(shuffledInput, 6, NOW).map((q) => q.id);
check('C 排序', '同输入两次调用结果完全一致', twice.join('|') === ordered.join('|'), twice, ordered);

const demo = source.buildQuestions([
  makeItem({ title: '演示题', id: 'err_default_123_0', createTime: NOW - 30 * DAY }),
  makeItem({ title: '真实题', id: 'err_real', createTime: NOW - 30 * DAY }),
], 6, NOW);
check('C 排序', '同分时演示数据靠后',
  demo.length === 2 && demo[0].id === 'q_err_err_real', demo.map((q) => q.id), ['q_err_err_real', 'q_err_err_default_123_0']);
check('C 排序', '演示题不可回写（sourceRecordId 为空）',
  demo.length === 2 && demo[0].sourceRecordId === 'err_real' && demo[1].sourceRecordId === '',
  demo.map((q) => q.sourceRecordId), ['err_real', '']);

// D. tag coverage
const twoTags = [
  makeItem({ title: 'X1', id: 'x1', category: 'X', createTime: NOW - 30 * DAY }),
  makeItem({ title: 'X2', id: 'x2', category: 'X', createTime: NOW - 29 * DAY }),
  makeItem({ title: 'X3', id: 'x3', category: 'X', createTime: NOW - 28 * DAY }),
  makeItem({ title: 'X4', id: 'x4', category: 'X', createTime: NOW - 27 * DAY }),
  makeItem({ title: 'Y1', id: 'y1', category: 'Y', createTime: NOW - 26 * DAY }),
  makeItem({ title: 'Y2', id: 'y2', category: 'Y', createTime: NOW - 25 * DAY }),
];
const covered = source.buildQuestions(twoTags, 4, NOW);
const coveredTags = covered.map(tagOf);
check('D 覆盖', '前两道来自不同知识点（round-robin）',
  covered.length === 4 && coveredTags[0] !== coveredTags[1],
  coveredTags, 'alternating tags');
check('D 覆盖', '两轮各取一道，不会全挤在一个知识点',
  coveredTags.filter((t) => t === 'X').length === 2 && coveredTags.filter((t) => t === 'Y').length === 2,
  coveredTags, ['X', 'Y', 'X', 'Y']);

const singleTag = source.buildQuestions([
  makeItem({ title: 'S1', id: 's1', category: 'S' }),
  makeItem({ title: 'S2', id: 's2', category: 'S' }),
  makeItem({ title: 'S3', id: 's3', category: 'S' }),
  makeItem({ title: 'S4', id: 's4', category: 'S' }),
  makeItem({ title: 'S5', id: 's5', category: 'S' }),
  makeItem({ title: 'S6', id: 's6', category: 'S' }),
], 6, NOW);
check('D 覆盖', '只有一个知识点时取满6道不崩', singleTag.length === 6, singleTag.length, 6);

const short = source.buildQuestions([makeItem({ title: '唯一', id: 'only' })], 10, NOW);
check('D 覆盖', '题量不足时返回全部而不是占位题', short.length === 1, short.length, 1);

const emptySource = source.buildQuestions([], 6, NOW);
check('D 覆盖', '空错题本返回空数组', Array.isArray(emptySource) && emptySource.length === 0, emptySource.length, 0);

// ---------- Part 2: integration with the real service ----------

// The service now pulls in a practice-history store and the learner-profile
// store. Both are loaded for real (not stubbed), so the write-back assertions
// below keep exercising the true integration rather than a fake.
function servicePrelude() {
  const historyMod = loadArkTs(
    'features/aiagent/src/main/ets/service/PracticeHistoryStore.ets',
    'const { reviewAgeLevel } = global.__sourceModule;');
  global.__historyModule = historyMod;
  global.__profileModule = loadArkTs('features/aiagent/src/main/ets/service/LearnerProfileStore.ets',
    'const Logger = { error() {}, info() {} };');
  return `
${modelsPrelude}
const { ErrorBookPracticeSource, normalizeQuestionTitle, SOURCE_ERROR_BOOK, normalizeKnowledgeTag } = global.__sourceModule;
const { PracticeHistoryStore, DEFAULT_SEED_MASTERY, buildPracticeHistoryLine } = global.__historyModule;
const { LearnerProfileStore } = global.__profileModule;
class DataCollectService {
  collectAllData() {
    return global.__snapshot || { examScores: [], errorQuestions: [], courseProgress: [], totalStudyTime: 0 };
  }
}
class ErrorAttributionService {
  diagnosePracticeQuestion() { return { causeLabel: '测试归因', confidence: 80, remediation: '复习', evidence: '答错' }; }
}
`;
}
const serviceMod = loadArkTs('features/aiagent/src/main/ets/service/AdaptivePracticeService.ets', servicePrelude());
const service = new serviceMod.AdaptivePracticeService();

function setErrorBook(records) {
  global.AppStorage.setOrCreate('ErrorQuestions', records === null ? '' : JSON.stringify(records));
}
function readErrorBook() {
  const raw = global.AppStorage.data.get('ErrorQuestions');
  return raw ? JSON.parse(raw) : [];
}

// E. wiring
const sixErrors = [];
for (let i = 0; i < 6; i += 1) {
  sixErrors.push(makeItem({ title: `错题${i}`, id: `eb${i}`, category: i % 2 === 0 ? '函数与极限' : '数据结构', createTime: NOW - (i + 1) * DAY }));
}
setErrorBook([]);
global.__snapshot = { examScores: [], errorQuestions: sixErrors, courseProgress: [], totalStudyTime: 0 };
const sessionE1 = service.generateSession(6, NOW);
check('E 接线', '错题充足时六道题全部来自错题本',
  sessionE1.questions.length === 6 && sessionE1.questions.every((q) => q.id.indexOf('q_err_') === 0) &&
  sessionE1.questions.every((q) => q.source === SOURCE_ERROR_BOOK),
  sessionE1.questions.map((q) => q.id), '6 error-book questions');

global.__snapshot = { examScores: [], errorQuestions: [sixErrors[0], sixErrors[1]], courseProgress: [], totalStudyTime: 0 };
const sessionE2 = service.generateSession(6, NOW);
const e2Ids = sessionE2.questions.map((q) => q.id);
check('E 接线', '错题不足时用题库补齐且 id 不重复',
  sessionE2.questions.length === 6 && new Set(e2Ids).size === 6 &&
  e2Ids.filter((id) => id.indexOf('q_err_') === 0).length === 2,
  { total: e2Ids.length, unique: new Set(e2Ids).size, fromBook: e2Ids.filter((id) => id.indexOf('q_err_') === 0).length },
  { total: 6, unique: 6, fromBook: 2 });

global.__snapshot = {
  examScores: [],
  errorQuestions: [makeItem({ title: '', id: 'junk1' }), makeItem({ title: '垃圾', id: 'junk2', options: [] })],
  courseProgress: [],
  totalStudyTime: 0,
};
let sessionE3 = null;
let e3Threw = false;
try {
  sessionE3 = service.generateSession(6, NOW);
} catch (e) {
  e3Threw = true;
}
check('E 接线', '错题全是脏数据时回退题库且不抛错',
  !e3Threw && sessionE3 !== null && sessionE3.questions.length === 6,
  { threw: e3Threw, count: sessionE3 ? sessionE3.questions.length : null }, { threw: false, count: 6 });

const bankTitle = '极限 lim(x→0) sin(2x)/x 的值为？';
global.__snapshot = {
  examScores: [],
  errorQuestions: [makeItem({ title: bankTitle, id: 'clash', category: '函数与极限' })],
  courseProgress: [],
  totalStudyTime: 0,
};
const sessionE4 = service.generateSession(6, NOW);
const clashCount = sessionE4.questions.filter((q) => q.title === bankTitle).length;
check('E 接线', '错题与题库撞题面时一轮内只出现一次', clashCount === 1, clashCount, 1);

// F. write-back loop
function prepareQuestion(record) {
  setErrorBook([record]);
  const item = makeItem({
    title: record.title, id: record.id, category: record.knowledgeTag,
    options: record.option, correctIndex: record.rightQues, createTime: record.createTime,
    userNote: record.userNote, mistakeReason: record.mistakeReason, wrongCount: record.wrongCount,
  });
  return source.buildQuestions([item], 6, NOW)[0];
}

const baseRecord = {
  id: 'rec1', title: '重做的错题', option: ['A', 'B', 'C', 'D'], rightQues: 2,
  userNote: '我的笔记', mistakeReason: '概念混淆', knowledgeTag: '函数与极限',
  createTime: NOW - 30 * DAY, key: '', wrongCount: 1,
};

const qWrong = prepareQuestion(baseRecord);
service.submitAnswer(qWrong, 0, NOW);
const afterWrong = readErrorBook();
check('F 回写', '重做答错时原地更新，不新增记录', afterWrong.length === 1, afterWrong.length, 1);
check('F 回写', '更新本次误选与重做次数',
  afterWrong[0].answer === 0 && afterWrong[0].wrongCount === 2 && afterWrong[0].lastReviewTime === NOW,
  { answer: afterWrong[0].answer, wrongCount: afterWrong[0].wrongCount, lastReviewTime: afterWrong[0].lastReviewTime },
  { answer: 0, wrongCount: 2, lastReviewTime: NOW });
check('F 回写', '原本的 createTime 保留（越旧越优先的年龄信号）',
  afterWrong[0].createTime === NOW - 30 * DAY, afterWrong[0].createTime, NOW - 30 * DAY);
check('F 回写', '写入本次归因结论', (afterWrong[0].analysis || '').indexOf('测试归因') >= 0, afterWrong[0].analysis, 'contains 测试归因');
check('F 回写', '不覆盖学生自己的字段',
  afterWrong[0].userNote === '我的笔记' && afterWrong[0].mistakeReason === '概念混淆' &&
  afterWrong[0].rightQues === 2 && afterWrong[0].option.length === 4,
  { userNote: afterWrong[0].userNote, rightQues: afterWrong[0].rightQues }, { userNote: '我的笔记', rightQues: 2 });

service.submitAnswer(qWrong, 1, NOW);
const afterRepeat = readErrorBook();
check('F 回写', '同一题重复提交不再重复更新（syncedToErrorBook 生效）',
  afterRepeat.length === 1 && afterRepeat[0].wrongCount === 2,
  { count: afterRepeat.length, wrongCount: afterRepeat[0].wrongCount }, { count: 1, wrongCount: 2 });

const qOrphan = prepareQuestion({
  id: 'gone', title: '已被删除的错题', option: ['A', 'B', 'C'], rightQues: 1,
  userNote: '', mistakeReason: '', knowledgeTag: '数据结构', createTime: NOW - 5 * DAY, key: '',
});
setErrorBook([]); // learner deleted the record after the question was generated
service.submitAnswer(qOrphan, 0, NOW);
const afterOrphan = readErrorBook();
check('F 回写', '原记录已被删除时回退为追加，不丢数据',
  afterOrphan.length === 1 && afterOrphan[0].source === 'adaptive_practice',
  { count: afterOrphan.length, source: afterOrphan[0].source }, { count: 1, source: 'adaptive_practice' });
// The appended record's id ends in a random suffix (by design), so it is masked
// in the reported value — otherwise every run rewrites the result file and a
// stable artifact turns into per-run noise. The identity check itself still runs
// against the real ids.
check('F 回写', '追加后题目重新指向新记录，避免再次重复写入',
  qOrphan.sourceRecordId === afterOrphan[0].id,
  maskRandomIdSuffix(qOrphan.sourceRecordId), maskRandomIdSuffix(afterOrphan[0].id));

const bankQuestion = new global.AdaptivePracticeQuestion(
  'q_bank', '题库题', ['A', 'B', 'C', 'D'], 1, '数据结构', '基础', '来自题库', '解析', '建议', '');
setErrorBook([]);
service.submitAnswer(bankQuestion, 3, NOW);
const afterBank = readErrorBook();
check('F 回写', '题库题答错仍走追加（既有行为不回归）',
  afterBank.length === 1 && afterBank[0].source === 'adaptive_practice',
  { count: afterBank.length, source: afterBank.length ? afterBank[0].source : null }, { count: 1, source: 'adaptive_practice' });

const demoQuestion = source.buildQuestions([makeItem({ title: '演示错题', id: 'err_default_9_0' })], 6, NOW)[0];
setErrorBook([{
  id: 'err_default_9_0', title: '演示错题', option: ['A', 'B', 'C', 'D'], rightQues: 1,
  userNote: '', mistakeReason: '', knowledgeTag: '函数与极限', createTime: NOW - 30 * DAY, key: '',
}]);
service.submitAnswer(demoQuestion, 0, NOW);
const afterDemo = readErrorBook();
check('F 回写', '演示题答错落到同题记录上，不新增重复条目',
  afterDemo.length === 1 && afterDemo[0].id === 'err_default_9_0' &&
  afterDemo[0].answer === 0 && afterDemo[0].wrongCount === 2,
  { count: afterDemo.length, answer: afterDemo[0].answer, wrongCount: afterDemo[0].wrongCount },
  { count: 1, answer: 0, wrongCount: 2 });

// Regression for the reported duplication: every fresh session mints new
// question ids (and demo records get new ids on a clean start), so dedup by
// record id alone let the same question pile up.
setErrorBook([]);
const dupeA = new global.AdaptivePracticeQuestion(
  'q_bank_a', '重复错的题', ['A', 'B', 'C', 'D'], 1, '数据结构', '基础', 'bank', '解析', '建议', '');
service.submitAnswer(dupeA, 0, NOW);
const dupeB = new global.AdaptivePracticeQuestion(
  'q_bank_b', '重复错的题', ['A', 'B', 'C', 'D'], 1, '数据结构', '基础', 'bank', '解析', '建议', '');
service.submitAnswer(dupeB, 0, NOW);
const afterDupe = readErrorBook();
check('F 回写', '同题以不同题目 id 再答错时不新增重复条目',
  afterDupe.length === 1 && afterDupe[0].wrongCount === 2 && afterDupe[0].id === dupeA.sourceRecordId,
  { count: afterDupe.length, wrongCount: afterDupe[0].wrongCount, id: maskRandomIdSuffix(afterDupe[0].id) },
  { count: 1, wrongCount: 2, id: maskRandomIdSuffix(dupeA.sourceRecordId) });

const reviewRecord = {
  id: 'rev1', title: '答对的错题', option: ['A', 'B', 'C', 'D'], rightQues: 2,
  userNote: '', mistakeReason: '', knowledgeTag: '函数与极限', createTime: NOW - 30 * DAY, key: '',
};
const qRight = prepareQuestion(reviewRecord);
const reviewNow = NOW + 5 * DAY;
const reviewSession = new global.AdaptivePracticeSession('s1', [qRight], []);
service.submitAnswer(qRight, 2, reviewNow);
const midReview = readErrorBook();
check('F 回写', '答对时不立即写盘（等会话结束统一降权）',
  midReview.length === 1 && midReview[0].lastReviewTime === undefined, midReview[0].lastReviewTime, undefined);

service.buildSummary(reviewSession, reviewNow);
const afterReview = readErrorBook();
check('F 回写', '答对后仅在汇总时刷新复习时间，不删除记录',
  afterReview.length === 1 && afterReview[0].lastReviewTime === reviewNow && afterReview[0].id === 'rev1',
  { count: afterReview.length, lastReviewTime: afterReview[0].lastReviewTime }, { count: 1, lastReviewTime: reviewNow });

service.buildSummary(reviewSession, reviewNow);
const afterReview2 = readErrorBook();
check('F 回写', '重复汇总不产生额外写入（幂等）',
  afterReview2.length === 1 && afterReview2[0].lastReviewTime === reviewNow,
  afterReview2[0].lastReviewTime, reviewNow);

// H. 换一组 must actually produce a different set
const storeMod = loadArkTs('features/aiagent/src/main/ets/service/PracticeSessionStore.ets', modelsPrelude);
global.__storeModule = storeMod;
global.__sourceModule = sourceMod;
global.__serviceModule = serviceMod;
const vmPrelude = `
${modelsPrelude}
function Observed(target) { return target; }
const { AdaptivePracticeService } = global.__serviceModule;
const { PracticeSessionStore } = global.__storeModule;
const { SOURCE_ERROR_BOOK } = global.__sourceModule;
const { PracticeHistoryTotals } = global.__historyModule;
class ErrorAttributionService { updateErrorBookAttributions() { return 0; } }
`;
const vmMod = loadArkTs('features/aiagent/src/main/ets/viewmodel/AdaptivePracticeViewModel.ets', vmPrelude);

const manyErrors = [];
for (let i = 0; i < 12; i += 1) {
  manyErrors.push(makeItem({
    title: `轮换题${i}`, id: `rot${i}`, category: '函数与极限',
    createTime: NOW - (i + 1) * DAY,
  }));
}
const excluded = source.buildQuestions(manyErrors, 6, NOW).map((q) => q.id);
const nextSet = source.buildQuestions(manyErrors, 6, NOW, excluded).map((q) => q.id);
check('H 换一组', '排除已出的题后返回不同的一组',
  nextSet.length === 6 && nextSet.every((id) => excluded.indexOf(id) < 0),
  nextSet, 'none of ' + excluded.join(','));
check('H 换一组', '题量取尽后返回空（由上层兜底）',
  source.buildQuestions(manyErrors, 6, NOW, manyErrors.map((i) => `q_err_${i.id}`)).length === 0,
  source.buildQuestions(manyErrors, 6, NOW, manyErrors.map((i) => `q_err_${i.id}`)).length, 0);

global.__snapshot = { examScores: [], errorQuestions: manyErrors, courseProgress: [], totalStudyTime: 0 };
setErrorBook([]);
const vm = new vmMod.AdaptivePracticeViewModel();
const vmFirst = vm.session.questions.map((q) => q.id).join('|');
vm.resetSession();
const vmSecond = vm.session.questions.map((q) => q.id).join('|');
check('H 换一组', 'ViewModel.resetSession 给出不同的一组', vmFirst !== vmSecond, vmSecond, 'different from ' + vmFirst);
check('H 换一组', '换一组后回到第一题且未结束',
  vm.currentIndex === 0 && vm.isFinished === false,
  { currentIndex: vm.currentIndex, isFinished: vm.isFinished }, { currentIndex: 0, isFinished: false });
vm.resetSession();
vm.selectOption(1);
const selectedIndex = vm.getCurrentQuestion().selectedIndex;
const didSubmit = vm.submitCurrent();
check('H 换一组', 'ViewModel 选选项后可提交判分',
  selectedIndex === 1 && didSubmit === true && vm.getCurrentQuestion().isSubmitted === true,
  { selectedIndex: selectedIndex, didSubmit: didSubmit, isSubmitted: vm.getCurrentQuestion().isSubmitted },
  { selectedIndex: 1, didSubmit: true, isSubmitted: true });

// G. static checks
const sourceSrc = fs.readFileSync(path.join(root, 'features/aiagent/src/main/ets/service/ErrorBookPracticeSource.ets'), 'utf8');
// Match member access, not the words in prose/comment.
check('G 静态', '出题源不直接读写 AppStorage/fileIo（保持纯函数可测）',
  sourceSrc.indexOf('AppStorage.') < 0 && sourceSrc.indexOf('fileIo.') < 0,
  { hasAppStorage: sourceSrc.indexOf('AppStorage.') >= 0, hasFileIo: sourceSrc.indexOf('fileIo.') >= 0 },
  { hasAppStorage: false, hasFileIo: false });

const serviceSrc = fs.readFileSync(path.join(root, 'features/aiagent/src/main/ets/service/AdaptivePracticeService.ets'), 'utf8');
check('G 静态', '硬编码题库仍作为兜底保留',
  serviceSrc.indexOf('buildQuestionBank()') >= 0 && serviceSrc.indexOf('errorBookSource.buildQuestions') >= 0,
  { hasBank: serviceSrc.indexOf('buildQuestionBank()') >= 0, usesSource: serviceSrc.indexOf('errorBookSource.buildQuestions') >= 0 },
  { hasBank: true, usesSource: true });

// The practice card must not go back to being a by-value @Builder parameter:
// ArkUI does not refresh those, which froze the whole card on its first render.
const viewSrc = fs.readFileSync(path.join(root, 'features/aiagent/src/main/ets/components/AdaptivePracticeView.ets'), 'utf8');
check('G 静态', '练习卡片用 keyed ForEach 重建而非按值传参 builder',
  viewSrc.indexOf('ForEach(this.cardKeys') >= 0 && viewSrc.indexOf('PracticeContent()') >= 0 &&
  viewSrc.indexOf('PracticeContent(question') < 0,
  {
    keyedForEach: viewSrc.indexOf('ForEach(this.cardKeys') >= 0,
    parameterless: viewSrc.indexOf('PracticeContent()') >= 0,
    stillTakesParam: viewSrc.indexOf('PracticeContent(question') >= 0,
  },
  { keyedForEach: true, parameterless: true, stillTakesParam: false });

check('G 静态', '选项 ForEach 的 key 带上选中/判分状态',
  viewSrc.indexOf("? 'sel' : ''") >= 0 && viewSrc.indexOf("? 'sub' : ''") >= 0,
  viewSrc.indexOf('sel') >= 0 ? 'present' : 'missing', 'sel/sub in key');

// ArkUI nodes carry at most one bindSheet; chaining two on the same node makes
// them overwrite each other (📋 flipped the state but nothing showed until ⚙️
// forced a rebuild).
const chatViewSrc = fs.readFileSync(path.join(root, 'features/aiagent/src/main/ets/components/AiChatView.ets'), 'utf8');
const sheetLines = [];
chatViewSrc.split('\n').forEach((line, index) => {
  if (line.indexOf('.bindSheet(') >= 0) {
    sheetLines.push(index);
  }
});
let chainedSheets = false;
for (let i = 1; i < sheetLines.length; i += 1) {
  if (sheetLines[i] - sheetLines[i - 1] < 10) {
    chainedSheets = true;
  }
}
check('G 静态', '同一节点不链式挂两个 bindSheet',
  sheetLines.length === 2 && !chainedSheets,
  { count: sheetLines.length, chained: chainedSheets }, { count: 2, chained: false });

// An AI reply kept spilling out of its bubble. A pixel measurement of the
// screenshot settled the direction: the white background ended at x=353 while
// the text ink ran to x=424, i.e. the text was ~20% wider than its bubble and
// over on the right only. `constraintSize({ maxWidth })` caps the bubble but
// does not bound its children's measurement, so `.width('100%')` on the
// markdown root kept resolving against the full row width. The bubble and the
// text are now both sized from `contentWidth`, one definite number.
// Source only: the comments explaining this fix quote the very patterns the
// checks below forbid, so prose has to come out before matching.
function stripArkTsComments(source) {
  return source.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
}
const bubbleSrcRaw = fs.readFileSync(path.join(root, 'features/aiagent/src/main/ets/components/ChatBubble.ets'), 'utf8');
const bubbleSrc = stripArkTsComments(bubbleSrcRaw);
const markdownSrc = stripArkTsComments(
  fs.readFileSync(path.join(root, 'features/aiagent/src/main/ets/components/MarkdownText.ets'), 'utf8'));
// The class before @Component holds the module-level helper; anything after it
// is UI that no offline transpile can check.
const markdownLogic = markdownSrc.split('@Component')[0];

const bubbleConstrainLine = (bubbleSrc.match(/constraintSize\(\{[^}]*\}\)/) || [''])[0];
const bubbleUsesPercent =
  (bubbleSrc.match(/maxWidth:\s*'/g) || []).length > 0 ||
  (bubbleSrc.match(/maxWidth:\s*"/g) || []).length > 0;
check('G 静态', '气泡宽度上限是确定数值而非百分比（百分比在内容自适应容器里解析成父级约束宽度）',
  !bubbleUsesPercent && bubbleConstrainLine.indexOf('this.contentWidth') >= 0 &&
  bubbleSrc.indexOf('getDefaultDisplaySync') >= 0,
  { percent: bubbleUsesPercent, constraint: bubbleConstrainLine },
  { percent: false, constraint: 'constraintSize({ maxWidth: this.contentWidth + BUBBLE_INNER_PADDING })' });

// Reading the display is a runtime call the offline suite cannot make, so the
// helper it feeds is lifted out of the source and exercised on a plain object.
const helperFnStart = bubbleSrc.indexOf('function resolveBubbleContentWidth');
const helperFnEnd = bubbleSrc.indexOf('\n}', helperFnStart) + 2;
const helperCode = bubbleSrc.slice(bubbleSrc.indexOf('const BUBBLE_OUTER_PADDING'), helperFnEnd) +
  '\nreturn resolveBubbleContentWidth;';
const helperWidths = {};
try {
  // The lifted code keeps its ArkTS annotations, so it still needs transpiling.
  const helperJs = ts.transpileModule(helperCode, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
  }).outputText;
  const resolve = new Function('display', helperJs)({ getDefaultDisplaySync: () => ({ width: 1080 }) });
  // On every width the 75% cap still sits below the padding budget, so the cap
  // is what survives and the padding subtraction only matters for the fallback.
  helperWidths.vp360 = resolve({ px2vp: (px) => px / 3 });        // min(312, 270)
  helperWidths.vp412 = resolve({ px2vp: (px) => px / 2.625 });    // min(340, 309)
  helperWidths.vp480 = resolve({ px2vp: () => 480 });             // min(432, 360)
  helperWidths.noDisplay = resolve({ px2vp: () => { throw new Error('no display'); } });
  helperWidths.degenerateScreen = resolve({ px2vp: () => 100 });  // clamp, would be negative
  // The invariant the screenshot regression broke: the bubble (content + its own
  // padding) has to fit the width left over after the Row's padding. A content
  // width at or above the cap would push the text past the bubble again.
  helperWidths.fits412 = resolve({ px2vp: (px) => px / 2.625 }) + 24 <= 412 - 24;
  helperWidths.fits360 = resolve({ px2vp: (px) => px / 3 }) + 24 <= 360 - 24;
  helperWidths.fits480 = resolve({ px2vp: () => 480 }) + 24 <= 480 - 24;
} catch (e) {
  helperWidths.error = String(e);
}
check('G 静态', '气泡宽度助手：由窗口宽度算出确定 vp，display 不可用时仍有兜底',
  helperWidths.vp360 === 270 && helperWidths.vp412 === 309 && helperWidths.vp480 === 360 &&
  helperWidths.noDisplay === 240 && helperWidths.degenerateScreen === 96,
  helperWidths, { vp360: 270, vp412: 309, vp480: 360, noDisplay: 240, degenerateScreen: 96 });

check('G 静态', '气泡(内容宽度+自身内边距)始终放得进行宽（截图里文字比气泡宽 20% 的那条回归）',
  helperWidths.fits412 === true && helperWidths.fits360 === true && helperWidths.fits480 === true,
  { fits360: helperWidths.fits360, fits412: helperWidths.fits412, fits480: helperWidths.fits480 },
  { fits360: true, fits412: true, fits480: true });

check('G 静态', 'Markdown 根容器用宿主给的确定宽度（百分比会解析成父级约束宽度、撑破气泡）',
  markdownLogic.indexOf('resolveBubbleContentWidth') < 0 &&
  markdownSrc.split('@Component')[1].indexOf('.width(this.contentWidth)') >= 0 &&
  markdownSrc.indexOf('@Prop contentWidth') >= 0,
  { rootWidth: (markdownSrc.split('@Component')[1].match(/\.width\([^)]*\)/) || [''])[0] },
  { rootWidth: '.width(this.contentWidth)' });

// The regression that actually shipped: the bubble was capped at 309vp while
// the text inside it rendered 393vp wide. Bubble and text have to come from the
// one number, so neither can drift back to a percentage or an intrinsic measure.
const bubbleWidthLines = bubbleSrc.split('\n').filter(l => l.indexOf('.width(this.contentWidth)') >= 0);
check('G 静态', '气泡内每个内容分支都与气泡同宽（文字不会再比气泡宽）',
  bubbleWidthLines.length === 3 && bubbleSrc.indexOf('.width(this.contentWidth)') >= 0,
  { widthCalls: bubbleWidthLines.length },
  { widthCalls: 3 });

const storeSrc = fs.readFileSync(path.join(root, 'features/aiagent/src/main/ets/service/PracticeSessionStore.ets'), 'utf8');
check('G 静态', '练习会话交接保留错题记录链接（漏了会退化成重复追加）',
  storeSrc.indexOf('sourceRecordId') >= 0 && storeSrc.indexOf('syncedToErrorBook') >= 0,
  { sourceRecordId: storeSrc.indexOf('sourceRecordId') >= 0, synced: storeSrc.indexOf('syncedToErrorBook') >= 0 },
  { sourceRecordId: true, synced: true });

fs.writeFileSync(path.join(__dirname, 'ai_agent_p5_test_result.json'), JSON.stringify(results, null, 2));
console.log(`${results.length - failures}/${results.length} passed`);
process.exit(failures > 0 ? 1 : 0);

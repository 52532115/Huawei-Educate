// Offline tests for P6 方案 2: cumulative mastery + practice history.
//
// Groups A-C exercise PracticeHistoryStore on its own (pure logic, then the
// AppStorage/file round-trip). Later groups cover the service integration.
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

// Shared in-memory AppStorage + fileIo so store instances share state. Both must
// be globals: compiled modules run inside new Function and only see global scope.
const fileMap = new Map();
let lastOpenedPath = '';
let openSyncShouldThrow = false;
global.AppStorage = {
  data: new Map(),
  get(key) { return this.data.get(key); },
  setOrCreate(key, value) { this.data.set(key, value); },
};
global.fileIo = {
  readTextSync(p) { return fileMap.get(p) || ''; },
  openSync(p) {
    if (openSyncShouldThrow) {
      throw new Error('disk full');
    }
    lastOpenedPath = p;
    return { fd: 1 };
  },
  writeSync(fd, text) { fileMap.set(lastOpenedPath, text); },
  closeSync() {},
};

global.AppStorage.setOrCreate('filesDir', '/tmp/p6test');

// ---------- load the modules ----------

// The pure source module builds ErrorBookPracticeCandidate instances, so that
// model class has to be in its scope — imports are stripped before it runs.
global.__sourceModule = loadArkTs('features/aiagent/src/main/ets/service/ErrorBookPracticeSource.ets', `
const PracticeDifficulty = { BASIC: '基础', MEDIUM: '进阶', HARD: '挑战' };
class ErrorBookPracticeCandidate {
  constructor() {
    Object.assign(this, { recordId: '', title: '', normalizedTitle: '', options: [], correctIndex: -1,
      knowledgeTag: '', userNote: '', mistakeReason: '', analysis: '', createTime: 0, lastActivityTime: 0,
      repeatCount: 1, isDemo: false, score: 0, difficulty: PracticeDifficulty.BASIC });
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
`);
const sourceModule = global.__sourceModule;
const history = loadArkTs(
  'features/aiagent/src/main/ets/service/PracticeHistoryStore.ets',
  'const { reviewAgeLevel } = global.__sourceModule;');
const {
  PracticeHistoryStore, PracticeHistoryEntry,
  clampMastery, decayPenaltyForAgeLevel, masteryDecay, effectiveMasteryOf, nextStoredMastery,
  buildPracticeHistoryLine, buildHistorySummaryLine,
  DEFAULT_SEED_MASTERY, WEAK_MASTERY_THRESHOLD, MASTERY_CORRECT_GAIN, MASTERY_WRONG_LOSS,
} = history;

const HISTORY_KEY = 'PracticeHistory';

function freshStore() {
  global.AppStorage.data.delete(HISTORY_KEY);
  fileMap.clear();
  return new PracticeHistoryStore();
}

// ---------- A. decay table ----------

check('A 衰减档位', '未练习的档位递减：0 / 1天 / 3天 / 7天 / 14天 / 30天',
  masteryDecay(NOW, NOW) === 0 && masteryDecay(NOW - DAY, NOW) === 4 &&
  masteryDecay(NOW - 3 * DAY, NOW) === 8 && masteryDecay(NOW - 7 * DAY, NOW) === 12 &&
  masteryDecay(NOW - 14 * DAY, NOW) === 16 && masteryDecay(NOW - 30 * DAY, NOW) === 16,
  {
    d0: masteryDecay(NOW, NOW), d1: masteryDecay(NOW - DAY, NOW), d3: masteryDecay(NOW - 3 * DAY, NOW),
    d7: masteryDecay(NOW - 7 * DAY, NOW), d14: masteryDecay(NOW - 14 * DAY, NOW),
    d30: masteryDecay(NOW - 30 * DAY, NOW),
  },
  { d0: 0, d1: 4, d3: 8, d7: 12, d14: 16, d30: 16 });

check('A 衰减档位', '档位边界：1天差1毫秒仍是0档，13.9天仍是3档',
  masteryDecay(NOW - DAY + 1, NOW) === 0 && masteryDecay(NOW - Math.floor(13.9 * DAY), NOW) === 12,
  { justUnder1: masteryDecay(NOW - DAY + 1, NOW), d13_9: masteryDecay(NOW - Math.floor(13.9 * DAY), NOW) },
  { justUnder1: 0, d13_9: 12 });

check('A 衰减档位', '时钟回拨(lastPracticeTime 在未来)不衰减',
  masteryDecay(NOW + 5 * DAY, NOW) === 0,
  masteryDecay(NOW + 5 * DAY, NOW), 0);

check('A 衰减档位', '没有练习时间锚点(0 / 非法)不衰减',
  masteryDecay(0, NOW) === 0 && masteryDecay(-1, NOW) === 0 && masteryDecay(NaN, NOW) === 0,
  { zero: masteryDecay(0, NOW), neg: masteryDecay(-1, NOW), nan: masteryDecay(NaN, NOW) },
  { zero: 0, neg: 0, nan: 0 });

check('A 衰减档位', '有效掌握度 = 存储值 − 衰减，且钳在 [0,100]',
  effectiveMasteryOf(74, NOW - 30 * DAY, NOW) === 58 &&
  effectiveMasteryOf(5, NOW - 30 * DAY, NOW) === 0 &&
  effectiveMasteryOf(100, NOW, NOW) === 100,
  {
    decayed: effectiveMasteryOf(74, NOW - 30 * DAY, NOW),
    floored: effectiveMasteryOf(5, NOW - 30 * DAY, NOW),
    fresh: effectiveMasteryOf(100, NOW, NOW),
  },
  { decayed: 58, floored: 0, fresh: 100 });

check('A 衰减档位', '衰减表是显式 switch，越界档位按最强衰减兜底',
  decayPenaltyForAgeLevel(0) === 0 && decayPenaltyForAgeLevel(4) === 16 &&
  decayPenaltyForAgeLevel(9) === 16 && decayPenaltyForAgeLevel(-1) === 16,
  {
    l0: decayPenaltyForAgeLevel(0), l4: decayPenaltyForAgeLevel(4),
    l9: decayPenaltyForAgeLevel(9), lneg: decayPenaltyForAgeLevel(-1),
  },
  { l0: 0, l4: 16, l9: 16, lneg: 16 });

check('A 衰减档位', '与错题本共用同一套复习档位口径（旁证：30天→score 60、8天→45、今天→0）',
  sourceModule.reviewAgeLevel(30) === 4 && sourceModule.reviewAgeLevel(8) === 3 &&
  sourceModule.reviewAgeLevel(0.5) === 0,
  {
    d30: sourceModule.reviewAgeLevel(30), d8: sourceModule.reviewAgeLevel(8),
    d0_5: sourceModule.reviewAgeLevel(0.5),
  },
  { d30: 4, d8: 3, d0_5: 0 });

// ---------- B. write rule ----------

check('B 写入', '答对 +6、答错 −8',
  nextStoredMastery(68, true) === 74 && nextStoredMastery(74, false) === 66 &&
  MASTERY_CORRECT_GAIN === 6 && MASTERY_WRONG_LOSS === 8,
  { correct: nextStoredMastery(68, true), wrong: nextStoredMastery(74, false) },
  { correct: 74, wrong: 66 });

check('B 写入', '下限 0、上限 100（天花板吃掉增益是既定行为）',
  nextStoredMastery(4, false) === 0 && nextStoredMastery(98, true) === 100 &&
  nextStoredMastery(100, true) === 100,
  {
    floor: nextStoredMastery(4, false), nearCeiling: nextStoredMastery(98, true),
    atCeiling: nextStoredMastery(100, true),
  },
  { floor: 0, nearCeiling: 100, atCeiling: 100 });

// A non-finite value cannot be a real mastery, so it is discarded rather than
// clamped: satisfying Infinity as "100" would let one corrupt record report a
// knowledge point as fully mastered.
check('B 写入', 'clampMastery 钳住有限值，非有限值一律按 0 丢弃',
  clampMastery(42) === 42 && clampMastery(-5) === 0 && clampMastery(120) === 100 &&
  clampMastery(NaN) === 0 && clampMastery(Infinity) === 0 && clampMastery(-Infinity) === 0,
  {
    ok: clampMastery(42), neg: clampMastery(-5), over: clampMastery(120),
    nan: clampMastery(NaN), inf: clampMastery(Infinity), negInf: clampMastery(-Infinity),
  },
  { ok: 42, neg: 0, over: 100, nan: 0, inf: 0, negInf: 0 });

check('B 写入', '种子常量与旧启发式的首次错题值一致',
  DEFAULT_SEED_MASTERY === 68 && WEAK_MASTERY_THRESHOLD === 60,
  { seed: DEFAULT_SEED_MASTERY, weak: WEAK_MASTERY_THRESHOLD },
  { seed: 68, weak: 60 });

// ---------- C. persistence round-trip ----------

let store = freshStore();
let returned = store.recordAnswer('数据结构', true, NOW, DEFAULT_SEED_MASTERY);
check('C 存储往返', '首次作答以种子建条目：68 + 6 = 74，attempts 1',
  returned === 74 && store.getEntry('数据结构').mastery === 74 &&
  store.getEntry('数据结构').attempts === 1 && store.getEntry('数据结构').correct === 1,
  { returned, entry: store.getEntry('数据结构') },
  { returned: 74, mastery: 74, attempts: 1, correct: 1 });

check('C 存储往返', '作答即写入 AppStorage（不依赖会话结束）',
  typeof global.AppStorage.data.get(HISTORY_KEY) === 'string' &&
  global.AppStorage.data.get(HISTORY_KEY).indexOf('数据结构') >= 0,
  { written: typeof global.AppStorage.data.get(HISTORY_KEY) === 'string' },
  { written: true });

store.recordAnswer('数据结构', false, NOW + 1000, DEFAULT_SEED_MASTERY);
store.recordAnswer('数据结构', true, NOW + 2000, DEFAULT_SEED_MASTERY);
const afterThree = store.getEntry('数据结构');
check('C 存储往返', '三次作答累计：74 − 8 + 6 = 72，3 次 2 对，练习时间刷新',
  afterThree.mastery === 72 && afterThree.attempts === 3 && afterThree.correct === 2 &&
  afterThree.lastPracticeTime === NOW + 2000,
  afterThree,
  { mastery: 72, attempts: 3, correct: 2, lastPracticeTime: NOW + 2000 });

check('C 存储往返', '种子只在第一次用：后续作答不再回落到种子值',
  store.recordAnswer('数据结构', false, NOW + 3000, 10) === 64,
  store.getEntry('数据结构').mastery, 64);

const totals = store.getTotals();
check('C 存储往返', '合计值由条目派生',
  totals.attempts === 4 && totals.correct === 2 && totals.tags === 1 &&
  totals.lastPracticeTime === NOW + 3000,
  totals,
  { attempts: 4, correct: 2, tags: 1, lastPracticeTime: NOW + 3000 });

// App restart: AppStorage gone, file kept.
global.AppStorage.data.delete(HISTORY_KEY);
const restored = new PracticeHistoryStore();
check('C 存储往返', '重启后从文件恢复（清空 AppStorage，保留文件）',
  restored.getEntry('数据结构').mastery === 64 && restored.getEntry('数据结构').attempts === 4,
  restored.getEntry('数据结构'),
  { mastery: 64, attempts: 4 });

check('C 存储往返', '无历史的 tag：getEffectiveMastery 返回 −1，hasHistory false',
  restored.getEffectiveMastery('没练过', NOW) === -1 && restored.hasHistory('没练过') === false &&
  restored.getEntry('没练过').attempts === 0,
  {
    effective: restored.getEffectiveMastery('没练过', NOW),
    hasHistory: restored.hasHistory('没练过'),
  },
  { effective: -1, hasHistory: false });

check('C 存储往返', '空 tag / 非字符串 tag 被拒，不写入（返回 −1）',
  restored.recordAnswer('', true, NOW, DEFAULT_SEED_MASTERY) === -1 &&
  restored.recordAnswer('   ', true, NOW, DEFAULT_SEED_MASTERY) === -1 &&
  restored.getTotals().tags === 1,
  { empty: restored.recordAnswer('', true, NOW, 68), blank: restored.recordAnswer('  ', true, NOW, 68), tags: restored.getTotals().tags },
  { empty: -1, blank: -1, tags: 1 });

check('C 存储往返', '有效掌握度按衰减读取，但存储值不变（读不改状态）',
  restored.getEffectiveMastery('数据结构', NOW + 20 * DAY) === 64 - 16 &&
  restored.getEntry('数据结构').mastery === 64,
  {
    effective: restored.getEffectiveMastery('数据结构', NOW + 20 * DAY),
    stored: restored.getEntry('数据结构').mastery,
  },
  { effective: 48, stored: 64 });

check('C 存储往返', '损坏的 JSON 不抛异常，且仍可继续写入',
  (() => {
    global.AppStorage.data.set(HISTORY_KEY, 'not-json{{{');
    const broken = new PracticeHistoryStore();
    const emptyOnRead = broken.getTotals().tags === 0;
    const wrote = broken.recordAnswer('导数与微分', true, NOW, DEFAULT_SEED_MASTERY);
    return emptyOnRead && wrote === 74;
  })(),
  { recovered: true }, { recovered: true });

check('C 存储往返', '字段类型垃圾被逐条挡下（坏值不污染，好值照收）',
  (() => {
    global.AppStorage.data.set(HISTORY_KEY, JSON.stringify({
      version: 1,
      entries: [
        { tag: '好数据', mastery: 55, attempts: 4, correct: 2, lastPracticeTime: NOW },
        { tag: '坏mastery', mastery: 'x', attempts: 2, correct: 1, lastPracticeTime: NOW },
        { tag: '坏attempts', mastery: 50, attempts: -5, correct: 0, lastPracticeTime: NOW },
        { tag: '零作答', mastery: 50, attempts: 0, correct: 0, lastPracticeTime: NOW },
        { tag: '', mastery: 50, attempts: 1, correct: 0, lastPracticeTime: NOW },
        { tag: '好数据', mastery: 99, attempts: 9, correct: 9, lastPracticeTime: NOW },
        { tag: '正确数超出', mastery: 50, attempts: 2, correct: 7, lastPracticeTime: NOW },
        { tag: '时间非法', mastery: 50, attempts: 1, correct: 0, lastPracticeTime: null },
      ],
    }));
    // Survive: 好数据(4 due to the duplicate row being dropped), 坏mastery(2),
    // 正确数超出(2), 时间非法(1) = 4 entries / 9 attempts.
    // Dropped: 坏attempts(-5) and 零作答(0) have no valid attempts, '' has no tag.
    const s = new PracticeHistoryStore();
    const t = s.getTotals();
    const corrupt = s.getEntry('坏mastery');
    const overflow = s.getEntry('正确数超出');
    const badTime = s.getEntry('时间非法');
    return t.tags === 4 && t.attempts === 9 &&
      corrupt.mastery === DEFAULT_SEED_MASTERY &&
      s.getEntry('好数据').mastery === 55 && s.getEntry('好数据').attempts === 4 &&
      overflow.correct === 2 && badTime.lastPracticeTime === 0 && badTime.attempts === 1 &&
      s.hasHistory('坏attempts') === false && s.hasHistory('零作答') === false;
  })(),
  (() => {
    const s = new PracticeHistoryStore();
    return { tags: s.getTotals().tags, attempts: s.getTotals().attempts, corruptMastery: s.getEntry('坏mastery').mastery };
  })(),
  { tags: 4, attempts: 9, corruptMastery: 68 });

check('C 存储往返', '没有 filesDir 时只走 AppStorage，不抛异常',
  (() => {
    global.AppStorage.data.delete('filesDir');
    try {
      const s = new PracticeHistoryStore();
      const wrote = s.recordAnswer('无目录', true, NOW, DEFAULT_SEED_MASTERY);
      global.AppStorage.setOrCreate('filesDir', '/tmp/p6test');
      return wrote === 74 && s.getEntry('无目录').mastery === 74;
    } catch (e) {
      global.AppStorage.setOrCreate('filesDir', '/tmp/p6test');
      return false;
    }
  })(),
  { ok: true }, { ok: true });

check('C 存储往返', '文件写入失败时仍返回新值，不打断练习',
  (() => {
    const s = freshStore();
    openSyncShouldThrow = true;
    let wrote;
    try {
      wrote = s.recordAnswer('写盘失败', false, NOW, DEFAULT_SEED_MASTERY);
    } finally {
      openSyncShouldThrow = false;
    }
    return wrote === 60;
  })(),
  { returned: 60 }, { returned: 60 });

check('C 存储往返', '超过 60 条时淘汰最久未练的，且绝不淘汰刚写入的那条',
  (() => {
    const s = freshStore();
    for (let i = 0; i < 61; i++) {
      s.recordAnswer(`知识点${i}`, true, NOW + i * 1000, DEFAULT_SEED_MASTERY);
    }
    const t = s.getTotals();
    const newestKept = s.hasHistory('知识点60');
    const oldestGone = s.hasHistory('知识点0');
    // The eviction must pair "oldest dropped" with "newest kept" — an earlier
    // revision dropped the second-newest instead while still returning 60 rows,
    // which the count alone would not have caught.
    const survivorCount = (() => {
      let n = 0;
      for (let i = 0; i < 61; i++) {
        if (s.hasHistory(`知识点${i}`)) {
          n += 1;
        }
      }
      return n;
    })();
    // Deterministic: the same sequence twice yields the same survivors.
    const s2 = freshStore();
    for (let i = 0; i < 61; i++) {
      s2.recordAnswer(`知识点${i}`, true, NOW + i * 1000, DEFAULT_SEED_MASTERY);
    }
    let same = s2.getTotals().tags === t.tags;
    for (let i = 0; i < 61; i++) {
      if (s2.hasHistory(`知识点${i}`) !== s.hasHistory(`知识点${i}`)) {
        same = false;
      }
    }
    return t.tags === 60 && survivorCount === 60 && newestKept && !oldestGone && same;
  })(),
  (() => {
    const s = freshStore();
    for (let i = 0; i < 61; i++) {
      s.recordAnswer(`知识点${i}`, true, NOW + i * 1000, DEFAULT_SEED_MASTERY);
    }
    let survivors = 0;
    for (let i = 0; i < 61; i++) {
      if (s.hasHistory(`知识点${i}`)) {
        survivors += 1;
      }
    }
    return { tags: s.getTotals().tags, survivors, oldestKept: s.hasHistory('知识点0'), newestKept: s.hasHistory('知识点60') };
  })(),
  { tags: 60, survivors: 60, oldestKept: false, newestKept: true });

// ---------- D-G, I. service integration ----------
//
// The service is loaded against the real history store and the real learner
// profile store, so these exercise the actual wiring rather than a fake.

global.__snapshot = { examScores: [], errorQuestions: [], courseProgress: [], totalStudyTime: 0 };

// Both loaded for real: the service constructs them as field initialisers, so a
// missing class here is an immediate "not a constructor" for the whole file.
global.__historyModule = history;
global.__profileModule = loadArkTs('features/aiagent/src/main/ets/service/LearnerProfileStore.ets',
  'const Logger = { error() {}, info() {} };');

function servicePrelude() {
  return `
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
// The service constructs its own ErrorBookPracticeSource, so that class's model
// dependency has to be in this scope too — not just in the outer test file.
class ErrorBookPracticeCandidate {
  constructor() {
    Object.assign(this, { recordId: '', title: '', normalizedTitle: '', options: [], correctIndex: -1,
      knowledgeTag: '', userNote: '', mistakeReason: '', analysis: '', createTime: 0, lastActivityTime: 0,
      repeatCount: 1, isDemo: false, score: 0, difficulty: PracticeDifficulty.BASIC });
  }
}
global.ErrorQuestionItem = ErrorQuestionItem;
global.AdaptivePracticeQuestion = AdaptivePracticeQuestion;

const { ErrorBookPracticeSource, normalizeQuestionTitle, normalizeKnowledgeTag } = global.__sourceModule;
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

function loadService() {
  // Fresh module instance so each scenario starts from a clean service.
  return loadArkTs('features/aiagent/src/main/ets/service/AdaptivePracticeService.ets', servicePrelude());
}

/** Clears history + profile + error book, keeping the file map in step. */
function resetWorld() {
  global.AppStorage.data.delete(HISTORY_KEY);
  global.AppStorage.data.delete('LearnerProfile');
  global.AppStorage.data.delete('ErrorQuestions');
  fileMap.clear();
}

// D1 — with no history every profile keeps its seed, ordered weakest first.
resetWorld();
global.__snapshot = { examScores: [], errorQuestions: [], courseProgress: [], totalStudyTime: 0 };
let service = new (loadService().AdaptivePracticeService)();
let session = service.generateSession(6, NOW);
check('D 选择顺序', '冷启动按掌握度升序（默认画像：网络68 → 数据结构70 → 操作系统72）',
  session.profiles.length === 3 && session.profiles.map(p => p.tag).join('|') === '计算机网络|数据结构|操作系统' &&
  session.profiles.map(p => p.mastery).join('|') === '68|70|72',
  session.profiles.map(p => `${p.tag}:${p.mastery}`),
  ['计算机网络:68', '数据结构:70', '操作系统:72']);

check('D 选择顺序', '画像层出的题来自最弱的知识点',
  session.questions[0].knowledgeTag === '计算机网络',
  session.questions[0].knowledgeTag, '计算机网络');

// D2 — a course profile with progress 40 keeps its seeded value until practiced.
global.__snapshot = {
  examScores: [], courseProgress: [{ name: '操作系统', progress: 40 }], errorQuestions: [], totalStudyTime: 0,
};
service = new (loadService().AdaptivePracticeService)();
session = service.generateSession(6, NOW);
check('D 选择顺序', '课程进度不再压顶：只有一条课程画像时它仍按种子值 40 排在最前',
  session.profiles[0].tag === '操作系统' && session.profiles[0].mastery === 40,
  session.profiles.map(p => `${p.tag}:${p.mastery}`),
  '操作系统:40 first');

// D3 — answering shifts the order.
resetWorld();
global.__snapshot = { examScores: [], errorQuestions: [], courseProgress: [], totalStudyTime: 0 };
service = new (loadService().AdaptivePracticeService)();
session = service.generateSession(6, NOW);
const osQuestion = session.questions.filter(q => q.knowledgeTag === '操作系统')[0];
service.submitAnswer(osQuestion, (osQuestion.correctIndex + 1) % osQuestion.options.length, NOW + 1000);
service.submitAnswer(osQuestion, (osQuestion.correctIndex + 1) % osQuestion.options.length, NOW + 2000);
check('D 选择顺序', '同一题重复提交只计一次（masteryRecorded 守卫）',
  service.historyStore.getEntry('操作系统').attempts === 1,
  service.historyStore.getEntry('操作系统').attempts, 1);

// 操作系统 seeds at 72 (not the generic 68), so a wrong answer lands it on 64 —
// still below 计算机网络's 68 and 数据结构's 70, which is what reorders the list.
session = service.generateSession(6, NOW + 3000);
check('D 选择顺序', '答错后该知识点升到最前（72 − 8 = 64，低于另两个种子）',
  session.profiles[0].tag === '操作系统' && session.profiles[0].mastery === 64 &&
  session.questions[0].knowledgeTag === '操作系统',
  session.profiles.map(p => `${p.tag}:${p.mastery}`),
  '操作系统:64 first');

// D4 — answering correctly pushes a knowledge point down.
resetWorld();
service = new (loadService().AdaptivePracticeService)();
session = service.generateSession(6, NOW);
const netQuestion = session.questions.filter(q => q.knowledgeTag === '计算机网络')[0];
service.submitAnswer(netQuestion, netQuestion.correctIndex, NOW + 1000);
session = service.generateSession(6, NOW + 2000);
check('D 选择顺序', '答对后该知识点沉到最底（68 + 6 = 74，高于另两个种子）',
  session.profiles[2].tag === '计算机网络' && session.profiles[2].mastery === 74 &&
  session.profiles.map(p => p.tag).join('|') === '数据结构|操作系统|计算机网络',
  session.profiles.map(p => `${p.tag}:${p.mastery}`),
  '计算机网络:74 last');

// D5 — decay reorders without any new answer.
resetWorld();
service = new (loadService().AdaptivePracticeService)();
session = service.generateSession(6, NOW);
const dsQuestion = session.questions.filter(q => q.knowledgeTag === '数据结构')[0];
service.submitAnswer(dsQuestion, dsQuestion.correctIndex, NOW);
const freshOrder = service.generateSession(6, NOW).profiles.map(p => `${p.tag}:${p.mastery}`);
const decayedOrder = service.generateSession(6, NOW + 15 * DAY).profiles.map(p => `${p.tag}:${p.mastery}`);
check('D 选择顺序', '时间衰减把久未练的知识点重新推到前面（70 + 6 = 76，15 天后衰减到 60）',
  freshOrder[2] === '数据结构:76' && decayedOrder[0] === '数据结构:60',
  { fresh: freshOrder, after15Days: decayedOrder },
  { fresh: '数据结构 last at 76', after15Days: '数据结构 first at 60' });

// D6 — the error-book layer still outranks everything.
resetWorld();
global.__snapshot = {
  examScores: [], courseProgress: [], totalStudyTime: 0,
  errorQuestions: [0, 1, 2, 3, 4, 5].map(i => ({
    id: `err_${i}`, title: `错题${i}`, category: '数据结构',
    options: ['A选项', 'B选项', 'C选项', 'D选项'], correctIndex: 1, userIndex: 0,
    userNote: '', mistakeReason: '', createTime: NOW - i * DAY, analysis: '', wrongCount: 1, lastReviewTime: 0,
  })),
};
service = new (loadService().AdaptivePracticeService)();
session = service.generateSession(6, NOW);
check('D 选择顺序', '错题本仍是第一出题源（6 道错题占满整组）',
  session.questions.length === 6 && session.questions.every(q => q.id.indexOf('q_err_') === 0),
  session.questions.map(q => q.id), '6 error-book questions');

// E — cold start writes nothing, first answer persists, abandonment keeps it.
resetWorld();
global.__snapshot = { examScores: [], errorQuestions: [], courseProgress: [], totalStudyTime: 0 };
service = new (loadService().AdaptivePracticeService)();
service.generateSession(6, NOW);
check('E 冷启动/抛弃', 'generateSession 不写任何历史（种子只在作答时落盘）',
  global.AppStorage.data.get(HISTORY_KEY) === undefined && fileMap.size === 0,
  { appStorage: global.AppStorage.data.get(HISTORY_KEY) === undefined, files: fileMap.size },
  { appStorage: true, files: 0 });

session = service.generateSession(6, NOW);
const seedQuestion = session.questions[0];
service.submitAnswer(seedQuestion, seedQuestion.correctIndex, NOW + 1000);
check('E 冷启动/抛弃', '第一次作答从启发式种子起步（68 + 6 = 74，attempts 1）',
  service.historyStore.getEntry(seedQuestion.knowledgeTag).mastery === 74 &&
  service.historyStore.getEntry(seedQuestion.knowledgeTag).attempts === 1,
  service.historyStore.getEntry(seedQuestion.knowledgeTag),
  { mastery: 74, attempts: 1 });

// The session is abandoned here: buildSummary is never called.
const abandonedService = new (loadService().AdaptivePracticeService)();
check('E 冷启动/抛弃', '中途放弃会话后掌握度仍在（新实例从盘上读到）',
  abandonedService.historyStore.getEntry(seedQuestion.knowledgeTag).mastery === 74,
  abandonedService.historyStore.getEntry(seedQuestion.knowledgeTag),
  { mastery: 74, attempts: 1 });

// F — answering a bank question wrong once adds exactly one error-book record.
resetWorld();
global.__snapshot = { examScores: [], errorQuestions: [], courseProgress: [], totalStudyTime: 0 };
service = new (loadService().AdaptivePracticeService)();
session = service.generateSession(6, NOW);
const bankQuestion = session.questions.filter(q => q.sourceRecordId === '')[0];
service.submitAnswer(bankQuestion, (bankQuestion.correctIndex + 1) % bankQuestion.options.length, NOW);
const errorBookAfterOne = JSON.parse(global.AppStorage.data.get('ErrorQuestions') || '[]');
service.submitAnswer(bankQuestion, (bankQuestion.correctIndex + 1) % bankQuestion.options.length, NOW + 1000);
const errorBookAfterTwo = JSON.parse(global.AppStorage.data.get('ErrorQuestions') || '[]');
check('F 幂等', '重复提交同一题：掌握度不重复计、错题本不重复追加',
  service.historyStore.getEntry(bankQuestion.knowledgeTag).attempts === 1 &&
  errorBookAfterOne.length === 1 && errorBookAfterTwo.length === 1,
  {
    attempts: service.historyStore.getEntry(bankQuestion.knowledgeTag).attempts,
    afterOne: errorBookAfterOne.length, afterTwo: errorBookAfterTwo.length,
  },
  { attempts: 1, afterOne: 1, afterTwo: 1 });

// G — the weakest knowledge points reach the learner profile and survive analysis.
resetWorld();
global.__snapshot = { examScores: [], errorQuestions: [], courseProgress: [], totalStudyTime: 0 };
service = new (loadService().AdaptivePracticeService)();
session = service.generateSession(6, NOW);
// 计算机网络 seeds at 68; each wrong answer is −8, and the weak threshold is
// strictly below 60 — so it takes two answers to get to 52. The second answer
// comes from the next session, which is also the case that matters in practice.
let weakQuestion = session.questions.filter(q => q.knowledgeTag === '计算机网络')[0];
service.submitAnswer(weakQuestion, (weakQuestion.correctIndex + 1) % weakQuestion.options.length, NOW + 1000);
session = service.generateSession(6, NOW + 2000);
weakQuestion = session.questions.filter(q => q.knowledgeTag === '计算机网络')[0];
service.submitAnswer(weakQuestion, (weakQuestion.correctIndex + 1) % weakQuestion.options.length, NOW + 3000);
const profileStore = new (global.__profileModule.LearnerProfileStore)();
const practiced = profileStore.loadProfile();
check('G 档案联动', '掌握度跌破阈值后写进档案（weakPoints 与 practiceWeakPoints 都含它）',
  practiced.weakPoints.indexOf('计算机网络') >= 0 &&
  practiced.practiceWeakPoints.indexOf('计算机网络') >= 0,
  { weakPoints: practiced.weakPoints, practiceWeakPoints: practiced.practiceWeakPoints },
  { contains: '计算机网络' });

profileStore.updateFromAnalysis({
  weakPoints: ['高等数学', '线性代数'], strengths: ['数据结构'], totalExams: 2, avgScore: 80, totalStudyTime: 3600,
});
const afterAnalysis = profileStore.loadProfile();
check('G 档案联动', '学习分析不会抹掉练习派生的弱点（两个来源合流）',
  afterAnalysis.weakPoints.indexOf('计算机网络') >= 0 &&
  afterAnalysis.weakPoints.indexOf('高等数学') >= 0,
  afterAnalysis.weakPoints,
  'contains both 计算机网络 and 高等数学');

profileStore.updateFromAnalysis({
  weakPoints: ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'].map((t, i) => `弱点${t}`),
  strengths: [], totalExams: 1, avgScore: 70, totalStudyTime: 1000,
});
const capped = profileStore.loadProfile();
check('G 档案联动', '8 个分析弱点 + 1 个练习弱点 → 仍为 8 个，且练习项在列',
  capped.weakPoints.length === 8 && capped.weakPoints.indexOf('计算机网络') >= 0,
  capped.weakPoints,
  '8 entries incl. 计算机网络');

check('G 档案联动', '档案 prompt 带上练习派生的薄弱点',
  profileStore.buildProfilePrompt().indexOf('计算机网络') >= 0,
  profileStore.buildProfilePrompt().indexOf('计算机网络') >= 0, true);

// I — the same inputs and the same `now` produce the same session.
resetWorld();
global.__snapshot = { examScores: [], errorQuestions: [], courseProgress: [], totalStudyTime: 0 };
service = new (loadService().AdaptivePracticeService)();
const firstRun = service.generateSession(6, NOW);
const secondRun = service.generateSession(6, NOW);
check('I 确定性', '同输入同 now → 题目 id 序列、画像值与顺序完全一致',
  firstRun.questions.map(q => q.id).join('|') === secondRun.questions.map(q => q.id).join('|') &&
  firstRun.profiles.map(p => `${p.tag}:${p.mastery}`).join('|') ===
  secondRun.profiles.map(p => `${p.tag}:${p.mastery}`).join('|'),
  { first: firstRun.questions.map(q => q.id), second: secondRun.questions.map(q => q.id) },
  'identical');

check('I 确定性', '占位题 id 使用注入的 now，不再读系统时钟',
  service.generateSession(6, NOW).questions.filter(q => q.id.indexOf('q_custom_') >= 0)
    .every(q => q.id.indexOf(String(NOW)) >= 0) ||
  service.generateSession(6, NOW).questions.filter(q => q.id.indexOf('q_custom_') >= 0).length === 0,
  service.generateSession(6, NOW).questions.map(q => q.id).filter(id => id.indexOf('q_custom_') >= 0),
  'no clock reads');

// ---------- H. copy and static checks ----------

check('H 文案与静态', '练习历史行：没练过返回空串，练过则含次数/正确率/时间',
  buildPracticeHistoryLine(0, 0, 0, NOW) === '' &&
  buildPracticeHistoryLine(6, 4, NOW, NOW) === '已练 6 次 · 正确 4 次（67%）· 今天练过' &&
  buildPracticeHistoryLine(6, 4, NOW - 3 * DAY, NOW) === '已练 6 次 · 正确 4 次（67%）· 3 天前练过',
  {
    none: buildPracticeHistoryLine(0, 0, 0, NOW),
    today: buildPracticeHistoryLine(6, 4, NOW, NOW),
    days: buildPracticeHistoryLine(6, 4, NOW - 3 * DAY, NOW),
  },
  { none: '', today: '已练 6 次 · 正确 4 次（67%）· 今天练过', days: '已练 6 次 · 正确 4 次（67%）· 3 天前练过' });

check('H 文案与静态', '累计统计行：无记录有引导文案，有记录含总量与覆盖率',
  buildHistorySummaryLine(0, 0, 0).indexOf('还没有累计练习记录') >= 0 &&
  buildHistorySummaryLine(42, 31, 9) === '累计练习 42 题 · 正确 31 题（74%）· 覆盖 9 个知识点',
  { none: buildHistorySummaryLine(0, 0, 0), some: buildHistorySummaryLine(42, 31, 9) },
  { none: '还没有累计练习记录…', some: '累计练习 42 题 · 正确 31 题（74%）· 覆盖 9 个知识点' });

function stripArkTsComments(source) {
  return source.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
}
const storeSrc = stripArkTsComments(fs.readFileSync(
  path.join(root, 'features/aiagent/src/main/ets/service/PracticeHistoryStore.ets'), 'utf8'));

check('H 文案与静态', 'store 自身不读时钟、不用随机数（now 全程注入）',
  storeSrc.indexOf('Date.now') < 0 && storeSrc.indexOf('Math.random') < 0,
  { now: storeSrc.indexOf('Date.now') >= 0, random: storeSrc.indexOf('Math.random') >= 0 },
  { now: false, random: false });

check('H 文案与静态', 'store 双写：AppStorage + 文件',
  storeSrc.indexOf('AppStorage.setOrCreate(PRACTICE_HISTORY_KEY') >= 0 &&
  storeSrc.indexOf('fileIo.openSync') >= 0 && storeSrc.indexOf('fileIo.writeSync') >= 0,
  {
    appStorage: storeSrc.indexOf('AppStorage.setOrCreate(PRACTICE_HISTORY_KEY') >= 0,
    file: storeSrc.indexOf('fileIo.openSync') >= 0,
  },
  { appStorage: true, file: true });

check('H 文案与静态', '衰减表复用错题本的 reviewAgeLevel，没有第二份档位表',
  storeSrc.indexOf('reviewAgeLevel') >= 0 &&
  storeSrc.indexOf('ageDays < 3') < 0 && storeSrc.indexOf('ageDays < 7') < 0,
  { usesShared: storeSrc.indexOf('reviewAgeLevel') >= 0, ownTable: storeSrc.indexOf('ageDays <') >= 0 },
  { usesShared: true, ownTable: false });

const serviceSrc = stripArkTsComments(fs.readFileSync(
  path.join(root, 'features/aiagent/src/main/ets/service/AdaptivePracticeService.ets'), 'utf8'));
check('H 文案与静态', '出题按掌握度升序（weakest first），错题本层仍在前面',
  serviceSrc.indexOf('a.mastery - b.mastery') >= 0 &&
  serviceSrc.indexOf('buildQuestions(snapshot.errorQuestions, questionCount, now, excludeIds)') >= 0 &&
  serviceSrc.indexOf('this.historyStore.recordAnswer') >= 0 &&
  serviceSrc.indexOf('recordPracticeWeakPoints') >= 0,
  {
    ascending: serviceSrc.indexOf('a.mastery - b.mastery') >= 0,
    errorBookFirst: serviceSrc.indexOf('buildQuestions(snapshot.errorQuestions') >= 0,
    recordsAnswer: serviceSrc.indexOf('this.historyStore.recordAnswer') >= 0,
    linksProfile: serviceSrc.indexOf('recordPracticeWeakPoints') >= 0,
  },
  { ascending: true, errorBookFirst: true, recordsAnswer: true, linksProfile: true });

check('H 文案与静态', '服务端不再自带第二套乱码判定（tag 归一化只有一处）',
  serviceSrc.indexOf('containsMojibake') < 0 && serviceSrc.indexOf('normalizeKnowledgeTag(item.category)') >= 0,
  { localGuard: serviceSrc.indexOf('containsMojibake') >= 0 },
  { localGuard: false });

const viewSrc = stripArkTsComments(fs.readFileSync(
  path.join(root, 'features/aiagent/src/main/ets/components/AdaptivePracticeView.ets'), 'utf8'));
check('H 文案与静态', '练习页渲染累计统计（重点面板 + 总结页）',
  viewSrc.indexOf('buildHistorySummaryLine(') >= 0 && viewSrc.indexOf('PracticeHistoryTotals') >= 0 &&
  viewSrc.indexOf('historyWeakTags.length > 0') >= 0,
  {
    summaryLine: viewSrc.indexOf('buildHistorySummaryLine(') >= 0,
    totals: viewSrc.indexOf('PracticeHistoryTotals') >= 0,
    weakLine: viewSrc.indexOf('historyWeakTags.length > 0') >= 0,
  },
  { summaryLine: true, totals: true, weakLine: true });

// ---------- report ----------

fs.writeFileSync(path.join(__dirname, 'ai_agent_p6_test_result.json'), JSON.stringify(results, null, 2));
console.log(`${results.length - failures}/${results.length} passed`);
process.exit(failures > 0 ? 1 : 0);

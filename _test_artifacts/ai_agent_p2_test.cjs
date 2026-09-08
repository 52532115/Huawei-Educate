// Offline tests for P2: LearnerProfileStore (cross-session learner memory),
// tool write-back (get_learning_stats / analyze_error_book / generate_practice),
// and the new get_learner_profile tool.
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

// Shared in-memory AppStorage + fileIo so store instances share state.
// Both must be globals: compiled modules run inside `new Function` and only
// see the global scope.
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

const storePrelude = `
const Logger = { error() {}, info() {} };
`;
const storeMod = loadArkTs(
  'features/aiagent/src/main/ets/service/LearnerProfileStore.ets',
  storePrelude,
);
const store = new storeMod.LearnerProfileStore();

function makeAnalysis(weakPoints, strengths, exams, avg, studyTime) {
  return {
    totalExams: exams, avgScore: avg, totalStudyTime: studyTime,
    scoreTrend: [], knowledgePoints: [], courseProgress: [],
    weakPoints: weakPoints, strengths: strengths,
  };
}

// ---------- LearnerProfileStore: prompt building ----------
check('档案prompt', '空档案返回空串', store.buildProfilePrompt() === '', store.buildProfilePrompt(), '');

store.updateFromAnalysis(makeAnalysis(['函数与极限', '导数应用'], ['三角函数'], 3, 82, 450));
let prompt = store.buildProfilePrompt();
check('档案prompt', '包含薄弱点', prompt.indexOf('函数与极限') >= 0 && prompt.indexOf('导数应用') >= 0, prompt, 'weak points present');
check('档案prompt', '包含优势', prompt.indexOf('三角函数') >= 0, prompt, 'strength present');
check('档案prompt', '包含成绩概况', prompt.indexOf('3 次考试') >= 0 && prompt.indexOf('82 分') >= 0, prompt, 'exam stats present');
check('档案prompt', '包含累计时长', prompt.indexOf('450 分钟') >= 0, prompt, 'study time present');

// ---------- LearnerProfileStore: clamping ----------
store.updateFromAnalysis(makeAnalysis(
  ['a1','a2','a3','a4','a5','a6','a7','a8','a9','a10'],
  ['s1','s2','s3','s4','s5','s6','s7'],
  0, 0, 0,
));
prompt = store.buildProfilePrompt();
check('档案prompt', '薄弱点截断为8个', prompt.indexOf('a9') < 0 && prompt.indexOf('a8') >= 0, prompt, 'clamped at 8');
check('档案prompt', '优势截断为5个', prompt.indexOf('s6') < 0 && prompt.indexOf('s5') >= 0, prompt, 'clamped at 5');

// ---------- LearnerProfileStore: focus topics ----------
function countOccurrences(text, sub) {
  return text.split(sub).length - 1;
}
global.AppStorage.data.clear();
store.recordFocusTopics(['导数计算', '极限证明', '导数计算']);
prompt = store.buildProfilePrompt();
check('关注主题', '去重合并', countOccurrences(prompt, '导数计算') === 1 && prompt.indexOf('极限证明') >= 0, prompt, 'deduped');
store.recordFocusTopics(['t1','t2','t3','t4','t5','t6']);
prompt = store.buildProfilePrompt();
check('关注主题', '上限6个', prompt.indexOf('t4') >= 0 && prompt.indexOf('t5') < 0 && prompt.indexOf('t6') < 0, prompt, 'capped at 6');

// ---------- LearnerProfileStore: analysis summaries ----------
global.AppStorage.data.clear();
store.recordAnalysisSummary('太短'); // < 20 chars, ignored
let profile = store.loadProfile();
check('分析摘要', '过短内容被忽略', profile.analysisSummaries.length === 0, profile.analysisSummaries.length, 0);
const longText = '导数是重要概念'.repeat(50); // 350 chars
store.recordAnalysisSummary(longText);
profile = store.loadProfile();
check('分析摘要', '单条截断为200字', profile.analysisSummaries.length === 1 && profile.analysisSummaries[0].length === 200, profile.analysisSummaries[0].length, 200);
store.recordAnalysisSummary('第二条分析结论，关于函数极限的复习建议');
store.recordAnalysisSummary('第三条分析结论，关于三角函数公式的掌握情况');
store.recordAnalysisSummary('第四条分析结论，关于定积分计算的方法总结');
profile = store.loadProfile();
check('分析摘要', '只保留最近3条', profile.analysisSummaries.length === 3 &&
  profile.analysisSummaries[0].length === 200 &&
  profile.analysisSummaries[1].indexOf('第三条') >= 0 &&
  profile.analysisSummaries[2].indexOf('第四条') >= 0 &&
  profile.analysisSummaries[0].indexOf('第二条') < 0, JSON.stringify(profile.analysisSummaries), 'kept last 3');
check('分析摘要', '注入prompt含结论', store.buildProfilePrompt().indexOf('第四条分析结论') >= 0, store.buildProfilePrompt(), 'summaries in prompt');

// ---------- LearnerProfileStore: round-trip & corrupt data ----------
global.AppStorage.data.clear();
global.AppStorage.setOrCreate('filesDir', '/tmp/p2test');
store.updateFromAnalysis(makeAnalysis(['回写弱点'], [], 2, 90, 60));
global.AppStorage.data.clear(); // simulate app restart: only the file remains
global.AppStorage.setOrCreate('filesDir', '/tmp/p2test');
const store2 = new storeMod.LearnerProfileStore();
const restored = store2.loadProfile();
check('持久化', '重启后从文件恢复', restored.weakPoints.length === 1 && restored.weakPoints[0] === '回写弱点' && restored.examCount === 2, JSON.stringify(restored), 'restored from file');
global.AppStorage.data.set('LearnerProfile', 'not-json{{{');
const corrupt = store2.loadProfile();
check('持久化', '损坏数据返回空档案不崩溃', corrupt.weakPoints.length === 0 && corrupt.examCount === 0, JSON.stringify(corrupt), 'empty profile');

// ---------- LearnerProfileStore: clearProfile ----------
store2.clearProfile();
const afterClear = store2.loadProfile();
check('重置', 'clearProfile后档案为空', afterClear.weakPoints.length === 0 && afterClear.examCount === 0 && afterClear.analysisSummaries.length === 0, JSON.stringify(afterClear), 'empty profile');

// ---------- SessionStore: action round-trip (P2.5) ----------
global.AppStorage.data.clear();
global.AppStorage.setOrCreate('filesDir', '/tmp/p2test');
const sessionPrelude = `
class ChatMessage {
  constructor(id, role, content, status, analysisData) {
    this.id = id; this.role = role; this.content = content; this.status = status;
    this.timestamp = Date.now(); this.analysisData = analysisData;
  }
}
class ChatSession {
  constructor(id, title) {
    this.id = id; this.title = title; this.messages = [];
    this.createTime = Date.now(); this.updateTime = Date.now();
  }
}
const MessageRole = { USER: 'user', AI: 'ai', SYSTEM: 'system', ANALYSIS: 'analysis', STEP: 'step' };
const MessageStatus = { SENDING: 'sending', SUCCESS: 'success', FAILED: 'failed' };
const Logger = { error() {}, info() {} };
`;
const sessionMod = loadArkTs(
  'features/aiagent/src/main/ets/service/SessionStore.ets',
  sessionPrelude,
);
const sessionStore = new sessionMod.SessionStore();
// Plain objects suffice: SessionStore only reads fields, and recordToSession
// rebuilds ChatMessage instances via the prelude classes.
const testSession = {
  id: 's1', title: '练习',
  createTime: 123, updateTime: 123,
  messages: [
    { id: 'm1', role: 'user', content: '帮我出几道练习题', timestamp: 123, status: 'success' },
    { id: 'm2', role: 'ai', content: '已生成练习题，点击下方按钮开始吧！', timestamp: 123, status: 'success', action: 'start_practice' },
    { id: 'm3', role: 'step', content: '正在生成练习题…', timestamp: 123, status: 'success' },
  ],
};
sessionStore.saveSessions([testSession]);
global.AppStorage.data.clear(); // simulate restart: only the file remains
global.AppStorage.setOrCreate('filesDir', '/tmp/p2test');
const restoredSessions = new sessionMod.SessionStore().loadSessions();
check('会话action', '重启后恢复且action保留', restoredSessions.length === 1 && restoredSessions[0].messages.length === 2 &&
  restoredSessions[0].messages[1].action === 'start_practice', JSON.stringify(restoredSessions.map(s => s.messages.map(m => ({ role: m.role, action: m.action })))), 'action survives restart');
check('会话action', 'STEP消息不落盘', restoredSessions.length === 1 && restoredSessions[0].messages.every(m => m.role !== 'step'), JSON.stringify(restoredSessions[0].messages.map(m => m.role)), 'no step messages');

// ---------- AgentTools integration: real LearnerProfileStore + service stubs ----------
global.AppStorage.data.clear();
const toolsPrelude = `
const Logger = { error() {}, info() {} };
class DataCollectService {
  collectAllData() { return { examScores: [], errorQuestions: [], courseProgress: [], totalStudyTime: 120 }; }
  analyzeData(s) { return makeAnalysisReal(); }
}
function makeAnalysisReal() {
  return { totalExams: 4, avgScore: 78, totalStudyTime: 120, scoreTrend: [], knowledgePoints: [], courseProgress: [], weakPoints: ['函数与极限', '导数应用'], strengths: ['三角函数'] };
}
class ErrorAttributionService { updateErrorBookAttributions() { return 2; } }
class AdaptivePracticeService { generateSession(n) { return { questions: [{ title: '导数计算' }, { title: '极限证明' }] }; } }
class PracticeSessionStore { savePendingSession() {} }
class AiMessage { constructor() { this.role = ''; this.content = ''; } }
class AiToolCall { constructor() { this.id = ''; this.type = 'function'; this.function = new AiToolCallFunction(); } }
class AiToolCallFunction { constructor() { this.name = ''; this.arguments = ''; } }
${transpileArkTs('features/aiagent/src/main/ets/service/LearnerProfileStore.ets')}
`;
const agentTools = loadArkTs(
  'features/aiagent/src/main/ets/service/AgentTools.ets',
  toolsPrelude,
);

const tools = agentTools.buildToolDefinitions();
check('工具定义', '共7个且包含get_learner_profile', tools.length === 7 && tools.some(t => t.function.name === 'get_learner_profile'), tools.map(t => t.function.name).join(','), '7 tools with profile');
check('步骤文案', 'get_learner_profile有文案', typeof agentTools.getToolStepLabel('get_learner_profile') === 'string' && agentTools.getToolStepLabel('get_learner_profile').length > 0, agentTools.getToolStepLabel('get_learner_profile'), 'label');

const registry = new agentTools.AgentToolRegistry();
(async () => {
  const statsJson = await registry.execute('get_learning_stats', '{}');
  const stats = JSON.parse(statsJson);
  check('工具执行', 'get_learning_stats返回分析JSON', typeof stats.totalExams === 'number', statsJson, 'has totalExams');
  // Write-back: the real store (shared AppStorage) must now carry the analysis.
  const promptAfterStats = new storeMod.LearnerProfileStore().buildProfilePrompt();
  check('档案回写', 'get_learning_stats后档案含薄弱点', promptAfterStats.indexOf('函数与极限') >= 0 && promptAfterStats.indexOf('78 分') >= 0, promptAfterStats, 'profile updated');

  const profileJson = await registry.execute('get_learner_profile', '{}');
  const profilePayload = JSON.parse(profileJson);
  check('工具执行', 'get_learner_profile返回档案字段', Array.isArray(profilePayload.weakPoints) && profilePayload.weakPoints.indexOf('函数与极限') >= 0 && profilePayload.examCount === 4, profileJson, 'profile payload');

  await registry.execute('generate_practice', '{}');
  const promptAfterPractice = new storeMod.LearnerProfileStore().buildProfilePrompt();
  check('档案回写', 'generate_practice后档案含练习主题', promptAfterPractice.indexOf('导数计算') >= 0 && promptAfterPractice.indexOf('极限证明') >= 0, promptAfterPractice, 'focus topics recorded');

  report();
})();

function report() {
  fs.writeFileSync(path.join(__dirname, 'ai_agent_p2_test_result.json'), JSON.stringify(results, null, 2));
  console.log(`${results.length - failures}/${results.length} passed`);
  process.exit(failures > 0 ? 1 : 0);
}

const fs = require('fs');
const path = require('path');
const ts = require('D:/devecostudio-windows-6.0.2.650/DevEco Studio/tools/hvigor/hvigor/node_modules/typescript');

const root = path.resolve(__dirname, '..');
const results = [];

function check(group, name, condition, actual, expected) {
  results.push({
    group,
    name,
    status: condition ? 'PASS' : 'FAIL',
    actual,
    expected,
  });
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

const commonPrelude = `
const ErrorCauseType = {
  CONCEPT: 'concept', FORMULA: 'formula', METHOD: 'method',
  CALCULATION: 'calculation', CARELESS: 'careless', UNKNOWN: 'unknown'
};
class ErrorAttributionResult {
  constructor(causeType, causeLabel, confidence, evidence, remediation, nextAction) {
    Object.assign(this, { causeType, causeLabel, confidence, evidence, remediation, nextAction });
  }
}
const fileIo = { readTextSync() { return ''; }, openSync() { return { fd: 1 }; }, writeSync() {}, closeSync() {} };
global.AppStorage = global.AppStorage || {
  data: new Map(),
  get(key) { return this.data.get(key); },
  setOrCreate(key, value) { this.data.set(key, value); }
};
`;

const { ErrorAttributionService } = loadArkTs(
  'features/aiagent/src/main/ets/service/ErrorAttributionService.ets',
  commonPrelude,
);
const attribution = new ErrorAttributionService();

const attributionCases = [
  ['概念线索', ['题目', '极限', '概念混淆', '', 'B', 'A'], 'concept'],
  ['公式线索', ['题目', '导数', '公式使用错误', '', 'B', 'A'], 'formula'],
  ['方法线索', ['题目', '积分', '解题步骤不完整', '', 'B', 'A'], 'method'],
  ['计算线索', ['题目', '代数', '计算算错', '', 'B', 'A'], 'calculation'],
  ['粗心线索', ['题目', '网络', '看错题干', '', 'B', 'A'], 'careless'],
  ['仅答案不同', ['题目', '操作系统', '', '', 'B', 'A'], 'method'],
  ['知识点名称不参与原因判断', ['题目', '计算机网络', '', '', '', ''], 'unknown'],
  ['信息不足', ['题目', '未分类', '', '', '', ''], 'unknown'],
];

for (const [name, args, expected] of attributionCases) {
  const output = attribution.diagnoseByFields(...args);
  check('错题归因', name, output.causeType === expected, output.causeType, expected);
}

const dataPrelude = `
const fileIo = { readTextSync() { return ''; } };
const MineCourseList = [];
class MineCourseListModel {}
class LearningAnalysisData {}
class LearningDataSnapshot {}
class ScoreTrendItem { constructor(examName, score, date) { Object.assign(this, { examName, score, date }); } }
class KnowledgePoint { constructor(name, mastery, total, correct) { Object.assign(this, { name, mastery, total, correct }); } }
class CourseProgressItem { constructor(courseName, progress, teacher) { Object.assign(this, { courseName, progress, teacher }); } }
class ExamScoreItem { constructor(name, score, date) { Object.assign(this, { name, score, date }); } }
class ErrorQuestionItem {
  constructor(title, category) {
    Object.assign(this, { title, category, options: [], correctIndex: -1, userIndex: -1,
      correctLabel: '', userLabel: '', userNote: '', mistakeReason: '', createTime: 0 });
  }
}
class CourseProgressDataItem { constructor(name, progress, teacher) { Object.assign(this, { name, progress, teacher }); } }
class KnowledgeStats { constructor(total, correct) { Object.assign(this, { total, correct }); } }
global.AppStorage = {
  data: new Map(),
  get(key) { return this.data.get(key); },
  setOrCreate(key, value) { this.data.set(key, value); }
};
`;

const { DataCollectService } = loadArkTs(
  'features/aiagent/src/main/ets/service/DataCollectService.ets',
  dataPrelude,
);
const dataService = new DataCollectService();
global.AppStorage.data.set('ExamHistory', JSON.stringify([
  { name: '第一次考试', score: 88, date: '2026-07-15', duration: 60000, timestamp: 1 },
]));
global.AppStorage.data.set('ErrorQuestions', JSON.stringify([
  { title: '极限题', knowledgeTag: '函数与极限', option: ['0', '1'], rightQues: 1, answer: 0,
    userNote: '需复习', mistakeReason: '概念混淆', createTime: 1 },
]));
global.AppStorage.data.set('CourseProgress', JSON.stringify([
  { name: '数据结构', progress: 68, teacher: '张教授' },
]));
global.AppStorage.data.set('TotalStudyTimeMinutes', 120);
const snapshot = dataService.collectAllData();
check('学习数据', '读取真实考试分数', snapshot.examScores.length === 1 && snapshot.examScores[0].score === 88,
  snapshot.examScores.map((item) => item.score), [88]);
check('学习数据', '读取错题答案标签', snapshot.errorQuestions[0].correctLabel === 'B' && snapshot.errorQuestions[0].userLabel === 'A',
  `${snapshot.errorQuestions[0].userLabel}->${snapshot.errorQuestions[0].correctLabel}`, 'A->B');
check('学习数据', '平均分计算', dataService.analyzeData(snapshot).avgScore === 88,
  dataService.analyzeData(snapshot).avgScore, 88);
check('学习数据', '课程进度来自真实数据', snapshot.courseProgress.length === 1 &&
  snapshot.courseProgress[0].name === '数据结构' && snapshot.courseProgress[0].progress === 68,
  snapshot.courseProgress, [{ name: '数据结构', progress: 68, teacher: '张教授' }]);
check('学习数据', '学习时长来自真实数据', snapshot.totalStudyTime === 120,
  snapshot.totalStudyTime, 120);

const repeatedMastery = new Set();
for (let i = 0; i < 50; i += 1) {
  repeatedMastery.add(dataService.analyzeData(snapshot).knowledgePoints[0].mastery);
}
check('学习数据', '同一输入分析结果确定性', repeatedMastery.size === 1,
  [...repeatedMastery].sort((a, b) => a - b), '唯一固定结果');

global.AppStorage.data = new Map();
const emptySnapshot = dataService.collectAllData();
check('学习数据', '无成绩时不伪造考试历史', emptySnapshot.examScores.length === 0,
  emptySnapshot.examScores.map((item) => item.score), []);

const adaptivePrelude = `
const PracticeDifficulty = { BASIC: '基础', MEDIUM: '进阶', HARD: '挑战' };
class AdaptivePracticeQuestion {
  constructor(id, title, options, correctIndex, knowledgeTag, difficulty, source, explanation, recommendation) {
    Object.assign(this, { id, title, options, correctIndex, knowledgeTag, difficulty, source, explanation,
      recommendation, selectedIndex: -1, isSubmitted: false, syncedToErrorBook: false });
  }
}
class KnowledgePracticeProfile {
  constructor(tag, errorCount, mastery, priority, reason) { Object.assign(this, { tag, errorCount, mastery, priority, reason }); }
}
class PracticeSessionSummary {
  constructor() { Object.assign(this, { totalCount: 0, correctCount: 0, score: 0, weakTags: [], masteredTags: [], advice: '', generatedAt: Date.now() }); }
}
class AdaptivePracticeSession {
  constructor(id, questions, profiles) { Object.assign(this, { id, questions, profiles, summary: new PracticeSessionSummary() }); }
}
class DataCollectService {
  collectAllData() { return { examScores: [], errorQuestions: [], courseProgress: [], totalStudyTime: 0 }; }
}
class ErrorAttributionService {
  diagnosePracticeQuestion() { return { causeLabel: '测试归因', confidence: 80, remediation: '复习', evidence: '答错' }; }
}
const fileIo = { readTextSync() { return ''; }, openSync() { return { fd: 1 }; }, writeSync() {}, closeSync() {} };
global.AppStorage = {
  data: new Map(), get(key) { return this.data.get(key); }, setOrCreate(key, value) { this.data.set(key, value); }
};
`;

const { AdaptivePracticeService } = loadArkTs(
  'features/aiagent/src/main/ets/service/AdaptivePracticeService.ets',
  adaptivePrelude,
);
const practice = new AdaptivePracticeService();
const session = practice.generateSession();
check('自适应练习', '默认生成6题', session.questions.length === 6, session.questions.length, 6);
check('自适应练习', '题目ID不重复', new Set(session.questions.map((q) => q.id)).size === session.questions.length,
  new Set(session.questions.map((q) => q.id)).size, session.questions.length);
check('自适应练习', '无画像时建立默认薄弱画像', session.profiles.length === 3,
  session.profiles.map((p) => p.tag), ['数据结构', '操作系统', '计算机网络']);

practice.submitAnswer(session.questions[0], session.questions[0].correctIndex);
check('自适应练习', '正确答案提交状态', session.questions[0].isSubmitted && !session.questions[0].attribution,
  { submitted: session.questions[0].isSubmitted, attribution: session.questions[0].attribution || null },
  { submitted: true, attribution: null });

const wrong = session.questions[1];
practice.submitAnswer(wrong, (wrong.correctIndex + 1) % wrong.options.length);
const firstErrorBook = JSON.parse(global.AppStorage.data.get('ErrorQuestions'));
practice.submitAnswer(wrong, (wrong.correctIndex + 1) % wrong.options.length);
const secondErrorBook = JSON.parse(global.AppStorage.data.get('ErrorQuestions'));
check('自适应练习', '答错生成归因并写入错题本', Boolean(wrong.attribution) && wrong.syncedToErrorBook && firstErrorBook.length === 1,
  { attributed: Boolean(wrong.attribution), synced: wrong.syncedToErrorBook, count: firstErrorBook.length },
  { attributed: true, synced: true, count: 1 });
check('自适应练习', '重复提交不重复写错题', secondErrorBook.length === 1, secondErrorBook.length, 1);

for (let i = 2; i < session.questions.length; i += 1) {
  const q = session.questions[i];
  practice.submitAnswer(q, i < 4 ? q.correctIndex : (q.correctIndex + 1) % q.options.length);
}
const summary = practice.buildSummary(session);
check('自适应练习', '汇总正确数', summary.correctCount === 3, summary.correctCount, 3);
check('自适应练习', '汇总分数四舍五入', summary.score === 50, summary.score, 50);

const staticFiles = {
  constants: fs.readFileSync(path.join(root, 'features/aiagent/src/main/ets/utils/AiConstants.ets'), 'utf8'),
  aiService: fs.readFileSync(path.join(root, 'features/aiagent/src/main/ets/service/AiService.ets'), 'utf8'),
  chatViewModel: fs.readFileSync(path.join(root, 'features/aiagent/src/main/ets/viewmodel/ChatViewModel.ets'), 'utf8'),
  chatBubble: fs.readFileSync(path.join(root, 'features/aiagent/src/main/ets/components/ChatBubble.ets'), 'utf8'),
  photo: fs.readFileSync(path.join(root, 'features/aiagent/src/main/ets/components/PhotoSearchView.ets'), 'utf8'),
};

check('接口与安全', '模型接口使用HTTPS', /AI_API_URL[^\n]+https:\/\//.test(staticFiles.constants), 'HTTPS', 'HTTPS');
check('接口与安全', '客户端不内嵌API密钥', !/API_KEY[^\n]+['"]sk-/.test(staticFiles.constants),
  '发现客户端硬编码密钥', '密钥仅保存在可信后端');
check('接口与安全', '图片后端使用HTTPS', /PHOTO_SEARCH_BACKEND_URL\s*=\s*['"]https:\/\//.test(staticFiles.photo),
  'HTTP 明文地址', 'HTTPS');
check('接口与安全', 'AI请求启用流式响应', /new AiApiRequest\([\s\S]*?messages,\s*true\s*,?\s*\)/.test(staticFiles.aiService),
  'stream=false', 'stream=true/SSE');
check('接口与安全', '超时重试已实现', /MAX_RETRY_COUNT/.test(staticFiles.aiService) && /(for|while)\s*\(/.test(staticFiles.aiService),
  '仅定义常量，服务无重试循环', '最多3次重试');
check('接口与安全', '取消请求会销毁连接', /cancelRequest\(\)[\s\S]*?destroy\(\)/.test(staticFiles.aiService),
  'destroy()', 'destroy()');
check('可靠性', '普通问答失败有友好提示', /暂时无法回复/.test(staticFiles.chatViewModel),
  '存在友好提示', '存在友好提示');
check('功能符合性', 'Markdown内容被解析渲染', /Markdown(Parser|Text)|RichEditor/.test(staticFiles.chatBubble),
  '直接使用 Text 渲染', 'Markdown解析/渲染');
check('功能符合性', '图片文件类型随原图传输', !/filename="image\.jpg"[\s\S]*?Content-Type: image\/jpeg/.test(staticFiles.photo),
  '所有图片声明为 JPEG', '保留真实 MIME/扩展名');
check('资源管理', '图片文件描述符会关闭', /closeSync\(this\.imageFd\)/.test(staticFiles.photo),
  '未关闭 imageFd', '使用后或页面退出时关闭');

const targeted = process.argv.includes('--targeted');
const evaluatedResults = targeted ?
  results.filter((item) => item.group === '错题归因' || item.group === '学习数据') : results;
const passed = evaluatedResults.filter((item) => item.status === 'PASS').length;
const failed = evaluatedResults.filter((item) => item.status === 'FAIL').length;
console.log(JSON.stringify({
  mode: targeted ? 'targeted' : 'full',
  summary: { total: evaluatedResults.length, passed, failed },
  results: evaluatedResults,
}, null, 2));
process.exitCode = failed === 0 ? 0 : 1;

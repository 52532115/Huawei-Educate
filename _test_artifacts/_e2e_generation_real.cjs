/*
 * 端到端跑通「RAG + LLM 出题」——走**生产**代码路径，不是脚本自己拼 prompt。
 *
 * 与 p8 的分工：
 *   - p8 用桩替换模型与检索，证明的是**契约**（提示词怎么写、回复怎么解析、
 *     缓存怎么失效、失败怎么粘住），跑得快、不花钱、可反复跑。
 *   - 这个脚本证明的是**通路**：真讲义语料 → 真 `searchBest` 检索 → 真
 *     `buildPrompt` → 真 http → 本机后端 → DeepSeek → 真回复 → 真
 *     `parseResponse` → 真入池 → 下一组练习真的用上。中间没有任何一处由脚本
 *     代替生产代码决定。
 *
 * 唯一的替换是 `@ohos.net.http`：Node 里没有这个模块，桩把它接到真的 `fetch`。
 * 请求体、请求头、URL、重试、响应解析全部由 `AiService` 自己产出——桩只搬字节。
 * 这也正是 `_e2e_dense_real.cjs` 对待嵌入代理的方式。
 *
 * 花钱的地方只有一次出题调用（约 1100 token，几秒钟）。向量侧刻意不接，理由见
 * 下面「后端注入」一节。
 *
 * 用法：
 *   node _test_artifacts/_e2e_generation_real.cjs
 *   node _test_artifacts/_e2e_generation_real.cjs --base http://10.0.0.5:8787
 *   node _test_artifacts/_e2e_generation_real.cjs --tag 三次握手   # 换一个知识点
 */
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const LOG_PATH = path.join(__dirname, '_e2e_generation_run.log');
const captured = [];
const rawLog = console.log.bind(console);
console.log = (...args) => {
  captured.push(args.map((a) => (typeof a === 'string' ? a : JSON.stringify(a))).join(' '));
  rawLog(...args);
};
process.on('exit', () => {
  try {
    fs.writeFileSync(LOG_PATH, captured.join('\n') + '\n');
  } catch (e) { /* 留证失败不该改退出码 */ }
});

function loadTypeScript() {
  const vendored = 'D:/devecostudio-windows-6.0.2.650/DevEco Studio/tools/hvigor/hvigor/node_modules/typescript';
  if (fs.existsSync(vendored)) {
    return require(vendored);
  }
  return require('typescript');
}

const ts = loadTypeScript();

function transpileArkTs(relativePath) {
  const filePath = path.join(ROOT, relativePath);
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

const SERVICE_DIR = 'features/aiagent/src/main/ets/service/';

let passed = 0;
let failed = 0;
function check(name, condition, actual, expected) {
  console.log(`${condition ? 'ok  ' : 'FAIL'} ${name}`);
  if (condition) {
    passed += 1;
  } else {
    failed += 1;
    console.log(`       actual  : ${JSON.stringify(actual)}`);
    console.log(`       expected: ${JSON.stringify(expected)}`);
  }
}
function section(title) {
  console.log('');
  console.log(title);
}

// ---------- 后端配置 ----------
function readEnvFile(envPath) {
  const out = {};
  if (!fs.existsSync(envPath)) {
    return out;
  }
  const text = fs.readFileSync(envPath, 'utf8').replace(/^\uFEFF/, '');
  for (const rawLine of text.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (line.length === 0 || line.charAt(0) === '#') {
      continue;
    }
    const eq = line.indexOf('=');
    if (eq <= 0) {
      continue;
    }
    out[line.slice(0, eq).trim()] = line.slice(eq + 1).trim();
  }
  return out;
}

const env = readEnvFile(path.join(ROOT, 'server', '.env'));
const APP_TOKEN = env.APP_TOKEN || '';
const PORT = env.PORT || '8787';
const baseIndex = process.argv.indexOf('--base');
const BASE = ((baseIndex >= 0 ? process.argv[baseIndex + 1] : '') || `http://127.0.0.1:${PORT}`).replace(/\/+$/, '');
const tagIndex = process.argv.indexOf('--tag');
const TAG = tagIndex >= 0 ? process.argv[tagIndex + 1] : '三次握手';

if (APP_TOKEN.length === 0) {
  console.error('server/.env 里没有 APP_TOKEN —— 后端若开了鉴权，这一趟只会得到 401。');
  process.exit(2);
}

// ---------- 设备侧环境桩 ----------
// 同一份桩喂给 AiBackend / KnowledgeIndexStore / GeneratedQuestionPool：真机上这
// 三者看到的是同一个 filesDir 和同一套设置。
global.__envStub = { files: {}, dirs: {}, opens: 0, closes: 0 };
const SNAPSHOT_PATH = '/data/files/knowledgeIndex.json';
const POOL_PATH = '/data/files/generatedQuestions.json';
const ENV_STUB = `
const __env = global.__envStub;
const AppStorage = {
  get(key) { return __env.dirs[key]; },
  setOrCreate(key, value) { __env.dirs[key] = value; },
};
const fileIo = {
  readTextSync(p) { if (!(p in __env.files)) { throw new Error('ENOENT'); } return __env.files[p]; },
  openSync(p, flags) { __env.files[p] = ''; __env.opens++; return { fd: p }; },
  writeSync(fd, data) { __env.files[fd] = (__env.files[fd] || '') + data; return data.length; },
  closeSync(file) { __env.closes++; },
  unlinkSync(p) { if (!(p in __env.files)) { throw new Error('ENOENT'); } delete __env.files[p]; },
};
`;
global.__envStub.dirs.filesDir = '/data/files';

// ---------- 后端注入：为什么 AppStorage 里没有后端地址 ----------
//
// 真机上后端地址由设置面板写进 AppStorage，`AiBackend.current()` 再把它解析出来。
// 这个脚本不走那一步，而是把同一个 `AiBackend` 从 `AiService` 的构造函数注入 ——
// 那是它自己公开的注入口（注释写明「tests, and any caller that wants to pin a
// mode」），路由、请求头、模型名仍然全部由生产代码决定。
//
// 理由只有一个：**让向量侧保持关闭**。`KnowledgeStore.searchBest` 一旦看到「已
// 配置的嵌入器」就会在后台把 243 块讲义全嵌一遍（约 6.2 万 token，见
// `_e2e_dense_real.cjs`），而那是另一条链路的开销，与本脚本要证的出题通路无关。
// AppStorage 里没有地址 → `KnowledgeProxyEmbedder.current()` 未配置 → 纯词法检索，
// 一次嵌入请求都不会发。下面第 1、2 段各有一条断言盯着这件事。
const backendMod = loadArkTs(`${SERVICE_DIR}AiBackend.ets`,
  `${ENV_STUB}\nconst Logger = { error() {}, info() {}, warn() {}, debug() {} };`);
global.__aiBackendModule = backendMod;
const backendForChat = new backendMod.AiBackend(BASE, APP_TOKEN);

// ---------- 模型类的桩（ArkTS 的 import 被剥掉，模块只看得到自己的作用域） ----------
const MODEL_STUB = `
const PracticeDifficulty = { BASIC: '基础', MEDIUM: '进阶', HARD: '挑战' };
const KnowledgeSourceType = { COURSE: 'course', QUESTION_BANK: 'question_bank',
  ERROR_BOOK: 'error_book', COURSE_NOTE: 'course_note' };
class AdaptivePracticeQuestion {
  constructor(id, title, options, correctIndex, knowledgeTag, difficulty, source, explanation, recommendation,
    sourceRecordId = '') {
    Object.assign(this, { id, title, options, correctIndex, knowledgeTag, difficulty, source, explanation,
      recommendation, selectedIndex: -1, isSubmitted: false, syncedToErrorBook: false, sourceRecordId,
      masteryRecorded: false, citation: '' });
  }
}
class PracticeSessionSummary {
  constructor() {
    Object.assign(this, { totalCount: 0, correctCount: 0, score: 0, weakTags: [], masteredTags: [],
      advice: '', generatedAt: 0, historyAttempts: 0, historyCorrect: 0, historyTags: 0, historyWeakTags: [] });
  }
}
class AdaptivePracticeSession {
  constructor(id, questions, profiles) {
    Object.assign(this, { id, questions, profiles, summary: new PracticeSessionSummary() });
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
class KnowledgePracticeProfile {
  constructor(tag, errorCount, mastery, priority, reason) {
    Object.assign(this, { tag, errorCount, mastery, priority, reason, attempts: 0, correct: 0, lastPracticeTime: 0 });
  }
}
class KnowledgeDocument {
  constructor() {
    Object.assign(this, { docId: '', title: '', courseId: '', knowledgeTag: '',
      sourceType: KnowledgeSourceType.COURSE_NOTE, text: '' });
  }
}
class KnowledgeChunk {
  constructor() {
    Object.assign(this, { chunkId: '', docId: '', title: '', headingPath: '', courseId: '',
      knowledgeTag: '', sourceType: KnowledgeSourceType.COURSE_NOTE, text: '', chunkIndex: 0 });
  }
}
class KnowledgeHit {
  constructor() { Object.assign(this, { chunk: new KnowledgeChunk(), score: 0, matchedTerms: [], retriever: 'bm25' }); }
}
class KnowledgeIndexStats {
  constructor() { Object.assign(this, { chunkCount: 0, termCount: 0, avgChunkLength: 0 }); }
}
class KnowledgeIndexState {
  constructor() { Object.assign(this, { chunkLengths: [], averageLength: 0, terms: [], postings: [] }); }
}
class KnowledgeSnapshot {
  constructor() {
    Object.assign(this, { version: 0, fingerprint: '', signature: '', vectorSignature: '',
      chunks: [], state: new KnowledgeIndexState(), vectors: [] });
  }
}
class SeedCourseInput {
  constructor() { Object.assign(this, { courseId: '', title: '', category: '', description: '', tags: [], outline: [] }); }
}
class SeedLectureInput {
  constructor() {
    Object.assign(this, { courseId: '', title: '', category: '', knowledgeTag: '', markdown: '', body: '' });
  }
}
class SeedQuestionInput {
  constructor() {
    Object.assign(this, { questionId: '', title: '', options: [], correctIndex: -1,
      knowledgeTag: '', explanation: '', recommendation: '' });
  }
}
class AiMessage { constructor() { this.role = ''; this.content = ''; } }
global.AdaptivePracticeQuestion = AdaptivePracticeQuestion;
global.AdaptivePracticeSession = AdaptivePracticeSession;
global.PracticeDifficulty = PracticeDifficulty;
global.KnowledgePracticeProfile = KnowledgePracticeProfile;
`;

// ---------- 真 HTTP 桩 ----------
// p8 用固定 JSON 回答，因此只能证明**解析**得对。这里换成真的 fetch，于是下面这条
// 链路第一次被真正走过：
//   service.synthesizeFor → AiService.chat → http.request → POST /chat/completions
//   → 服务端带厂商密钥转 DeepSeek → 选择题 JSON 回到客户端 → 解析 → 入池。
global.__chatLog = [];
global.__embedLog = [];
const CHAT_HTTP = `
const __log = global.__chatLog;
const http = {
  RequestMethod: { POST: 'POST', GET: 'GET' },
  HttpDataType: { STRING: 0 },
  createHttp() {
    return {
      async request(url, options) {
        const started = Date.now();
        const entry = { url, status: 0, ms: 0, userPrompt: '', systemPrompt: '', error: '', contentChars: 0 };
        try {
          const body = JSON.parse(options.extraData);
          const messages = body.messages;
          const last = messages[messages.length - 1];
          const first = messages[0];
          entry.userPrompt = last && typeof last.content === 'string' ? last.content : '';
          entry.systemPrompt = first && typeof first.content === 'string' ? first.content : '';
        } catch (e) { /* 记空串，断言会抓到 */ }
        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), 90000);
        try {
          const response = await fetch(url, {
            method: options.method,
            headers: options.header,
            body: options.extraData,
            signal: controller.signal,
          });
          const text = await response.text();
          entry.status = response.status;
          entry.ms = Date.now() - started;
          try {
            const parsed = JSON.parse(text);
            const choice = parsed.choices && parsed.choices[0];
            const content = choice && choice.message ? choice.message.content : '';
            entry.contentChars = typeof content === 'string' ? content.length : 0;
          } catch (e) { /* 非 JSON 也要能落进日志 */ }
          __log.push(entry);
          return { responseCode: response.status, result: text };
        } catch (error) {
          entry.ms = Date.now() - started;
          entry.error = error && error.message ? error.message : String(error);
          __log.push(entry);
          throw error;
        } finally {
          clearTimeout(timer);
        }
      },
      destroy() {},
      on() {},
      off() {},
    };
  },
};
`;

// 嵌入侧单独一份计数日志：本次应当**一条都没有**。有了它，「没花钱」才是被断言的，
// 而不是被相信的。
const EMBED_HTTP = `
const __embedLog = global.__embedLog;
const http = {
  RequestMethod: { POST: 'POST' },
  HttpDataType: { STRING: 0 },
  createHttp() {
    return {
      async request(url, options) {
        const entry = { url, status: 0, inputs: -1, error: '' };
        try { entry.inputs = JSON.parse(options.extraData).inputs.length; } catch (e) { }
        try {
          const response = await fetch(url, { method: options.method, headers: options.header, body: options.extraData });
          const text = await response.text();
          entry.status = response.status;
          __embedLog.push(entry);
          return { responseCode: response.status, result: text };
        } catch (error) {
          entry.error = error && error.message ? error.message : String(error);
          __embedLog.push(entry);
          throw error;
        }
      },
      destroy() {},
    };
  },
};
const Logger = { info() {}, warn() {}, error() {}, debug() {} };
`;

// ---------- 合成器 / 缓存池：全是真的 ----------
const sourceMod = loadArkTs(`${SERVICE_DIR}ErrorBookPracticeSource.ets`, MODEL_STUB);
global.__sourceModule = sourceMod;

const synthMod = loadArkTs(`${SERVICE_DIR}PracticeQuestionSynthesizer.ets`,
  `${MODEL_STUB}\nconst { isCorruptedText, normalizeKnowledgeTag, normalizeQuestionTitle, stableTextHash } = global.__sourceModule;`);
global.__synthModule = synthMod;

const poolMod = loadArkTs(`${SERVICE_DIR}GeneratedQuestionPool.ets`,
  `${ENV_STUB}\n${MODEL_STUB}\nconst SOURCE_AI_GENERATED = '${synthMod.SOURCE_AI_GENERATED}';
const SYNTHESIS_CONTRACT_VERSION = ${synthMod.SYNTHESIS_CONTRACT_VERSION};
const SYNTHESIS_QUESTION_COUNT = ${synthMod.SYNTHESIS_QUESTION_COUNT};`);
global.__poolModule = poolMod;

// ---------- AiService：真的那个 ----------
const aiModule = loadArkTs(`${SERVICE_DIR}AiService.ets`, `
${ENV_STUB}
${MODEL_STUB}
${CHAT_HTTP}
const AiBackend = global.__aiBackendModule.AiBackend;
function describeBackendProbe() { return new BackendProbeResult(false, '', ''); }
const PROBE_NOT_CONFIGURED = -2;
const PROBE_TOKEN_NOT_RUN = -1;
class BackendProbeResult {
  constructor(ok, title, detail) { this.ok = ok; this.title = title; this.detail = detail; }
}
const util = { TextDecoder: { create() { return { decodeToString(u8) { return Buffer.from(u8).toString('utf8'); } }; } } };
const Logger = { error() {}, info() {}, warn() {}, debug() {} };
const AiConstants = {
  AI_API_URL: 'https://api.test/v1/chat/completions',
  AI_MODEL: 'unused-in-backend-mode',
  REQUEST_TIMEOUT: 90000,
  MAX_RETRY_COUNT: 1,
};
class ApiKeyStore {
  getKey() { return ''; }
  isConfigured() { return false; }
}
class AiResponseResult { constructor() { this.content = ''; this.toolCalls = []; } }
class AiToolCall { constructor() { this.id = ''; this.type = 'function'; this.function = new AiToolCallFunction(); } }
class AiToolCallFunction { constructor() { this.name = ''; this.arguments = ''; } }
class AiApiRequest { constructor(model, messages, stream) { this.model = model; this.messages = messages; this.stream = stream; } }
`);
global.__aiModule = aiModule;

// ---------- 讲义语料：真的 chunker / index / 讲义 ----------
// 每一段 prelude 照抄 `_e2e_dense_real.cjs`（那边已验证过缺什么会炸）。
const SHARED_DEPS = `
const { isCorruptedText, normalizeKnowledgeTag, normalizeQuestionTitle } = global.__sourceModule;
`;

global.__codecModule = loadArkTs(`${SERVICE_DIR}KnowledgeSnapshotCodec.ets`, MODEL_STUB);
global.__chunkerModule = loadArkTs(`${SERVICE_DIR}KnowledgeChunker.ets`, `${SHARED_DEPS}\n${MODEL_STUB}`);
global.__indexModule = loadArkTs(`${SERVICE_DIR}KnowledgeIndex.ets`,
  `${MODEL_STUB}\nconst { hashString } = global.__codecModule;`);
global.__corpusModule = loadArkTs(`${SERVICE_DIR}KnowledgeSeedCorpus.ets`, `${SHARED_DEPS}\n${MODEL_STUB}`);
global.__catalogModule = loadArkTs(`${SERVICE_DIR}KnowledgeCourseCatalog.ets`, `${SHARED_DEPS}\n${MODEL_STUB}`);
global.__embeddingModule = loadArkTs(`${SERVICE_DIR}KnowledgeEmbedding.ets`,
  `${MODEL_STUB}\nconst { tokenizeWithUnigrams } = global.__indexModule;\nconst { hashString } = global.__codecModule;`);
global.__vectorModule = loadArkTs(`${SERVICE_DIR}KnowledgeVectorRetriever.ets`,
  `${MODEL_STUB}\nconst { cosineSimilarity } = global.__embeddingModule;`);
global.__notesSupport = loadArkTs(`${SERVICE_DIR}KnowledgeNotesSupport.ets`, MODEL_STUB);

const noteFiles = fs.readdirSync(path.join(ROOT, SERVICE_DIR)).filter((f) =>
  /^KnowledgeNotes.*\.ets$/.test(f) && f !== 'KnowledgeNotesCatalog.ets' && f !== 'KnowledgeNotesSupport.ets');
let catalogPrelude = `${MODEL_STUB}\n`;
global.__noteBuilders = {};
for (const file of noteFiles) {
  const noteModule = loadArkTs(`${SERVICE_DIR}${file}`,
    `const { makeLecture } = global.__notesSupport;\n${MODEL_STUB}`);
  const builderName = Object.keys(noteModule).find((key) => /^build.*Notes$/.test(key));
  if (!builderName) {
    throw new Error(`no note builder exported by ${file}`);
  }
  global.__noteBuilders[builderName] = noteModule[builderName];
  catalogPrelude += `const ${builderName} = global.__noteBuilders['${builderName}'];\n`;
}
global.__notesCatalogModule = loadArkTs(`${SERVICE_DIR}KnowledgeNotesCatalog.ets`, catalogPrelude);

global.__liveIndexStoreModule = loadArkTs(`${SERVICE_DIR}KnowledgeIndexStore.ets`,
  `${ENV_STUB}\nconst { encodeSnapshot, decodeSnapshot } = global.__codecModule;\n${MODEL_STUB}`);
global.__proxyModule = loadArkTs(`${SERVICE_DIR}KnowledgeEmbeddingProxy.ets`,
  `${MODEL_STUB}\nconst { KnowledgeEmbeddingBatch } = global.__embeddingModule;\n` +
  `const { RRF_DEFAULT_VECTOR_WEIGHT, RRF_REMOTE_VECTOR_WEIGHT } = global.__vectorModule;\n` +
  `const { AiBackend, BACKEND_EMBED_PATH } = global.__aiBackendModule;\n${ENV_STUB}\n${EMBED_HTTP}`);

// ---------- 真 KnowledgeStore ----------
// `KnowledgeCorpusProvider` 内部 `new AdaptivePracticeService()` 只为拿题库，所以给它
// 一个只回答这一件事的替身，把两个模块之间的循环依赖剪断。真的那份服务在下面单独加载。
global.__providerBank = [];
const knowledgeMod = loadArkTs(`${SERVICE_DIR}KnowledgeStore.ets`, `
const { KnowledgeChunker } = global.__chunkerModule;
const { KnowledgeIndex } = global.__indexModule;
const { KnowledgeSeedCorpus } = global.__corpusModule;
const { buildCourseCatalog } = global.__catalogModule;
const { buildLectureNotes } = global.__notesCatalogModule;
const { KnowledgeIndexStore } = global.__liveIndexStoreModule;
const { fingerprintChunks, KNOWLEDGE_SNAPSHOT_VERSION } = global.__codecModule;
const { KnowledgeVectorRetriever, fuseRankings, RRF_RANK_CONSTANT, RRF_DEFAULT_VECTOR_WEIGHT } = global.__vectorModule;
const { KnowledgeProxyEmbedder, vectorWeightForSignature } = global.__proxyModule;
const { KnowledgeEmbeddingBatch, documentTextFor } = global.__embeddingModule;
class AdaptivePracticeService {
  getShippedQuestionBank() { return global.__providerBank; }
}
${MODEL_STUB}
`);
global.__knowledgeModule = knowledgeMod;

// ---------- 练习服务：真的那个 ----------
global.__historyModule = loadArkTs(`${SERVICE_DIR}PracticeHistoryStore.ets`,
  `${ENV_STUB}\nconst { reviewAgeLevel } = global.__sourceModule;`);
global.__profileModule = loadArkTs(`${SERVICE_DIR}LearnerProfileStore.ets`,
  `${ENV_STUB}\nconst Logger = { error() {}, info() {}, warn() {}, debug() {} };`);

// 会话快照里放一个「有错题、但错题本身不可用」的知识点：`buildProfiles` 只看
// `category`，于是 TAG 一定出现在画像里；`ErrorBookPracticeSource` 会因为题干为空把
// 它丢掉，于是错题层一道题都不出 —— 这正是要的：让生成题层成为本组的第一道题，
// 而不是被错题挤到后面。
const serviceMod = loadArkTs(`${SERVICE_DIR}AdaptivePracticeService.ets`, `
${ENV_STUB}
${MODEL_STUB}
class DataCollectService {
  collectAllData() {
    return { examScores: [], courseProgress: [], totalStudyTime: 0,
      errorQuestions: [{ id: 'e2e_err_1', title: '', category: ${JSON.stringify(TAG)} }] };
  }
}
class ErrorAttributionService {
  diagnosePracticeQuestion() {
    return { causeLabel: '端到端归因', confidence: 80, remediation: '复习', evidence: '答错' };
  }
}
const { ErrorBookPracticeSource, normalizeKnowledgeTag, normalizeQuestionTitle, stableTextHash } = global.__sourceModule;
const { PracticeHistoryStore, DEFAULT_SEED_MASTERY, buildPracticeHistoryLine } = global.__historyModule;
const { LearnerProfileStore } = global.__profileModule;
const { PracticeQuestionSynthesizer, SynthesisPassage, SynthesisRequest,
  SYNTHESIS_QUESTION_COUNT } = global.__synthModule;
const GeneratedQuestionPool = global.__poolModule.GeneratedQuestionPool;
const AiService = global.__aiModule.AiService;
const KnowledgeStore = global.__knowledgeModule.KnowledgeStore;
`);

// 题库：真的那份。用真服务取，避免脚本自己抄一份题库出来再和源码漂移。
global.__providerBank = new serviceMod.AdaptivePracticeService().getShippedQuestionBank();

(async () => {
  console.log('══ RAG + LLM 出题 · 端到端（生产代码路径）══');
  console.log(`  后端      ${BASE}（令牌长度 ${APP_TOKEN.length}）`);
  console.log(`  知识点    ${TAG}`);

  // ---------- 真语料 + 真检索 ----------
  section('1. 真讲义语料与检索');
  const provider = new knowledgeMod.KnowledgeCorpusProvider();
  const documents = new global.__corpusModule.KnowledgeSeedCorpus().buildDocuments(
    provider.getCourses(), provider.getQuestions(), provider.getLectures());
  const chunks = new global.__chunkerModule.KnowledgeChunker().buildChunks(documents);
  console.log(`  · 语料块数 ${chunks.length}（讲义 + 课程目录 + 题库）`);
  check('语料非空（讲义真的装进来了）', chunks.length > 200, chunks.length, '> 200');

  const knowledgeStore = new knowledgeMod.KnowledgeStore(
    provider, new global.__liveIndexStoreModule.KnowledgeIndexStore());
  const hits = await knowledgeStore.searchBest(TAG, 3);
  console.log(`  · 「${TAG}」命中 ${hits.length} 段：${hits.map((h) => knowledgeStore.citationOf(h)).join(' | ')}`);
  check('检索到可用于出题的讲义片段', hits.length >= 1 && hits[0].chunk.text.length > 40,
    { hits: hits.length, firstLen: hits[0] ? hits[0].chunk.text.length : 0 }, '>= 1 hit, > 40 chars');
  check('本次没有可用的向量侧（脚本刻意不配嵌入器）', knowledgeStore.hasVectors() === false,
    knowledgeStore.hasVectors(), false);

  // ---------- 真调后端出题 ----------
  section('2. 真调后端出题');
  const pool = new poolMod.GeneratedQuestionPool();
  const aiService = new aiModule.AiService(90000, 50, backendForChat);
  const service = new serviceMod.AdaptivePracticeService(aiService, knowledgeStore, pool);
  check('AiService 处在后端模式（厂商密钥只在服务端）', aiService.getMode() === 'backend', aiService.getMode(), 'backend');
  check('新池初始为空', pool.size() === 0, pool.size(), 0);

  const profile = new global.KnowledgePracticeProfile(TAG, 0, 62, 80, '端到端验证');
  const started = Date.now();
  const added = await service.prepareQuestions([profile]);
  const elapsed = Date.now() - started;
  const stats = service.getSynthesisStats();
  console.log(`  · 用时 ${elapsed} ms，后端请求 ${global.__chatLog.length} 次`);
  for (const entry of global.__chatLog) {
    console.log(`    POST ${entry.url} → ${entry.status}（${entry.ms} ms，正文 ${entry.contentChars} 字）`);
  }
  check('后端返回 200', global.__chatLog.length === 1 && global.__chatLog[0].status === 200,
    global.__chatLog.map((e) => e.status), [200]);
  check('题目被解析并入池', added === synthMod.SYNTHESIS_QUESTION_COUNT && pool.countForTag(TAG) === added,
    { added, pooled: pool.countForTag(TAG) }, { added: synthMod.SYNTHESIS_QUESTION_COUNT });
  check('失败锁没有被置上', stats.blocked === false, stats.lastError || '(none)', '(no error)');
  check('整趟没有发出任何嵌入请求（没为向量侧付费）', global.__embedLog.length === 0,
    global.__embedLog.length, 0);

  // prompt 里必须真的带着讲义原文，否则「grounding」只是说法。
  const sentPrompt = global.__chatLog[0].userPrompt;
  const firstPassage = hits[0].chunk.text.slice(0, 20);
  check('发出的提示词里带着刚检索到的讲义原文（真的 grounding，不是模板）',
    sentPrompt.indexOf(firstPassage) >= 0 && sentPrompt.indexOf(`知识点：${TAG}`) >= 0,
    { promptLen: sentPrompt.length, hasPassage: sentPrompt.indexOf(firstPassage) >= 0 },
    { promptLen: '> 0', hasPassage: true });
  check('提示词里没有任何厂商密钥（客户端只带应用令牌）',
    sentPrompt.indexOf('sk-') < 0 && (env.CHAT_API_KEY || '').length > 0 &&
    sentPrompt.indexOf(env.CHAT_API_KEY) < 0,
    'no vendor key', 'no vendor key');

  // ---------- 题目本身 ----------
  section('3. 生成出来的题目');
  const generated = pool.getForTag(TAG, [], 99);
  for (const question of generated) {
    console.log(`  · ${question.title}`);
    console.log(`    难度 ${question.difficulty} ｜ 答案 ${question.correctIndex + 1}/${question.options.length}` +
      ` ｜ 出处 ${question.citation}`);
    console.log(`    解析 ${question.explanation.slice(0, 60)}…`);
  }
  const allShapeOk = generated.length > 0 && generated.every((q) => q.title.length > 8 && q.options.length === 4 &&
    q.correctIndex >= 0 && q.correctIndex < q.options.length &&
    q.explanation.length > 20 && q.recommendation.length > 0 &&
    q.source === synthMod.SOURCE_AI_GENERATED && q.citation.length > 0 &&
    q.selectedIndex === -1 && q.isSubmitted === false);
  check('每题形状合规（题干/4 选项/答案下标/解析/建议/出处/未作答）', allShapeOk, generated.length, 'all ok');
  const spreads = [...new Set(generated.map((q) => q.correctIndex))];
  check('答案位置不是千篇一律（不全是第一个选项）', spreads.length >= 2, spreads, '>= 2 distinct');
  check('难度按掌握度取（62 → 进阶）', generated.every((q) => q.difficulty === '进阶'),
    generated.map((q) => q.difficulty), ['进阶']);

  // ---------- 真的被练习用上 ----------
  section('4. 下一组练习真的用上它');
  const session = service.generateSession(6, Date.now());
  const generatedInSession = session.questions.filter((q) => q.source === synthMod.SOURCE_AI_GENERATED);
  console.log('  · 本组题目：');
  for (const question of session.questions) {
    console.log(`    [${question.source}] ${question.title.slice(0, 44)}`);
  }
  check('生成题进入会话且排在最前（最弱知识点优先）',
    generatedInSession.length >= 1 && session.questions[0].source === synthMod.SOURCE_AI_GENERATED,
    session.questions.map((q) => q.source), 'ai_generated first');
  check('每题仍满 6 道（生成题只是补充，不挤掉原有材料）',
    session.questions.length === 6, session.questions.length, 6);
  check('生成题带着出处一路走到会话里', generatedInSession.every((q) => q.citation.length > 0),
    generatedInSession.map((q) => q.citation), 'all non-empty');

  // ---------- 覆盖阈值：不该重复付费 ----------
  section('5. 已覆盖就不该再请求');
  const callsBefore = global.__chatLog.length;
  const secondAdded = await service.prepareQuestions([profile]);
  check('第二次调用不再打后端（池里已经够了）',
    global.__chatLog.length === callsBefore && secondAdded === 0,
    { calls: global.__chatLog.length, added: secondAdded }, { calls: callsBefore, added: 0 });

  // ---------- 缓存是真的落到了盘上 ----------
  section('6. 落盘与恢复');
  const persisted = global.__envStub.files[POOL_PATH];
  check('题目写进了 filesDir/generatedQuestions.json',
    typeof persisted === 'string' && persisted.length > 100,
    typeof persisted === 'string' ? persisted.length : '(missing)', '> 100 chars');
  const reloaded = new poolMod.GeneratedQuestionPool();
  check('新实例能从文件读回同样的题目与出处',
    reloaded.countForTag(TAG) === generated.length && reloaded.getForTag(TAG, [], 99)[0].citation.length > 0,
    { count: reloaded.countForTag(TAG), expected: generated.length }, 'same count');
  check('语料快照与题目池是两个文件（互不覆盖）', SNAPSHOT_PATH !== POOL_PATH,
    { pool: POOL_PATH, snapshot: SNAPSHOT_PATH }, 'distinct');

  console.log('');
  console.log(`${passed}/${passed + failed} passed`);
  process.exit(failed > 0 ? 1 : 0);
})();

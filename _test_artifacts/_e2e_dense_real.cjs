/*
 * 端到端跑通「向量侧」——走**生产**代码路径，不是脚本自己拼融合。
 *
 * 与 `_eval_real_embedding.cjs` 的分工：
 *   - 那个脚本回答「该不该接、权重给多少」。它自己加载 chunker/index/vector，
 *     亲手调 fuseRankings，因此**验证不了接线**——它证明的是算法，不是通路。
 *   - 这个脚本回答「接线到底通不通」。它只碰 `KnowledgeStore.searchBest()`，
 *     下面是真实的 KnowledgeEmbeddingProxy → 真实 http → 本机后端 /embed → 百炼。
 *     chunker、index、融合、签名、权重、落盘全部由生产代码自己决定。
 *
 * 四段证据：
 *   1. 冷启动首问必须走 BM25 且不等待（同时后台真的开始嵌 243 块）；
 *   2. 第二问必须走融合，且批次形状正确（10 批 × ≤25、全部 200）；
 *   3. 33 条评测用例经**生产** searchBest 复现评测脚本测得的基线（Recall@3 0.9697）；
 *   4. 快照落盘后，新实例从缓存恢复向量、**不再嵌入**、排序逐位不变
 *      —— 这条用**真实 1024 维远端向量**验证 int8+base64 编解码，此前只用合成数据测过。
 *
 * 花钱的地方只有第 1 段（243 块 ≈ 6.2 万 token）。第一次跑完会把生产编码出的快照
 * 存进 `_e2e_dense.cache.json`，之后用 `--reuse` 就能零成本跳过前三段
 * （第 4 段仍会为 33 条查询各发一次短请求，量可忽略）。
 *
 * 用法：
 *   node _test_artifacts/_e2e_dense_real.cjs              # 全量（真的嵌入 243 块）
 *   node _test_artifacts/_e2e_dense_real.cjs --reuse      # 复用上次的快照，不再嵌文档
 *   node _test_artifacts/_e2e_dense_real.cjs --base http://10.0.0.5:8787
 */
const fs = require('fs');
const path = require('path');

const REUSE = process.argv.indexOf('--reuse') >= 0;
const baseArgIndex = process.argv.indexOf('--base');
const BASE_ARG = baseArgIndex >= 0 ? process.argv[baseArgIndex + 1] : '';

const ROOT = path.resolve(__dirname, '..');
// 命名以 .cache.json 结尾，这样既有的忽略规则（_test_artifacts/*.cache.json）
// 一并挡住它 —— 里面是真实嵌入向量，是产物不是源码，不入库。
const SNAPSHOT_CACHE = path.join(__dirname, '_e2e_dense.cache.json');

// 整段输出同时落一份日志（`_test_artifacts/*.log` 已被忽略）。留证用：这次跑的证据
// 应该是机器写下来的，而不是从终端里手工抄走的——抄一遍就多一次抄错的机会。
const LOG_PATH = path.join(__dirname, '_e2e_dense_run.log');
const capturedLines = [];
const rawConsoleLog = console.log.bind(console);
console.log = (...args) => {
  capturedLines.push(args.map((a) => (typeof a === 'string' ? a : JSON.stringify(a))).join(' '));
  rawConsoleLog(...args);
};
process.on('exit', () => {
  try {
    fs.writeFileSync(LOG_PATH, capturedLines.join('\n') + '\n');
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

const MODEL_STUB = `
const KnowledgeSourceType = { COURSE: 'course', QUESTION_BANK: 'question_bank',
  ERROR_BOOK: 'error_book', COURSE_NOTE: 'course_note' };
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
  constructor() {
    Object.assign(this, { chunkLengths: [], averageLength: 0, terms: [], postings: [] });
  }
}
class KnowledgeSnapshot {
  constructor() {
    Object.assign(this, { version: 0, fingerprint: '', signature: '', vectorSignature: '',
      chunks: [], state: new KnowledgeIndexState(), vectors: [] });
  }
}
class SeedCourseInput {
  constructor() { Object.assign(this, { courseId: '', title: '', category: '', description: '' }); }
}
class SeedLectureInput {
  constructor() {
    Object.assign(this, { courseId: '', title: '', category: '', knowledgeTag: '', markdown: '' });
  }
}
class SeedQuestionInput {
  constructor() {
    Object.assign(this, { questionId: '', title: '', options: [], correctIndex: -1,
      knowledgeTag: '', explanation: '', recommendation: '' });
  }
}
`;

const SOURCE_PRELUDE = `
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
`;

const SHARED_DEPS = `
const { isCorruptedText, normalizeKnowledgeTag, normalizeQuestionTitle } = global.__sourceModule;
`;

global.__sourceModule = loadArkTs(`${SERVICE_DIR}ErrorBookPracticeSource.ets`, SOURCE_PRELUDE);
const codecModule = loadArkTs(`${SERVICE_DIR}KnowledgeSnapshotCodec.ets`, MODEL_STUB);
global.__codecModule = codecModule;

const chunkerModule = loadArkTs(`${SERVICE_DIR}KnowledgeChunker.ets`, `${SHARED_DEPS}\n${MODEL_STUB}`);
const indexModule = loadArkTs(`${SERVICE_DIR}KnowledgeIndex.ets`,
  `${MODEL_STUB}\nconst { hashString } = global.__codecModule;`);
const corpusModule = loadArkTs(`${SERVICE_DIR}KnowledgeSeedCorpus.ets`, `${SHARED_DEPS}\n${MODEL_STUB}`);
const catalogModule = loadArkTs(`${SERVICE_DIR}KnowledgeCourseCatalog.ets`, `${SHARED_DEPS}\n${MODEL_STUB}`);
global.__chunkerModule = chunkerModule;
global.__indexModule = indexModule;
global.__corpusModule = corpusModule;
global.__catalogModule = catalogModule;

const embeddingModule = loadArkTs(`${SERVICE_DIR}KnowledgeEmbedding.ets`,
  `${MODEL_STUB}\nconst { tokenizeWithUnigrams } = global.__indexModule;\nconst { hashString } = global.__codecModule;`);
global.__embeddingModule = embeddingModule;
const vectorModule = loadArkTs(`${SERVICE_DIR}KnowledgeVectorRetriever.ets`,
  `${MODEL_STUB}\nconst { cosineSimilarity } = global.__embeddingModule;`);
global.__vectorModule = vectorModule;

global.__notesSupport = loadArkTs(`${SERVICE_DIR}KnowledgeNotesSupport.ets`, MODEL_STUB);
const noteFiles = fs.readdirSync(path.join(ROOT, SERVICE_DIR)).filter((f) =>
  /^KnowledgeNotes.*\.ets$/.test(f) && f !== 'KnowledgeNotesCatalog.ets' && f !== 'KnowledgeNotesSupport.ets');
let catalogPrelude = `${MODEL_STUB}\n`;
for (const file of noteFiles) {
  const noteModule = loadArkTs(`${SERVICE_DIR}${file}`,
    `const { makeLecture } = global.__notesSupport;\n${MODEL_STUB}`);
  const builderName = Object.keys(noteModule).find((key) => /^build.*Notes$/.test(key));
  if (!builderName) {
    throw new Error(`no note builder exported by ${file}`);
  }
  global.__noteBuilders = global.__noteBuilders || {};
  global.__noteBuilders[builderName] = noteModule[builderName];
  catalogPrelude += `const ${builderName} = global.__noteBuilders['${builderName}'];\n`;
}
const notesCatalogModule = loadArkTs(`${SERVICE_DIR}KnowledgeNotesCatalog.ets`, catalogPrelude);
global.__notesCatalogModule = notesCatalogModule;

const metricsModule = loadArkTs(`${SERVICE_DIR}KnowledgeRetrievalMetrics.ets`, MODEL_STUB);
const evalSetModule = loadArkTs(`${SERVICE_DIR}KnowledgeEvalSet.ets`, MODEL_STUB);

// ---------- 设备侧环境桩：AppStorage + 沙箱文件 ----------
//
// 同一份桩喂给 AiBackend（读后端地址与令牌）和 KnowledgeIndexStore（读写快照）。
// 真机上这两者看到的是同一套 AppStorage 与同一个 filesDir，这里必须一致，
// 否则「配了后端」和「落盘可用」会在两个互不相干的世界里分别成立。
global.__envStub = { files: {}, dirs: {}, opens: 0, closes: 0 };
const SNAPSHOT_PATH = '/data/files/knowledgeIndex.json';
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

// ---------- 真 HTTP 桩 ----------
//
// 这是整件事的要害：所有其它离线套件都把 http 换成「返回一段固定 JSON」，因此
// 只能证明代理**解析**得对。这里换成真的 fetch，于是下面这条链路第一次被真正走过：
//   proxy.embed → http.createHttp().request → POST http://127.0.0.1:8787/embed
//   → 服务端带厂商密钥转百炼 → 1024 维向量回到客户端。
// 客户端自始至终不持有任何厂商密钥，这正是代理存在的理由。
global.__embedLog = [];
global.__proxyWarnings = [];
const REAL_HTTP = `
const __log = global.__embedLog;
const http = {
  RequestMethod: { POST: 'POST' },
  HttpDataType: { STRING: 0 },
  createHttp() {
    return {
      async request(url, options) {
        const started = Date.now();
        const entry = { url, status: 0, ms: 0, inputs: -1, bytes: 0, error: '', vectorWidth: 0 };
        try {
          entry.inputs = JSON.parse(options.extraData).inputs.length;
        } catch (e) { /* 记 -1，断言会抓到 */ }
        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), 60000);
        try {
          const response = await fetch(url, {
            method: options.method,
            headers: options.header,
            body: options.extraData,
            signal: controller.signal,
          });
          const text = await response.text();
          entry.status = response.status;
          entry.bytes = Buffer.byteLength(text);
          entry.ms = Date.now() - started;
          try {
            const parsed = JSON.parse(text);
            if (parsed && Array.isArray(parsed.vectors) && parsed.vectors.length > 0) {
              entry.vectorWidth = parsed.vectors[0].length;
            }
          } catch (e) { /* 非 JSON 也要能落进日志，断言看 status */ }
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
    };
  },
};
const Logger = { info() {}, warn(m) { global.__proxyWarnings.push(String(m)); },
  error(m) { global.__proxyWarnings.push(String(m)); }, debug() {} };
`;

global.__aiBackendModule = loadArkTs(`${SERVICE_DIR}AiBackend.ets`, ENV_STUB);
global.__proxyModule = loadArkTs(`${SERVICE_DIR}KnowledgeEmbeddingProxy.ets`,
  `${MODEL_STUB}\nconst { KnowledgeEmbeddingBatch } = global.__embeddingModule;\n` +
  `const { RRF_DEFAULT_VECTOR_WEIGHT, RRF_REMOTE_VECTOR_WEIGHT } = global.__vectorModule;\n` +
  `const { AiBackend, BACKEND_EMBED_PATH } = global.__aiBackendModule;\n${ENV_STUB}\n${REAL_HTTP}`);

// 活体 KnowledgeIndexStore：真的读 /data/files/knowledgeIndex.json，并且真的走
// decodeSnapshot，所以第 4 段验证的是生产编解码器，不是脚本的手艺。
global.__liveIndexStoreModule = loadArkTs(`${SERVICE_DIR}KnowledgeIndexStore.ets`,
  `${ENV_STUB}\nconst { encodeSnapshot, decodeSnapshot } = global.__codecModule;\n${MODEL_STUB}`);

const STORE_DEPS = `
const { KnowledgeChunker } = global.__chunkerModule;
const { KnowledgeIndex } = global.__indexModule;
const { KnowledgeSeedCorpus } = global.__corpusModule;
const { buildCourseCatalog, CATALOG_ROW_COUNT } = global.__catalogModule;
const { buildLectureNotes } = global.__notesCatalogModule;
const { KnowledgeIndexStore } = global.__liveIndexStoreModule;
const { fingerprintChunks, KNOWLEDGE_SNAPSHOT_VERSION } = global.__codecModule;
const { KnowledgeVectorRetriever, fuseRankings, RRF_RANK_CONSTANT,
  RRF_DEFAULT_VECTOR_WEIGHT } = global.__vectorModule;
const { KnowledgeProxyEmbedder, vectorWeightForSignature } = global.__proxyModule;
const { KnowledgeEmbeddingBatch, documentTextFor } = global.__embeddingModule;
class AdaptivePracticeService {
  getShippedQuestionBank() { return global.__providerBank; }
}
${MODEL_STUB}
`;

// 与 p7 / 评测脚本同一道题库桩，块数才可比。
global.__providerBank = [
  {
    id: 'q_tcp_note', title: 'TCP 相比 UDP 最典型的特征是？',
    options: ['无连接', '可靠传输', '不校验数据', '一定更快'], correctIndex: 1,
    knowledgeTag: '计算机网络',
    explanation: 'TCP 面向连接，提供可靠传输；UDP 无连接、开销较小。',
    recommendation: '比较协议时从连接性、可靠性、开销和典型场景四个维度入手。',
  },
];

const storeModule = loadArkTs(`${SERVICE_DIR}KnowledgeStore.ets`, STORE_DEPS);
const { KnowledgeStore, KnowledgeCorpusProvider, DENSE_EMBED_BATCH_SIZE } = storeModule;
const { KnowledgeChunker } = chunkerModule;
const { KnowledgeSeedCorpus } = corpusModule;
const { buildKnowledgeEvalSet } = evalSetModule;
const { evaluateCase, summarize, formatRetrievalReport } = metricsModule;

const P7_CHUNK_COUNT = 243;
const EXPECTED_HYBRID_RECALL = 0.9697;
const EXPECTED_BM25_RECALL = 0.8485;
/** 243×1024 个 int8 + base64 + 一份 float scale：理论约 324 KB。 */
const EXPECTED_VECTOR_PAYLOAD_KB = 324;

// ---------- 报告 ----------
const results = [];
let failures = 0;
function check(name, condition, actual, expected) {
  results.push({ name, status: condition ? 'PASS' : 'FAIL', actual, expected });
  if (!condition) failures++;
  console.log(`  ${condition ? '[ok]  ' : '[FAIL]'} ${name}`);
  if (!condition) {
    console.log(`         实际: ${JSON.stringify(actual)}`);
    console.log(`         期望: ${JSON.stringify(expected)}`);
  }
}
function section(title) {
  console.log('');
  console.log(title);
}
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const kbOf = (value) => Math.round(Buffer.byteLength(typeof value === 'string' ? value : JSON.stringify(value)) / 1024);

function msOf(fn) {
  const t0 = process.hrtime.bigint();
  const out = fn();
  return { ms: Number(process.hrtime.bigint() - t0) / 1e6, out };
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
const BASE = (BASE_ARG || `http://127.0.0.1:${PORT}`).replace(/\/+$/, '');

if (APP_TOKEN.length === 0) {
  console.error('server/.env 里没有 APP_TOKEN —— 后端若开了鉴权，这一趟只会得到 401。');
  process.exit(2);
}

// AppStorage 里就是设置面板写下的那两项，外加 filesDir。这样 AiBackend.current()
// 解析出来的正是用户在面板里填的后端，而不是脚本塞给某个内部对象的东西。
global.__envStub.dirs.aiBackendUrl = BASE;
global.__envStub.dirs.aiBackendToken = APP_TOKEN;
global.__envStub.dirs.filesDir = '/data/files';

// ---------- 语料自检 ----------
const provider = new KnowledgeCorpusProvider();
const builtDocs = new KnowledgeSeedCorpus().buildDocuments(
  provider.getCourses(), provider.getQuestions(), provider.getLectures());
const chunks = new KnowledgeChunker().buildChunks(builtDocs);

if (chunks.length !== P7_CHUNK_COUNT) {
  console.error(`语料漂移：块数 ${chunks.length} != p7 基线 ${P7_CHUNK_COUNT}。`);
  console.error('批次断言与评测基线都不可比，先核对讲义/目录/题库桩是否改过。');
  process.exit(2);
}

function freshStore() {
  return new KnowledgeStore(new KnowledgeCorpusProvider(),
    new global.__liveIndexStoreModule.KnowledgeIndexStore());
}

function idsOf(hits) {
  return hits.map((hit) => hit.chunk.chunkId);
}

const evalCases = buildKnowledgeEvalSet();
const traceCase = evalCases.find((item) => item.bucket === 'paraphrase') || evalCases[0];

/**
 * 三段只存在于「没有向量」的状态里，所以复用快照时整体跳过：
 * 首问不等嵌入、10 批形状、单飞——那时根本没有构建要观察。
 */
async function coldPhases(store, expectedBatches) {
  section('1. 冷启动首问（无向量）');
  const t0 = Date.now();
  const coldHits = await store.searchBest(traceCase.query);
  const coldMs = Date.now() - t0;
  const lexicalHits = store.search(traceCase.query);

  check('首问用的是纯 BM25 结果（不是"等一下再说"）',
    JSON.stringify(idsOf(coldHits)) === JSON.stringify(idsOf(lexicalHits)),
    idsOf(coldHits), idsOf(lexicalHits));
  check('首问返回时向量还没装好', store.hasVectors() === false, store.hasVectors(), false);
  check('首问返回时后台构建已经启动（单飞承诺）', store.isDensePending() === true,
    store.isDensePending(), true);
  check('首问返回前没有为文档发起任何嵌入（发起了就说明它在等）',
    global.__embedLog.filter((entry) => entry.inputs > 1).length === 0,
    global.__embedLog.length, 0);
  console.log(`  · 首问耗时 ${coldMs} ms（不含任何嵌入等待）`);

  section('2. 后台构建（243 块 → 分批嵌入 → 安装）');
  const buildStart = Date.now();
  let denseState = 'failed';
  const deadline = Date.now() + 240000;
  while (Date.now() < deadline) {
    if (store.hasVectors()) { denseState = 'ok'; break; }
    if (!store.isDensePending()) { denseState = 'failed'; break; }
    await sleep(200);
  }
  const buildMs = Date.now() - buildStart;
  check('后台构建建成并安装了向量（未等满 240 秒）', denseState === 'ok', denseState, 'ok');
  if (denseState !== 'ok') {
    console.log('\n构建没成，后面的融合断言没有意义。嵌入日志：');
    console.log(JSON.stringify(global.__embedLog.slice(-4), null, 2));
    console.log('代理告警：' + JSON.stringify(global.__proxyWarnings.slice(-4)));
    console.log(`\n${results.filter((r) => r.status === 'FAIL').length} 项失败。`);
    process.exit(1);
  }

  const docCalls = global.__embedLog.filter((entry) => entry.inputs > 1);
  const docInputs = docCalls.reduce((sum, entry) => sum + entry.inputs, 0);
  check('文档侧嵌入批次形状正确（每批 ≤ 25，共 ceil(243/25) = 10 批）',
    docCalls.length === expectedBatches && docCalls.every((entry) => entry.inputs <= DENSE_EMBED_BATCH_SIZE),
    { batches: docCalls.length, sizes: docCalls.map((entry) => entry.inputs) },
    { batches: expectedBatches, maxSize: DENSE_EMBED_BATCH_SIZE });
  check('文档侧嵌入覆盖了全部 243 块，一块不多一块不少',
    docInputs === chunks.length, docInputs, chunks.length);
  check('每一批都是 200（没有静默降级成"没有向量"）',
    docCalls.every((entry) => entry.status === 200),
    docCalls.map((entry) => entry.status), docCalls.map(() => 200));
  check('后端返回的是 1024 维（真模型，不是替身）',
    docCalls.every((entry) => entry.vectorWidth === 1024),
    docCalls.map((entry) => entry.vectorWidth).find((w) => w !== 1024) || 1024, 1024);
  check('请求发往配置的后端 /embed，而不是某个厂商地址',
    docCalls.every((entry) => entry.url === `${BASE}/embed`), docCalls[0].url, `${BASE}/embed`);
  check('整个构建过程没有产生代理告警',
    global.__proxyWarnings.length === 0, global.__proxyWarnings, []);
  console.log(`  · 构建耗时 ${(buildMs / 1000).toFixed(1)} s，`
    + `平均每批 ${(docCalls.reduce((s, e) => s + e.ms, 0) / docCalls.length).toFixed(0)} ms`);
  return { coldMs, buildMs };
}

console.log('SafeTAcademy — 向量侧端到端');
console.log(`  后端      ${BASE}（令牌已填，长度 ${APP_TOKEN.length}）`);
console.log(`  语料      ${chunks.length} 块（与 p7 基线一致）`);
console.log(`  评测集    ${evalCases.length} 条`);
console.log(`  追踪问题  "${traceCase.query}"  [${traceCase.bucket}]`);
console.log(`  模式      ${REUSE ? '复用快照（不嵌入文档）' : '全量（会真的嵌入 ' + chunks.length + ' 块）'}`);

(async () => {
  if (REUSE) {
    if (!fs.existsSync(SNAPSHOT_CACHE)) {
      console.error(`\n--reuse 需要一个快照缓存，但 ${path.basename(SNAPSHOT_CACHE)} 不存在。先跑一次全量。`);
      process.exit(2);
    }
    const cached = JSON.parse(fs.readFileSync(SNAPSHOT_CACHE, 'utf8'));
    global.__envStub.files[SNAPSHOT_PATH] = cached.snapshot;
    console.log(`  已装入快照 ${kbOf(cached.snapshot)} KB（录于 ${cached.recordedAt}）`);
  }

  const expectedBatches = Math.ceil(chunks.length / DENSE_EMBED_BATCH_SIZE);
  const store = freshStore();

  if (REUSE) {
    section('1–3. 冷启动三段（已跳过）');
    store.warmUp();
    check('复用模式下实例带着缓存向量起跑',
      store.hasVectors() === true && store.getLoadSource() === 'cache',
      { vectors: store.hasVectors(), source: store.getLoadSource() },
      { vectors: true, source: 'cache' });
    console.log('  · 要验证「首问不等嵌入」「10 批形状」「单飞」，请跑一次全量（去掉 --reuse）。');
  } else {
    await coldPhases(store, expectedBatches);
  }

  // ================= 融合通路 =================
  section('3. 有向量之后：必须真的换了通路');
  const lexicalHits = store.search(traceCase.query);
  const hybridHits = await store.searchBest(traceCase.query);
  const docCalls = global.__embedLog.filter((entry) => entry.inputs > 1);
  const queryCalls = global.__embedLog.filter((entry) => entry.inputs === 1);

  check('结果与纯 BM25 不同（说明走的是融合，不是词法原样返回）',
    JSON.stringify(idsOf(hybridHits)) !== JSON.stringify(idsOf(lexicalHits)),
    idsOf(hybridHits), idsOf(lexicalHits));
  check('检索时没有再为文档发起嵌入（向量在手就不该重复付费）',
    docCalls.length === (REUSE ? 0 : expectedBatches), docCalls.length, REUSE ? 0 : expectedBatches);
  check('这次检索只嵌入了一条查询文本，且成功',
    queryCalls.length === (REUSE ? 1 : 1) && queryCalls.every((entry) => entry.status === 200),
    queryCalls.length, 1);
  const installedSignature = store.getVectorSource();
  check('向量带上了远端来源签名（remote:<model>:<width>）',
    installedSignature.indexOf('remote:') === 0 && installedSignature.indexOf(':1024') > 0,
    installedSignature, 'remote:*:1024');
  check('融合权重按远端嵌入器自报为 1（不是给哈希替身用的 0.35）',
    store.getVectorWeight() === 1, store.getVectorWeight(), 1);
  console.log(`  · 签名 ${installedSignature}`);

  // ================= 33 条评测：生产路径复现基线 =================
  section('4. 33 条评测用例经生产 searchBest 复跑');
  const bm25Rows = [];
  const hybridRows = [];
  for (const item of evalCases) {
    bm25Rows.push(evaluateCase(store.search(item.query, 10), item, 3));
    hybridRows.push(evaluateCase(await store.searchBest(item.query, 10), item, 3));
  }
  const bm25All = summarize(bm25Rows, 3, '');
  const hybridAll = summarize(hybridRows, 3, '');
  const bm25Para = summarize(bm25Rows, 3, 'paraphrase');
  const hybridPara = summarize(hybridRows, 3, 'paraphrase');

  console.log(`  · 纯 BM25           ${formatRetrievalReport(bm25All)}`);
  console.log(`  · 生产 searchBest   ${formatRetrievalReport(hybridAll)}`);
  console.log(`  · paraphrase        ${bm25Para.recallAtK.toFixed(4)} → ${hybridPara.recallAtK.toFixed(4)}`);

  // 基线来自 _eval_real_embedding.cjs（那个脚本自己拼融合）。这里断言生产实现与它一致，
  // 容差 0.01：两者算的是同一件事，差异只可能来自四舍五入或接线不一致。
  check(`生产实现的 Recall@3 复现评测基线 ${EXPECTED_HYBRID_RECALL}`,
    Math.abs(hybridAll.recallAtK - EXPECTED_HYBRID_RECALL) < 0.01,
    Number(hybridAll.recallAtK.toFixed(4)), EXPECTED_HYBRID_RECALL);
  check(`纯词法基线也复现（${EXPECTED_BM25_RECALL}）`,
    Math.abs(bm25All.recallAtK - EXPECTED_BM25_RECALL) < 0.01,
    Number(bm25All.recallAtK.toFixed(4)), EXPECTED_BM25_RECALL);
  check('换句话问（paraphrase）全中', hybridPara.recallAtK === 1, hybridPara.recallAtK, 1);
  check('融合确实优于纯词法（不是"接了但没变好"）',
    hybridAll.recallAtK > bm25All.recallAtK,
    { hybrid: hybridAll.recallAtK, bm25: bm25All.recallAtK }, 'hybrid > bm25');

  // ================= 落盘 + 重启恢复 =================
  section('5. 快照落盘 → 新实例从缓存恢复（真实 1024 维向量走 int8+base64）');
  const snapshotText = global.__envStub.files[SNAPSHOT_PATH];
  check('快照确实写进了 filesDir 下的 knowledgeIndex.json',
    typeof snapshotText === 'string' && snapshotText.length > 0,
    typeof snapshotText === 'string' ? snapshotText.length : null, '非空');

  if (typeof snapshotText === 'string' && snapshotText.length > 0) {
    const totalKB = kbOf(snapshotText);
    // 体积必须按**构成**看，否则很容易把整个快照记成"向量的开销"：
    // 倒排 + 块在接向量之前就已经是几百 KB 了，向量只是在这之上加了 int8 的那份。
    const parsedSnapshot = JSON.parse(snapshotText);
    const withoutVectors = Object.assign({}, parsedSnapshot);
    withoutVectors.vectors = [];
    delete withoutVectors.vectorsQuantized;
    delete withoutVectors.vectorScales;
    const baseKB = kbOf(withoutVectors);
    const vectorKB = totalKB - baseKB;
    console.log(`  · 快照 ${totalKB} KB = 块与倒排 ${baseKB} KB（接向量之前就有）+ 向量 ${vectorKB} KB`);

    check(`向量载荷落在 int8+base64 的量级（理论约 ${EXPECTED_VECTOR_PAYLOAD_KB} KB）`,
      Math.abs(vectorKB - EXPECTED_VECTOR_PAYLOAD_KB) < 40, vectorKB, EXPECTED_VECTOR_PAYLOAD_KB);
    check('整个快照仍然低于 1 MB（float32 直存光向量就要 5000 KB）',
      totalKB < 1024, totalKB, '< 1024');

    fs.writeFileSync(SNAPSHOT_CACHE, JSON.stringify({
      recordedAt: new Date().toISOString(), base: BASE, chunkCount: chunks.length,
      signature: installedSignature, snapshot: snapshotText,
    }));
    console.log(`  · 已缓存到 ${path.basename(SNAPSHOT_CACHE)}，以后 --reuse 零成本复跑`);
  }

  const callsBeforeRestart = global.__embedLog.length;
  const restarted = freshStore();
  const warm = msOf(() => restarted.warmUp());
  check('新实例从缓存装载（而不是全量重建）',
    restarted.getLoadSource() === 'cache', restarted.getLoadSource(), 'cache');
  check('向量随快照一起恢复', restarted.hasVectors() === true, restarted.hasVectors(), true);
  check('恢复出来的来源签名与重建时一致（否则权重会算错）',
    restarted.getVectorSource() === installedSignature,
    restarted.getVectorSource(), installedSignature);
  check('恢复后的融合权重仍是 1（签名反推，不靠存值）',
    restarted.getVectorWeight() === 1, restarted.getVectorWeight(), 1);
  console.log(`  · 带缓存的启动耗时 ${warm.ms.toFixed(1)} ms（含 911 KB 快照的 JSON 解析与反量化）`);

  const restoredHits = await restarted.searchBest(traceCase.query, 10);
  const rebuiltHits = await store.searchBest(traceCase.query, 10);
  check('恢复后的排序与重建时逐位一致（int8 量化不下移任何一条）',
    JSON.stringify(idsOf(restoredHits)) === JSON.stringify(idsOf(rebuiltHits)),
    idsOf(restoredHits), idsOf(rebuiltHits));
  check('恢复过程没有再嵌入文档（只嵌入查询）',
    global.__embedLog.filter((entry) => entry.inputs > 1).length === (REUSE ? 0 : expectedBatches) &&
    global.__embedLog.length === callsBeforeRestart + 2,
    global.__embedLog.length - callsBeforeRestart, 2);

  // ---------- 汇总 ----------
  section('汇总');
  const passed = results.filter((row) => row.status === 'PASS').length;
  const embedTotal = global.__embedLog.reduce((sum, entry) => sum + entry.inputs, 0);
  console.log(`  ${passed}/${results.length} 项通过。`);
  console.log(`  本次真实嵌入 ${embedTotal} 条文本（${global.__embedLog.length} 次请求，全部走 ${BASE}/embed）。`);
  if (failures > 0) {
    console.log(`\n  ${failures} 项失败：`);
    for (const row of results.filter((r) => r.status === 'FAIL')) {
      console.log(`    - ${row.name}`);
    }
  }
  process.exit(failures > 0 ? 1 : 0);
})().catch((error) => {
  console.error('\n脚本自身抛异常：' + (error && error.stack ? error.stack : error));
  process.exit(3);
});

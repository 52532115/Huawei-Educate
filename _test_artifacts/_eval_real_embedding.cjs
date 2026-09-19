/*
 * 用**真实**嵌入模型给课程语料的每一块算向量，跑同一套评测集，回答两个问题：
 *
 *   1. 真模型在这份语料上到底比纯 BM25 强吗？（本地哈希嵌入器已实测为「不强」，
 *      而且 p7 把那个结论固化成了断言。真模型不能靠假设，只能实测。）
 *   2. 融合权重该给多少？（`RRF_DEFAULT_VECTOR_WEIGHT = 0.35` 是为**哈希替身**调的，
 *      对真模型没有先验依据，所以要扫到 1.0 以上。）
 *
 * 语料刻意与 `ai_agent_p7_test.cjs` 完全一致（讲义 + 课程目录 + 同一道题的题库桩），
 * 这样脚本开头的块数自检能跑，而且数字与该文件里记录的 BM25 基线可以直接比。
 * 注意生产语料还含**整套题库**，比这里多；本脚本衡量的是「讲义为主」的那部分，
 * 结论对生产同样成立，但要清楚它衡量的不是全部。
 *
 * 向量缓存到 `_real_vectors.cache.json`：嵌入要花钱，重复调参不该重复付费。
 * 缓存里只有向量和文本摘要，没有密钥。
 *
 * 用法：
 *   node _test_artifacts/_eval_real_embedding.cjs            # 用缓存（没有则先嵌）
 *   node _test_artifacts/_eval_real_embedding.cjs --refresh  # 强制重新嵌入
 *   node _test_artifacts/_eval_real_embedding.cjs --base http://10.0.0.5:8787
 */
const fs = require('fs');
const path = require('path');
const http = require('http');
const crypto = require('crypto');

const REFRESH = process.argv.indexOf('--refresh') >= 0;
const baseArgIndex = process.argv.indexOf('--base');
const BASE_ARG = baseArgIndex >= 0 ? process.argv[baseArgIndex + 1] : '';

const ROOT = path.resolve(__dirname, '..');
const CACHE_FILE = path.join(__dirname, '_real_vectors.cache.json');
/** How many texts per HTTP request. The server splits further to its own batch size. */
const CLIENT_BATCH = 25;
const REQUEST_TIMEOUT_MS = 90000;

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

// Same load order and the same stubs as the p7 suite — this script is only
// meaningful if it measures the code the tests measure.
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

// Each of these must be published to `global` BEFORE the module that borrows
// from it is loaded — the prelude runs at load time, so a symbol published
// afterwards is simply not there yet (`Cannot destructure property … of
// undefined`). Same trap the p7 suite documents for the fs stub.
const embeddingModule = loadArkTs(`${SERVICE_DIR}KnowledgeEmbedding.ets`,
  `${MODEL_STUB}\nconst { tokenizeWithUnigrams } = global.__indexModule;\n` +
  `const { hashString } = global.__codecModule;`);
global.__embeddingModule = embeddingModule;

const vectorModule = loadArkTs(`${SERVICE_DIR}KnowledgeVectorRetriever.ets`,
  `${MODEL_STUB}\nconst { cosineSimilarity } = global.__embeddingModule;`);
global.__vectorModule = vectorModule;

const metricsModule = loadArkTs(`${SERVICE_DIR}KnowledgeRetrievalMetrics.ets`, MODEL_STUB);
const evalSetModule = loadArkTs(`${SERVICE_DIR}KnowledgeEvalSet.ets`, MODEL_STUB);
global.__metricsModule = metricsModule;

global.__notesSupport = loadArkTs(`${SERVICE_DIR}KnowledgeNotesSupport.ets`, MODEL_STUB);

// The note files are discovered rather than listed, so adding a lecture cannot
// leave this script silently measuring a stale corpus.
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

function loadIndexStore(fsPrelude) {
  return loadArkTs(`${SERVICE_DIR}KnowledgeIndexStore.ets`,
    `${fsPrelude}\nconst { encodeSnapshot, decodeSnapshot } = global.__codecModule;\n${MODEL_STUB}`);
}
global.__indexStoreModule = loadIndexStore('');

const STORE_DEPS = `
const { KnowledgeChunker } = global.__chunkerModule;
const { KnowledgeIndex } = global.__indexModule;
const { KnowledgeSeedCorpus } = global.__corpusModule;
const { buildCourseCatalog, CATALOG_ROW_COUNT } = global.__catalogModule;
const { buildLectureNotes } = global.__notesCatalogModule;
const { KnowledgeIndexStore } = global.__indexStoreModule;
const { fingerprintChunks, KNOWLEDGE_SNAPSHOT_VERSION } = global.__codecModule;
const { KnowledgeVectorRetriever, fuseRankings } = global.__vectorModule;
class AdaptivePracticeService {
  getShippedQuestionBank() { return global.__providerBank; }
}
${MODEL_STUB}
`;
const storeModule = loadArkTs(`${SERVICE_DIR}KnowledgeStore.ets`, STORE_DEPS);

const { KnowledgeChunker } = chunkerModule;
const { KnowledgeSeedCorpus } = corpusModule;
const { KnowledgeStore, KnowledgeCorpusProvider, HYBRID_CANDIDATE_DEPTH } = storeModule;
const { documentTextFor, normalizeVector } = embeddingModule;
const { KnowledgeVectorRetriever, fuseRankings } = vectorModule;

// Same stub bank as p7, so the chunk count self-check below is comparable.
global.__providerBank = [
  {
    id: 'q_tcp_note', title: 'TCP 相比 UDP 最典型的特征是？',
    options: ['无连接', '可靠传输', '不校验数据', '一定更快'], correctIndex: 1,
    knowledgeTag: '计算机网络',
    explanation: 'TCP 面向连接，提供可靠传输；UDP 无连接、开销较小。',
    recommendation: '比较协议时从连接性、可靠性、开销和典型场景四个维度入手。',
  },
];

// p7 运行时实测的块数（见 ai_agent_p7_test_result.json 的「门面懒构建」一条）：
// 217 讲义块 + 24 课程目录 + 2 题库块 = 243。别把它跟某些笔记里的 "241" 混淆——
// 那个数字只算了讲义与目录，不含题库。
const P7_CHUNK_COUNT = 243;

const provider = new KnowledgeCorpusProvider();
const builtDocs = new KnowledgeSeedCorpus().buildDocuments(
  provider.getCourses(), provider.getQuestions(), provider.getLectures());
const chunks = new KnowledgeChunker().buildChunks(builtDocs);

if (chunks.length !== P7_CHUNK_COUNT) {
  console.error(`语料漂移：块数 ${chunks.length} != p7 基线 ${P7_CHUNK_COUNT}。`);
  console.error('评测数字与 p7 记录的基线不可比，先核对讲义/目录是否改过，或更新这个常量。');
  process.exit(2);
}

// ---------- backend ----------

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
const EMBED_URL = `${BASE}/embed`;

function postJson(url, payload) {
  return new Promise((resolve, reject) => {
    const data = JSON.stringify(payload);
    const parsed = new URL(url);
    const request = http.request({
      hostname: parsed.hostname,
      port: parsed.port || 80,
      path: parsed.pathname,
      method: 'POST',
      headers: Object.assign({
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(data),
      }, APP_TOKEN.length > 0 ? { Authorization: `Bearer ${APP_TOKEN}` } : {}),
      timeout: REQUEST_TIMEOUT_MS,
    }, (response) => {
      const parts = [];
      response.on('data', (chunk) => parts.push(chunk));
      response.on('end', () => resolve({
        status: response.statusCode,
        body: Buffer.concat(parts).toString('utf8'),
      }));
    });
    request.on('timeout', () => request.destroy(new Error(`timeout after ${REQUEST_TIMEOUT_MS}ms`)));
    request.on('error', reject);
    request.write(data);
    request.end();
  });
}

function digestOf(texts) {
  const hash = crypto.createHash('sha256');
  for (const text of texts) {
    hash.update(text);
    hash.update('\u0000');
  }
  return hash.digest('hex').slice(0, 16);
}

let cache = { textsDigest: '', model: '', dimension: 0, vectors: [], queries: {} };
if (fs.existsSync(CACHE_FILE) && !REFRESH) {
  try {
    cache = JSON.parse(fs.readFileSync(CACHE_FILE, 'utf8'));
  } catch (e) {
    console.warn(`缓存损坏，忽略：${CACHE_FILE}`);
  }
}

const texts = chunks.map((chunk) => documentTextFor(chunk));
const textsDigest = digestOf(texts);

async function embedBatch(batchTexts, label) {
  const response = await postJson(EMBED_URL, { model: '', inputs: batchTexts });
  if (response.status !== 200) {
    throw new Error(`${label}: /embed 回 ${response.status} — ${response.body.slice(0, 300)}`);
  }
  const parsed = JSON.parse(response.body);
  if (!Array.isArray(parsed.vectors) || parsed.vectors.length !== batchTexts.length) {
    throw new Error(`${label}: 返回 ${parsed.vectors ? parsed.vectors.length : 'no'} 条向量，期望 ${batchTexts.length}`);
  }
  return parsed;
}

async function embedAll(textsToEmbed, label) {
  const vectors = [];
  let model = '';
  let dimension = 0;
  const startedAt = Date.now();
  for (let offset = 0; offset < textsToEmbed.length; offset += CLIENT_BATCH) {
    const slice = textsToEmbed.slice(offset, offset + CLIENT_BATCH);
    const parsed = await embedBatch(slice, label);
    if (dimension === 0) {
      dimension = parsed.dimension;
      model = parsed.model;
    }
    for (const vector of parsed.vectors) {
      vectors.push(vector);
    }
    const done = Math.min(offset + CLIENT_BATCH, textsToEmbed.length);
    process.stdout.write(`\r  ${label} ${done}/${textsToEmbed.length}  ${Date.now() - startedAt} ms   `);
  }
  process.stdout.write('\n');
  return { vectors, model, dimension, elapsedMs: Date.now() - startedAt };
}

async function main() {
  console.log(`后端    ${BASE}`);
  console.log(`语料    ${chunks.length} 块，长度 ${texts.reduce((sum, t) => sum + t.length, 0)} 字符`);
  console.log(`令牌    ${APP_TOKEN.length > 0 ? `len=${APP_TOKEN.length}` : '（未设置，鉴权应为关闭）'}`);
  console.log('');

  let docVectors = cache.vectors;
  let model = cache.model;
  let dimension = cache.dimension;
  let embedMs = 0;
  if (cache.textsDigest === textsDigest && docVectors.length === texts.length && !REFRESH) {
    console.log(`文档向量  命中缓存（${docVectors.length} × ${dimension}，模型 ${model}）`);
  } else {
    console.log('文档向量  缓存未命中，开始嵌入…');
    const result = await embedAll(texts, '文档');
    docVectors = result.vectors;
    model = result.model;
    dimension = result.dimension;
    embedMs = result.elapsedMs;
    cache = { textsDigest, model, dimension, vectors: docVectors, queries: {} };
    fs.writeFileSync(CACHE_FILE, JSON.stringify(cache));
    console.log(`          完成：${docVectors.length} × ${dimension}，模型 ${model}，${embedMs} ms`);
    console.log(`          缓存已写 ${path.basename(CACHE_FILE)}（${(fs.statSync(CACHE_FILE).size / 1024).toFixed(0)} KB）`);
  }

  const evalCases = evalSetModule.buildKnowledgeEvalSet();
  const queryTexts = evalCases.map((item) => item.query);
  const missing = queryTexts.filter((query) => !cache.queries[query]);
  if (missing.length > 0) {
    console.log(`查询向量  ${missing.length}/${queryTexts.length} 条缺失，开始嵌入…`);
    const result = await embedAll(missing, '查询');
    for (let i = 0; i < missing.length; i++) {
      cache.queries[missing[i]] = result.vectors[i];
    }
    fs.writeFileSync(CACHE_FILE, JSON.stringify(cache));
  } else {
    console.log(`查询向量  命中缓存（${queryTexts.length} 条）`);
  }

  const queryVectors = queryTexts.map((query) => cache.queries[query]);
  const dense = new KnowledgeVectorRetriever();
  const denseOk = dense.build(docVectors, chunks);
  if (!denseOk) {
    throw new Error('稠密侧装不上（向量与块数不匹配）');
  }

  const store = new KnowledgeStore(provider);
  const installed = store.prepareVectors(
    { model, dimension, vectors: docVectors },
    `remote:${model}:${dimension}`);

  const CANDIDATE_DEPTH = HYBRID_CANDIDATE_DEPTH;

  function evaluate(weight) {
    const rows = evalCases.map((item, index) => {
      const lexical = store.search(item.query, CANDIDATE_DEPTH);
      const denseHits = dense.search(queryVectors[index], CANDIDATE_DEPTH);
      const hits = fuseRankings(lexical, denseHits, CANDIDATE_DEPTH, undefined, weight);
      return metricsModule.evaluateCase(hits, item, 3);
    });
    const all = metricsModule.summarize(rows, 3, '');
    return {
      weight,
      recallAt3: all.recallAtK,
      mrr: all.mrr,
      directRecall: metricsModule.summarize(rows, 3, 'direct').recallAtK,
      paraphraseRecall: metricsModule.summarize(rows, 3, 'paraphrase').recallAtK,
    };
  }

  const weights = [0, 0.2, 0.35, 0.5, 0.75, 1, 1.25, 1.5, 2, 3];
  const sweep = weights.map((weight) => evaluate(weight));
  const lexical = sweep[0];
  const best = sweep.reduce((winner, row) => (row.recallAt3 > winner.recallAt3 ? row : winner), sweep[0]);

  // A dense-only ranking, to separate "the vectors are good" from "the fusion
  // lets them through".
  const denseOnlyRows = evalCases.map((item, index) =>
    metricsModule.evaluateCase(dense.search(queryVectors[index], CANDIDATE_DEPTH), item, 3));
  const denseOnly = metricsModule.summarize(denseOnlyRows, 3, '');

  const fmt = (value) => value.toFixed(4);
  console.log('');
  console.log('权重   Recall@3   MRR      direct   paraphrase');
  for (const row of sweep) {
    const marker = row.weight === best.weight ? ' ←最优' : (row.weight === 0 ? '（纯 BM25 基线）' : '');
    console.log(
      `${String(row.weight).padEnd(6)} ${fmt(row.recallAt3)}   ${fmt(row.mrr)}  ${fmt(row.directRecall)}   ${fmt(row.paraphraseRecall)}${marker}`);
  }
  console.log('');
  console.log(`纯向量（不融合）  Recall@3 ${fmt(denseOnly.recallAtK)}  MRR ${fmt(denseOnly.mrr)}`);

  // ---------- storage variants, measured end-to-end ----------
  // Rank agreement is a proxy; the only number that decides a storage format is
  // what it does to Recall@3 through the fusion. Each variant is re-evaluated
  // at the winning weight.
  const finalWeight = best.weight;

  function evaluateVariant(name, docRows, queryRows, storageBytes) {
    const retriever = new KnowledgeVectorRetriever();
    if (!retriever.build(docRows, chunks)) {
      return { name, recallAt3: 0, mrr: 0, kb: 0, ok: false };
    }
    const rows = evalCases.map((item, index) => {
      const lexical = store.search(item.query, CANDIDATE_DEPTH);
      const denseHits = retriever.search(queryRows[index], CANDIDATE_DEPTH);
      const hits = fuseRankings(lexical, denseHits, CANDIDATE_DEPTH, undefined, finalWeight);
      return metricsModule.evaluateCase(hits, item, 3);
    });
    const all = metricsModule.summarize(rows, 3, '');
    return {
      name,
      recallAt3: all.recallAtK,
      mrr: all.mrr,
      paraphraseRecall: metricsModule.summarize(rows, 3, 'paraphrase').recallAtK,
      kb: storageBytes / 1024,
      ok: true,
    };
  }

  function truncate(vector, dim) {
    return normalizeVector(vector.slice(0, dim));
  }

  function quantizeRow(vector) {
    let maxAbs = 0;
    for (const value of vector) {
      maxAbs = Math.max(maxAbs, Math.abs(value));
    }
    const scale = maxAbs > 0 ? maxAbs / 127 : 1;
    return { scale, bytes: vector.map((value) => Math.max(-127, Math.min(127, Math.round(value / scale)))) };
  }

  function quantizeVectors(rows) {
    return rows.map((row) => quantizeRow(row));
  }

  function dequantizeVectors(quantizedRows) {
    return quantizedRows.map((row) => row.bytes.map((value) => value * row.scale));
  }

  /**
   * What the vectors actually cost to store, per encoding. Note this is NOT
   * `JSON.stringify` of the array used for searching: an int8 row searched as
   * floats would be measured at float size, which is exactly the mistake that
   * makes a compression experiment look pointless.
   */
  function storageBytes(rows, encoding) {
    if (encoding === 'float-json') {
      return Buffer.byteLength(JSON.stringify(rows));
    }
    const quantized = quantizeVectors(rows);
    if (encoding === 'int8-json') {
      return Buffer.byteLength(JSON.stringify(quantized.map((row) => row.bytes)));
    }
    // int8 packed as raw bytes, base64'd — what a shipped asset would look like.
    const raw = Buffer.alloc(quantized.length * quantized[0].bytes.length);
    let offset = 0;
    for (const row of quantized) {
      for (const value of row.bytes) {
        raw.writeInt8(value, offset);
        offset += 1;
      }
    }
    const scales = Buffer.alloc(quantized.length * 4);
    quantized.forEach((row, index) => scales.writeFloatLE(row.scale, index * 4));
    return Buffer.byteLength(raw.toString('base64')) + Buffer.byteLength(scales.toString('base64'));
  }

  const variants = [];
  variants.push(evaluateVariant('1024 float', docVectors, queryVectors, storageBytes(docVectors, 'float-json')));
  variants.push(evaluateVariant('1024 int8', dequantizeVectors(quantizeVectors(docVectors)), queryVectors,
    storageBytes(docVectors, 'int8-json')));
  variants.push(evaluateVariant('1024 int8/b64', dequantizeVectors(quantizeVectors(docVectors)), queryVectors,
    storageBytes(docVectors, 'int8-b64')));

  for (const dim of [512, 256]) {
    const docTrunc = docVectors.map((row) => truncate(row, dim));
    const queryTrunc = queryVectors.map((row) => truncate(row, dim));
    variants.push(evaluateVariant(`${dim} float`, docTrunc, queryTrunc, storageBytes(docTrunc, 'float-json')));
    variants.push(evaluateVariant(`${dim} int8/b64`, dequantizeVectors(quantizeVectors(docTrunc)), queryTrunc,
      storageBytes(docTrunc, 'int8-b64')));
  }

  console.log('');
  console.log(`存储方案（都在最优权重 ${finalWeight} 下端到端评测）`);
  console.log('方案         体积       Recall@3   MRR      paraphrase');
  for (const variant of variants) {
    console.log(`${variant.name.padEnd(13)} ${(variant.kb.toFixed(0) + ' KB').padEnd(10)} ` +
      `${fmt(variant.recallAt3)}   ${fmt(variant.mrr)}  ${fmt(variant.paraphraseRecall)}`);
  }
  console.log(`（BM25 基线体积为 0，Recall@3 ${fmt(lexical.recallAt3)}）`);

  console.log('');
  console.log('结论');
  const delta = best.recallAt3 - lexical.recallAt3;
  console.log(`  最优权重 ${best.weight}：Recall@3 ${fmt(lexical.recallAt3)} → ${fmt(best.recallAt3)}（${delta >= 0 ? '+' : ''}${fmt(delta)}）`);
  console.log(`  换句话问（paraphrase）：${fmt(lexical.paraphraseRecall)} → ${fmt(best.paraphraseRecall)}`);
  console.log(`  代码里当前的默认权重是 0.35，对应 Recall@3 ${fmt(sweep[2].recallAt3)}（那是为哈希替身调的，对真模型偏低）`);
  console.log(`  稠密侧装上：${installed}`);
  console.log(`  文档嵌入耗时：${embedMs > 0 ? `${embedMs} ms（本次实付）` : '本次命中缓存，未计时'}`);

  return delta > 0 ? 0 : 1;
}

main().then((code) => {
  process.exitCode = code;
}).catch((error) => {
  console.error('');
  console.error(`失败：${error && error.message}`);
  if (error && /ECONNREFUSED/.test(String(error.message))) {
    console.error(`后端没起来？先跑： cd server && set -a && . ./.env && set +a && npm start`);
  }
  process.exitCode = 3;
});

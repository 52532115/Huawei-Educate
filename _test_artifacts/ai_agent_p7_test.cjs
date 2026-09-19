// Offline tests for P7: RAG foundations — chunking, tokenizing, BM25 retrieval.
//
// Groups A-E exercise the three new pure services with real inputs; group F is
// the static guardrail set (no clock, no I/O, no second copy of the mojibake
// detector or the knowledge-tag cleaner). Nothing here needs AppStorage or a
// file system, which is exactly the point of keeping retrieval logic pure.
const fs = require('fs');
const path = require('path');

function loadTypeScript() {
  const vendored = 'D:/devecostudio-windows-6.0.2.650/DevEco Studio/tools/hvigor/hvigor/node_modules/typescript';
  if (fs.existsSync(vendored)) {
    return require(vendored);
  }
  return require('typescript');
}

const ts = loadTypeScript();

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

// Modules under test are compiled and run inside new Function, so anything they
// construct has to be reachable from the prelude in that scope.
const SERVICE_DIR = 'features/aiagent/src/main/ets/service/';
const MODEL_DIR = 'features/aiagent/src/main/ets/viewmodel/';

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

// Imports are stripped before the module runs, so the shared helpers the RAG
// code reuses must be injected from the already-loaded source module.
const SHARED_DEPS = `
const { isCorruptedText, normalizeKnowledgeTag, normalizeQuestionTitle } = global.__sourceModule;
`;

global.__sourceModule = loadArkTs(`${SERVICE_DIR}ErrorBookPracticeSource.ets`, SOURCE_PRELUDE);

// The codec has to exist before the index, because the index takes its hash and
// its build signature from it.
const codecModule = loadArkTs(`${SERVICE_DIR}KnowledgeSnapshotCodec.ets`, MODEL_STUB);
global.__codecModule = codecModule;

const chunkerModule = loadArkTs(`${SERVICE_DIR}KnowledgeChunker.ets`, `${SHARED_DEPS}\n${MODEL_STUB}`);
const indexModule = loadArkTs(`${SERVICE_DIR}KnowledgeIndex.ets`,
  `${MODEL_STUB}\nconst { hashString } = global.__codecModule;`);
const corpusModule = loadArkTs(`${SERVICE_DIR}KnowledgeSeedCorpus.ets`, `${SHARED_DEPS}\n${MODEL_STUB}`);

// The catalogue and the store are loaded from the real modules too — the store
// is only given a stub AdaptivePracticeService, because the point of the
// provider seam is that the retriever never builds the app's data services.
global.__chunkerModule = chunkerModule;
global.__indexModule = indexModule;
global.__corpusModule = corpusModule;

const catalogModule = loadArkTs(`${SERVICE_DIR}KnowledgeCourseCatalog.ets`, `${SHARED_DEPS}\n${MODEL_STUB}`);
global.__catalogModule = catalogModule;

// Embedding sits on top of both the tokenizer and the hash, and the vector
// retriever on top of the embedding maths — so each is loaded from the real
// source with only those two symbols injected. This has to come after the index
// module has been published, because the embedder borrows its tokenizer.
const embeddingModule = loadArkTs(`${SERVICE_DIR}KnowledgeEmbedding.ets`,
  `${MODEL_STUB}\nconst { tokenizeWithUnigrams } = global.__indexModule;\n` +
  `const { hashString } = global.__codecModule;`);
global.__embeddingModule = embeddingModule;
const vectorModule = loadArkTs(`${SERVICE_DIR}KnowledgeVectorRetriever.ets`,
  `${MODEL_STUB}\nconst { cosineSimilarity } = global.__embeddingModule;`);
global.__vectorModule = vectorModule;

// The shipped course notes are real content, not fixtures: the store test has
// to see the same notes the app indexes, so the whole note chain is loaded for
// real. It only depends on the model stub plus one helper, so this stays cheap.
global.__notesSupport = loadArkTs(`${SERVICE_DIR}KnowledgeNotesSupport.ets`, MODEL_STUB);

const NOTE_FILES = [
  ['KnowledgeNotesCalculus.ets', 'buildCalculusOneNotes'],
  ['KnowledgeNotesAlgebra.ets', 'buildAlgebraNotes'],
  ['KnowledgeNotesProbability.ets', 'buildProbabilityNotes'],
  ['KnowledgeNotesPhysics.ets', 'buildPhysicsNotes'],
  ['KnowledgeNotesProgramming.ets', 'buildProgrammingNotes'],
  ['KnowledgeNotesDataStructure.ets', 'buildDataStructureNotes'],
  ['KnowledgeNotesArchitecture.ets', 'buildComputerOrganizationNotes'],
  ['KnowledgeNotesOperatingSystem.ets', 'buildOperatingSystemNotes'],
  ['KnowledgeNotesNetwork.ets', 'buildComputerNetworkNotes'],
  ['KnowledgeNotesDatabase.ets', 'buildDatabaseNotes'],
  ['KnowledgeNotesCompiler.ets', 'buildCompilerNotes'],
  ['KnowledgeNotesSoftware.ets', 'buildSoftwareEngineeringNotes'],
  ['KnowledgeNotesGraphics.ets', 'buildGraphicsNotes'],
  ['KnowledgeNotesSecurity.ets', 'buildSecurityNotes'],
  ['KnowledgeNotesMl.ets', 'buildMachineLearningNotes'],
  ['KnowledgeNotesWeb.ets', 'buildWebLinuxNotes'],
];

global.__noteBuilders = {};
let catalogPrelude = `${MODEL_STUB}\n`;
for (const [file, builder] of NOTE_FILES) {
  const noteModule = loadArkTs(`${SERVICE_DIR}${file}`,
    `const { makeLecture } = global.__notesSupport;\n${MODEL_STUB}`);
  global.__noteBuilders[builder] = noteModule[builder];
  catalogPrelude += `const ${builder} = global.__noteBuilders['${builder}'];\n`;
}
const notesCatalogModule = loadArkTs(`${SERVICE_DIR}KnowledgeNotesCatalog.ets`, catalogPrelude);
global.__notesCatalogModule = notesCatalogModule;

// The index store is loaded twice on purpose. Bare (no AppStorage, no fileIo) it
// is the situation every other test group runs in, and it has to degrade to
// "no cache" instead of throwing. Group J loads it again against an in-memory
// fs stub to exercise the real read/write path.
//
// The codec symbols are injected by the loader rather than left to the caller:
// forgetting one makes `save` throw inside its own try/catch, which turns a
// broken prelude into a silently disabled cache instead of a failure.
function loadIndexStore(fsPrelude) {
  return loadArkTs(`${SERVICE_DIR}KnowledgeIndexStore.ets`,
    `${fsPrelude}\nconst { encodeSnapshot, decodeSnapshot } = global.__codecModule;\n${MODEL_STUB}`);
}
global.__indexStoreModule = loadIndexStore('');
global.__loadIndexStore = loadIndexStore;

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

const {
  KnowledgeChunker, parseHeadingLine,
  CHUNK_TARGET_CHARS, CHUNK_MAX_CHARS, CHUNK_MIN_CHARS, CHUNK_OVERLAP_CHARS,
} = chunkerModule;
const { KnowledgeIndex, tokenize, Bm25Config } = indexModule;
const { KnowledgeSeedCorpus } = corpusModule;
const { buildCourseCatalog, CATALOG_ROW_COUNT } = catalogModule;
const { buildLectureNotes } = notesCatalogModule;
const { KnowledgeStore, KnowledgeCorpusProvider, KNOWLEDGE_DEFAULT_TOP_K, KNOWLEDGE_WARMUP_DELAY_MS,
  describeKnowledgeSource } = storeModule;

const chunker = new KnowledgeChunker();
const corpus = new KnowledgeSeedCorpus();

// ---------- fixtures ----------

function makeDoc(docId, title, text, tag = '', sourceType = 'course_note', courseId = '') {
  return { docId, title, text, knowledgeTag: tag, sourceType, courseId };
}

function makeChunk(chunkId, title, text, headingPath = '') {
  return {
    chunkId, docId: 'd', title, headingPath, courseId: '',
    knowledgeTag: '未分类', sourceType: 'course_note', text, chunkIndex: 0,
  };
}

function buildIndex(chunks) {
  const index = new KnowledgeIndex();
  index.build(chunks);
  return index;
}

// ---------- A. chunking ----------

check('A 分块', 'parseHeadingLine：1~6 级识别，7 级不算标题（与 MarkdownText 同规则）',
  parseHeadingLine('# 数据结构').level === 1 &&
  parseHeadingLine('## 树').level === 2 &&
  parseHeadingLine('###### 六级').level === 6 &&
  parseHeadingLine('####### 七级') === null,
  {
    h1: parseHeadingLine('# 数据结构').level, h2: parseHeadingLine('## 树').level,
    h6: parseHeadingLine('###### 六级').level, h7: parseHeadingLine('####### 七级'),
  },
  { h1: 1, h2: 2, h6: 6, h7: null });

check('A 分块', 'parseHeadingLine：无空格 / 空标题 / 纯正文都不是标题',
  parseHeadingLine('#没有空格') === null && parseHeadingLine('#') === null &&
  parseHeadingLine('# ') === null && parseHeadingLine('普通正文') === null &&
  parseHeadingLine('') === null,
  {
    noSpace: parseHeadingLine('#没有空格'), bare: parseHeadingLine('#'),
    blank: parseHeadingLine('# '), plain: parseHeadingLine('普通正文'),
  },
  'all null');

check('A 分块', 'parseHeadingLine：允许行首缩进，标题文本已 trim',
  parseHeadingLine('  ## 缩进标题  ').level === 2 && parseHeadingLine('  ## 缩进标题  ').text === '缩进标题',
  parseHeadingLine('  ## 缩进标题  '), { level: 2, text: '缩进标题' });

const nestedText = [
  '# 数据结构',
  '## 树',
  '### 二叉搜索树',
  '节点左子树的所有键都小于该节点。',
  '## 图',
  '图的遍历分为深度优先和广度优先两种。',
].join('\n');
const nestedSections = chunker.splitIntoSections(nestedText);
check('A 分块', 'splitIntoSections：按标题切段，共 4 段',
  nestedSections.length === 4,
  nestedSections.map(s => s.heading), ['数据结构', '树', '二叉搜索树', '图']);

check('A 分块', 'splitIntoSections：标题路径逐级下钻，遇同级标题回退到上一层',
  nestedSections[2].headingPath.join('>') === '数据结构>树>二叉搜索树' &&
  nestedSections[3].headingPath.join('>') === '数据结构>图',
  {
    third: nestedSections[2].headingPath, fourth: nestedSections[3].headingPath,
  },
  { third: ['数据结构', '树', '二叉搜索树'], fourth: ['数据结构', '图'] });

const fencedSections = chunker.splitIntoSections(
  '## 代码示例\n\n```\n# 这不是标题\n```\n\n普通正文');

check('A 分块', 'splitIntoSections：围栏代码块内的 # 不当作标题',
  fencedSections.length === 1 && fencedSections[0].body.indexOf('# 这不是标题') >= 0,
  { count: fencedSections.length, keepsCodeLine: fencedSections[0].body.indexOf('# 这不是标题') >= 0 },
  { count: 1, keepsCodeLine: true });

const preludeSections = chunker.splitIntoSections('这是一段没有标题的课程笔记，讲的是三次握手的过程。');
check('A 分块', 'splitIntoSections：无标题文本落成一段前言，标题路径为空',
  preludeSections.length === 1 && preludeSections[0].level === 0 &&
  preludeSections[0].headingPath.length === 0,
  { count: preludeSections.length, level: preludeSections[0].level, path: preludeSections[0].headingPath },
  { count: 1, level: 0, path: [] });

const deepDoc = makeDoc('docA', '数据结构',
  '# 数据结构\n## 树\n### 二叉搜索树\n\n' +
  '二叉搜索树的中序遍历结果是一个递增序列，这是它最重要的性质之一，插入和删除都要维持左小右大的有序性。\n');
const deepChunks = chunker.buildChunks([deepDoc]);
check('A 分块', 'buildChunks：标题路径用 › 连接，title 取最近一级标题',
  deepChunks.length === 1 && deepChunks[0].headingPath === '数据结构 › 树 › 二叉搜索树' &&
  deepChunks[0].title === '二叉搜索树',
  { count: deepChunks.length, path: deepChunks[0].headingPath, title: deepChunks[0].title },
  { count: 1, path: '数据结构 › 树 › 二叉搜索树', title: '二叉搜索树' });

const P1 = 'A'.repeat(150);
const P2 = 'A'.repeat(150);
const P3 = 'A'.repeat(150);
const packChunks = chunker.buildChunks([makeDoc('docP', '块测试', `## 块\n\n${P1}\n\n${P2}\n\n${P3}\n`)]);
check('A 分块', `合并到目标长度：150+1+150=301 ≤ ${CHUNK_TARGET_CHARS} 合成一块，再加第三段超限另起一块`,
  packChunks.length === 2 && packChunks[0].text.length === 301 &&
  packChunks[0].text === `${P1}\n${P2}`,
  { count: packChunks.length, firstLength: packChunks[0].text.length },
  { count: 2, firstLength: 301 });

check('A 分块', `相邻块带重叠：第二块 = 尾重叠(${CHUNK_OVERLAP_CHARS}) + 换行 + 本段，共 60+1+150=211`,
  packChunks[1].text.length === 211 && packChunks[1].text.endsWith(P3),
  { secondLength: packChunks[1].text.length, endsWithP3: packChunks[1].text.endsWith(P3) },
  { secondLength: 211, endsWithP3: true });

const SENTENCE = '这是一句测试用的中文句子，长度为二十五个字符。';
const longParagraph = SENTENCE.repeat(25);
const longChunks = chunker.buildChunks([makeDoc('docL', '长段测试', `## 长\n\n${longParagraph}\n`)]);
check('A 分块', '超长段落按句子边界切：575 字的段落切在 552（第 24 句末），而不是硬切在 560',
  longChunks.length === 2 && longChunks[0].text.length === 552,
  { count: longChunks.length, firstLength: longChunks[0].text.length, secondLength: longChunks[1].text.length },
  { count: 2, firstLength: 552 });

check('A 分块', '切入点是句号，第二块保留原段尾部',
  longChunks[0].text.endsWith('。') && longChunks[1].text.endsWith(SENTENCE) &&
  longChunks[1].text.length > SENTENCE.length,
  {
    endsWithPeriod: longChunks[0].text.endsWith('。'),
    keepsTail: longChunks[1].text.endsWith(SENTENCE),
  },
  { endsWithPeriod: true, keepsTail: true });

check('A 分块', `短于 ${CHUNK_MIN_CHARS} 字的块被丢弃`,
  chunker.buildChunks([makeDoc('docS', '短', '## 短\n\n太短了。')]).length === 0,
  chunker.buildChunks([makeDoc('docS', '短', '## 短\n\n太短了。')]).length, 0);

const corruptedDoc = makeDoc('docM', '乱码',
  '## 乱码\n\n锛堝这是一段足够长的正常中文内容，用于验证乱码块会被整块丢掉而不是进入索引。');
check('A 分块', '含乱码的块被丢弃（复用同一套乱码判定）',
  chunker.buildChunks([corruptedDoc]).length === 0 &&
  chunker.buildChunks([makeDoc('docM2', '正常',
    '## 正常\n\n这是一段足够长的正常中文内容，用于验证正常块不会被误杀。')]).length === 1,
  {
    corrupted: chunker.buildChunks([corruptedDoc]).length,
    healthy: chunker.buildChunks([makeDoc('docM2', '正常',
      '## 正常\n\n这是一段足够长的正常中文内容，用于验证正常块不会被误杀。')]).length,
  },
  { corrupted: 0, healthy: 1 });

const tagChunks = chunker.buildChunks([
  makeDoc('docT1', '标签', '## 标签\n\n知识点标签归一化测试，内容足够长以便通过最小长度阈值。', '鏁版嵁缁撴瀯'),
  makeDoc('docT2', '标签2', '## 标签2\n\n知识点标签归一化测试，内容足够长以便通过最小长度阈值。', '  计算机网络  '),
  makeDoc('docT3', '标签3', '## 标签3\n\n知识点标签归一化测试，内容足够长以便通过最小长度阈值。', ''),
]);
check('A 分块', 'tag 归一化：乱码→未分类、带空格→trim、空→未分类',
  tagChunks[0].knowledgeTag === '未分类' && tagChunks[1].knowledgeTag === '计算机网络' &&
  tagChunks[2].knowledgeTag === '未分类',
  tagChunks.map(c => c.knowledgeTag), ['未分类', '计算机网络', '未分类']);

check('A 分块', 'chunkId 稳定且连续：k_<docId>_<序号>，序号只为成功入块的块递增',
  packChunks.map(c => c.chunkId).join('|') === 'k_docP_0|k_docP_1' &&
  packChunks.map(c => c.chunkIndex).join('|') === '0|1',
  { ids: packChunks.map(c => c.chunkId), index: packChunks.map(c => c.chunkIndex) },
  { ids: ['k_docP_0', 'k_docP_1'], index: [0, 1] });

const multiDoc = [deepDoc, makeDoc('docP', '块测试', `## 块\n\n${P1}\n\n${P2}\n\n${P3}\n`)];
check('A 分块', '同输入两次 → 完全相同的 chunkId 序列与文本（确定性，无时钟无随机）',
  chunker.buildChunks(multiDoc).map(c => `${c.chunkId}:${c.text.length}`).join('|') ===
  chunker.buildChunks(multiDoc).map(c => `${c.chunkId}:${c.text.length}`).join('|'),
  chunker.buildChunks(multiDoc).map(c => c.chunkId), ['k_docA_0', 'k_docP_0', 'k_docP_1']);

check('A 分块', 'docId 为空或正文为空的文档被跳过，不产生悬空块',
  chunker.buildChunks([makeDoc('', '无 id', '## 有内容\n\n内容内容内容内容内容内容内容内容内容内容内容内容。')]).length === 0 &&
  chunker.buildChunks([makeDoc('docE', '空', '   ')]).length === 0,
  {
    noId: chunker.buildChunks([makeDoc('', '无 id', '## 有内容\n\n内容内容内容内容内容内容内容内容内容内容内容内容。')]).length,
    empty: chunker.buildChunks([makeDoc('docE', '空', '   ')]).length,
  },
  { noId: 0, empty: 0 });

// ---------- B. tokenizing ----------

check('B 分词', '中文按 bigram 切分：三次握手 → 三次 / 次握 / 握手',
  tokenize('三次握手').join('|') === '三次|次握|握手',
  tokenize('三次握手'), ['三次', '次握', '握手']);

check('B 分词', '单字自成 token，停用字被丢弃',
  tokenize('数').join('|') === '数' && tokenize('的').length === 0 && tokenize('了').length === 0,
  { single: tokenize('数'), stop: tokenize('的'), stop2: tokenize('了') },
  { single: ['数'], stop: [], stop2: [] });

check('B 分词', '拉丁字母与数字连读并小写化：BM25 TCP → bm25 / tcp',
  tokenize('BM25 TCP').join('|') === 'bm25|tcp',
  tokenize('BM25 TCP'), ['bm25', 'tcp']);

check('B 分词', '两个停用字组成的 bigram 被丢，含一个实字的 bigram 保留',
  tokenize('的和').length === 0 && tokenize('数据').join('|') === '数据',
  { both: tokenize('的和'), one: tokenize('数据') },
  { both: [], one: ['数据'] });

check('B 分词', '全角标点只做切分，不进入 token',
  tokenize('TCP，三次握手。').join('|') === 'tcp|三次|次握|握手',
  tokenize('TCP，三次握手。'), ['tcp', '三次', '次握', '握手']);

check('B 分词', '空串与非字符串输入返回空数组',
  tokenize('').length === 0 && tokenize(null).length === 0 && tokenize(undefined).length === 0,
  { empty: tokenize('').length, nullish: tokenize(null).length },
  { empty: 0, nullish: 0 });

check('B 分词', '单字母拉丁 token 与英文停用词被丢弃',
  tokenize('a b').length === 0 && tokenize('the data').join('|') === 'data',
  { single: tokenize('a b'), stop: tokenize('the data') },
  { single: [], stop: ['data'] });

// ---------- C. index ----------

const tinyIndex = buildIndex([makeChunk('k_tiny', '树', '二叉树')]);
const tinyStats = tinyIndex.stats();
check('C 建索引', '统计口径：标题加权两次 + 正文 → 4 个 token / 3 个词项 / 平均长度 4',
  tinyStats.chunkCount === 1 && tinyStats.termCount === 3 && tinyStats.avgChunkLength === 4,
  tinyStats, { chunkCount: 1, termCount: 3, avgChunkLength: 4 });

const emptyIndex = buildIndex([]);
const emptyStats = emptyIndex.stats();
check('C 建索引', '空索引可用：isEmpty 为真、统计全 0、检索返回空',
  emptyIndex.isEmpty() && emptyStats.chunkCount === 0 && emptyStats.termCount === 0 &&
  emptyStats.avgChunkLength === 0 && emptyIndex.search('任意查询').length === 0,
  { isEmpty: emptyIndex.isEmpty(), stats: emptyStats, hits: emptyIndex.search('任意查询').length },
  { isEmpty: true, chunkCount: 0, hits: 0 });

const boostIndex = buildIndex([
  makeChunk('k_title', '三次握手', '网络协议基础内容的说明段落'),
  makeChunk('k_body', '网络协议基础内容', '三次握手'),
]);
const boostHits = boostIndex.search('三次握手', 5);
check('C 建索引', '标题加权：标题命中排在正文命中之前',
  boostHits.length === 2 && boostHits[0].chunk.chunkId === 'k_title',
  boostHits.map(h => `${h.chunk.chunkId}:${h.score}`),
  'k_title first');

check('C 建索引', 'BM25 参数可注入（用自定义 k1/b 重建仍可检索）',
  (() => {
    const config = new Bm25Config();
    config.k1 = 1.0;
    config.b = 0.5;
    const index = new KnowledgeIndex(config);
    index.build([makeChunk('k_cfg', '调度', '进程调度算法')]);
    return index.search('调度', 3).length === 1;
  })(),
  'injectable', true);

// ---------- D. retrieval ----------

const RETRIEVAL_CHUNKS = [
  makeChunk('k_a', '数据结构', '二叉搜索树的中序遍历结果是递增序列。'),
  makeChunk('k_b', '计算机网络', '三次握手用于建立 TCP 连接，需要交换 SYN 和 ACK。'),
  makeChunk('k_c', '操作系统', '进程调度算法包括先来先服务和短作业优先。'),
];
const retrievalIndex = buildIndex(RETRIEVAL_CHUNKS);

const handshakeHits = retrievalIndex.search('三次握手', 5);
check('D 检索', '关键词命中：三次握手 → 只命中计算机网络那块',
  handshakeHits.length === 1 && handshakeHits[0].chunk.chunkId === 'k_b',
  handshakeHits.map(h => h.chunk.chunkId), ['k_b']);

check('D 检索', '命中词回填 matchedTerms，按查询词顺序',
  handshakeHits[0].matchedTerms.join('|') === '三次|次握|握手',
  handshakeHits[0].matchedTerms, ['三次', '次握', '握手']);

check('D 检索', '中文查询不加空格也能命中：进程调度 → 操作系统那块',
  retrievalIndex.search('进程调度', 5)[0].chunk.chunkId === 'k_c',
  retrievalIndex.search('进程调度', 5).map(h => h.chunk.chunkId), 'k_c first');

check('D 检索', '无重叠查询返回空，而不是退回全量块',
  retrievalIndex.search('量子力学').length === 0,
  retrievalIndex.search('量子力学').length, 0);

check('D 检索', '空查询与纯停用词查询都返回空',
  retrievalIndex.search('').length === 0 && retrievalIndex.search('的了是').length === 0,
  { empty: retrievalIndex.search('').length, stop: retrievalIndex.search('的了是').length },
  { empty: 0, stop: 0 });

check('D 检索', 'topK 生效且不越界（topK=2 命中 3 块时只返回 2）',
  (() => {
    const index = buildIndex([
      makeChunk('k_1', '数据', '数据结构的说明内容'),
      makeChunk('k_2', '数据2', '数据结构的说明内容'),
      makeChunk('k_3', '数据3', '数据结构的说明内容'),
    ]);
    return index.search('数据', 2).length === 2 && index.search('数据', 99).length === 3 &&
      index.search('数据', 0).length === 0;
  })(),
  'topK respected', true);

check('D 检索', '同 query 两次 → chunkId 序列与分数完全一致（确定性）',
  (() => {
    const first = retrievalIndex.search('三次握手 TCP', 5);
    const second = retrievalIndex.search('三次握手 TCP', 5);
    return first.map(h => `${h.chunk.chunkId}:${h.score}`).join('|') ===
      second.map(h => `${h.chunk.chunkId}:${h.score}`).join('|');
  })(),
  'identical', true);

check('D 检索', '分数打平按 chunkId 升序（总序，不依赖插入顺序）',
  (() => {
    const index = buildIndex([
      makeChunk('k_z', '并列', '相同内容用于并列测试'),
      makeChunk('k_a', '并列', '相同内容用于并列测试'),
    ]);
    const hits = index.search('并列', 5);
    return hits.length === 2 && hits[0].chunk.chunkId === 'k_a' && hits[1].chunk.chunkId === 'k_z';
  })(),
  'k_a before k_z', true);

check('D 检索', '分数为正且保留到 4 位小数（可直接写进断言）',
  handshakeHits[0].score > 0 &&
  Math.abs(handshakeHits[0].score * 10000 - Math.round(handshakeHits[0].score * 10000)) < 0.01,
  handshakeHits[0].score, 'positive, rounded to 4 decimals');

// ---------- E. seed corpus ----------

const courseDocs = corpus.buildDocuments([
  {
    courseId: '1', title: '高等数学（上）', category: '数学基础',
    description: '函数、极限、连续、一元函数微积分学、向量代数与空间解析几何',
  },
], []);
check('E 语料', '课程 → 文档：id 前缀、分类作为 knowledgeTag、sourceType=course',
  courseDocs.length === 1 && courseDocs[0].docId === 'doc_course_1' &&
  courseDocs[0].knowledgeTag === '数学基础' && courseDocs[0].sourceType === 'course' &&
  courseDocs[0].courseId === '1',
  {
    count: courseDocs.length, docId: courseDocs[0].docId,
    tag: courseDocs[0].knowledgeTag, type: courseDocs[0].sourceType,
  },
  { count: 1, docId: 'doc_course_1', tag: '数学基础', type: 'course' });

check('E 语料', '课程文档正文用 ## 标题组织，分块后能拿到「课程：xxx」标题',
  courseDocs[0].text.indexOf('## 课程：高等数学（上）') === 0 &&
  courseDocs[0].text.indexOf('所属分类：数学基础') >= 0 &&
  courseDocs[0].text.indexOf('课程简介：') >= 0,
  courseDocs[0].text, 'starts with ## 课程：, has 所属分类 and 课程简介');

const questionDocs = corpus.buildDocuments([], [
  {
    questionId: 'q1', title: '三次握手的第二步是什么？', options: ['SYN', 'SYN+ACK'],
    correctIndex: 1, knowledgeTag: '计算机网络', explanation: '服务端回 SYN+ACK。',
    recommendation: '复习 TCP 建连过程。',
  },
]);
check('E 语料', '题目 → 文档：选项带字母前缀、sourceType=question_bank、含解析小节',
  questionDocs.length === 1 && questionDocs[0].docId === 'doc_q_q1' &&
  questionDocs[0].sourceType === 'question_bank' &&
  questionDocs[0].text.indexOf('A. SYN') >= 0 && questionDocs[0].text.indexOf('B. SYN+ACK') >= 0 &&
  questionDocs[0].text.indexOf('## 解析与建议') >= 0,
  {
    docId: questionDocs[0].docId, type: questionDocs[0].sourceType,
    hasLabels: questionDocs[0].text.indexOf('A. SYN') >= 0,
    hasAnalysis: questionDocs[0].text.indexOf('## 解析与建议') >= 0,
  },
  { docId: 'doc_q_q1', type: 'question_bank', hasLabels: true, hasAnalysis: true });

check('E 语料', '题干与选项同段，块标题带上题目原文（利于标题加权命中）',
  chunker.buildChunks(questionDocs)[0].title.indexOf('三次握手的第二步是什么？') >= 0,
  chunker.buildChunks(questionDocs).map(c => c.title),
  'first chunk title contains the question stem');

check('E 语料', '缺信息的条目跳过：无 id / 无标题 / 无简介的课程与题目都不入档',
  corpus.buildDocuments([
    { courseId: '', title: '无 id', category: 'x', description: '描述' },
    { courseId: '9', title: '', category: 'x', description: '描述' },
    { courseId: '10', title: '无简介', category: 'x', description: '' },
  ], [
    { questionId: '', title: '无 id', options: ['A'], correctIndex: 0, knowledgeTag: '', explanation: '', recommendation: '' },
    { questionId: 'q9', title: '   ', options: ['A'], correctIndex: 0, knowledgeTag: '', explanation: '', recommendation: '' },
  ]).length === 0,
  corpus.buildDocuments([
    { courseId: '', title: '无 id', category: 'x', description: '描述' },
    { courseId: '9', title: '', category: 'x', description: '描述' },
    { courseId: '10', title: '无简介', category: 'x', description: '' },
  ], [
    { questionId: '', title: '无 id', options: ['A'], correctIndex: 0, knowledgeTag: '', explanation: '', recommendation: '' },
    { questionId: 'q9', title: '   ', options: ['A'], correctIndex: 0, knowledgeTag: '', explanation: '', recommendation: '' },
  ]).length, 0);

check('E 语料', '去重：同 courseId 的课程只留一份，同题干的题目只留一份（手录重复不再产生两块）',
  corpus.buildDocuments([
    { courseId: '1', title: '高等数学（上）', category: '数学基础', description: '描述一' },
    { courseId: '1', title: '高等数学（上）', category: '数学基础', description: '描述二' },
  ], [
    { questionId: 'qA', title: '同一道题 的题干', options: ['A', 'B'], correctIndex: 0, knowledgeTag: '数学', explanation: '', recommendation: '' },
    { questionId: 'qB', title: '同一道题   的题干', options: ['A', 'B'], correctIndex: 0, knowledgeTag: '数学', explanation: '', recommendation: '' },
  ]).length === 2,
  corpus.buildDocuments([
    { courseId: '1', title: '高等数学（上）', category: '数学基础', description: '描述一' },
    { courseId: '1', title: '高等数学（上）', category: '数学基础', description: '描述二' },
  ], [
    { questionId: 'qA', title: '同一道题 的题干', options: ['A', 'B'], correctIndex: 0, knowledgeTag: '数学', explanation: '', recommendation: '' },
    { questionId: 'qB', title: '同一道题   的题干', options: ['A', 'B'], correctIndex: 0, knowledgeTag: '数学', explanation: '', recommendation: '' },
  ]).length, 2);

check('E 语料', '题目 tag 归一化：乱码 → 未分类',
  corpus.buildDocuments([], [
    {
      questionId: 'q7', title: '乱码标签题目', options: ['A', 'B'], correctIndex: 0,
      knowledgeTag: '鏁版嵁缁撴瀯', explanation: '', recommendation: '',
    },
  ])[0].knowledgeTag === '未分类',
  corpus.buildDocuments([], [
    {
      questionId: 'q7', title: '乱码标签题目', options: ['A', 'B'], correctIndex: 0,
      knowledgeTag: '鏁版嵁缁撴瀯', explanation: '', recommendation: '',
    },
  ])[0].knowledgeTag, '未分类');

// End-to-end: the seed corpus must be retrievable without any new content.
const e2eDocuments = corpus.buildDocuments([
  { courseId: '20', title: '计算机网络', category: '计算机网络', description: 'OSI 七层模型、TCP/IP 协议栈、可靠传输与拥塞控制' },
], [
  {
    questionId: 'q_tcp', title: '三次握手的第二步是什么？', options: ['SYN', 'SYN+ACK'],
    correctIndex: 1, knowledgeTag: '计算机网络', explanation: '服务端回 SYN+ACK 表示同意建连。',
    recommendation: '复习 TCP 建立连接的全过程。',
  },
]);
const e2eIndex = buildIndex(chunker.buildChunks(e2eDocuments));
const e2eHits = e2eIndex.search('三次握手', 3);
check('E 语料', '端到端：现有语料 → 分块 → 建索引 → 查询能命中题目块',
  e2eDocuments.length === 2 && e2eHits.length >= 1 &&
  e2eHits[0].chunk.docId === 'doc_q_q_tcp',
  {
    docs: e2eDocuments.length, hits: e2eHits.length,
    top: e2eHits.length > 0 ? e2eHits[0].chunk.docId : null,
  },
  { docs: 2, top: 'doc_q_q_tcp' });

check('E 语料', '端到端：命中块带着可引用的出处（标题路径 + 知识点）',
  e2eHits[0].chunk.knowledgeTag === '计算机网络' &&
  e2eHits[0].chunk.title.indexOf('三次握手的第二步是什么？') >= 0,
  { tag: e2eHits[0].chunk.knowledgeTag, title: e2eHits[0].chunk.title },
  { tag: '计算机网络', titleContains: '三次握手' });

// ---------- G. course catalogue + retrieval facade ----------

const G_COURSES = [
  {
    courseId: '13', title: '计算机网络', category: '计算机网络',
    description: '网络体系结构、物理层、数据链路层、网络层、传输层、应用层、网络安全',
  },
  {
    courseId: '9', title: '数据结构', category: '数据结构',
    description: '线性表、栈与队列、树与二叉树、图、查找、排序',
  },
];
const G_QUESTIONS = [
  {
    questionId: 'q_tcp', title: '三次握手的第二步是什么？',
    options: ['SYN', 'SYN+ACK', 'ACK', 'FIN'], correctIndex: 1,
    knowledgeTag: '计算机网络',
    explanation: '服务端回 SYN+ACK，表示同意建立连接。',
    recommendation: '复习 TCP 建立连接的全过程。',
  },
];

/** The provider seam exists so the retriever can be tested without the app. */
function makeProvider(courses, questions, lectures = []) {
  return {
    getCourses: () => courses,
    getQuestions: () => questions,
    getLectures: () => lectures,
  };
}

const catalog = buildCourseCatalog();
check('G 目录', `课程目录共 ${CATALOG_ROW_COUNT} 行，仅「计算机组成原理」重复故去重为 ${CATALOG_ROW_COUNT - 1} 门`,
  CATALOG_ROW_COUNT === 25 && catalog.length === 24 &&
  catalog.filter(c => c.title === '计算机组成原理').length === 1,
  { rows: CATALOG_ROW_COUNT, kept: catalog.length, dup: catalog.filter(c => c.title === '计算机组成原理').length },
  { rows: 25, kept: 24, dup: 1 });

check('G 目录', '去重保留先出现的那门（专业核心版，简介更完整）',
  catalog.find(c => c.title === '计算机组成原理').category === '专业核心' &&
  catalog.find(c => c.title === '计算机组成原理').description.indexOf('输入输出系统') >= 0,
  catalog.find(c => c.title === '计算机组成原理').category, '专业核心');

check('G 目录', '每门课都有 id / 标题 / 分类 / 简介，且 id 不重复',
  catalog.every(c => c.courseId.length > 0 && c.title.length > 0 &&
    c.category.length > 0 && c.description.length > 0) &&
  new Set(catalog.map(c => c.courseId)).size === catalog.length,
  { missing: catalog.filter(c => !c.courseId || !c.title || !c.category || !c.description).map(c => c.title) },
  'all fields present, ids unique');

const emptyStore = new KnowledgeStore(makeProvider([], []));
const emptyStoreStats = emptyStore.stats();
check('G 检索门面', '空语料可用：统计全 0，检索返回空而非报错',
  emptyStoreStats.chunkCount === 0 && emptyStore.search('三次握手').length === 0,
  { chunks: emptyStoreStats.chunkCount, hits: emptyStore.search('三次握手').length },
  { chunks: 0, hits: 0 });

// G stays on a tiny fixture corpus with no lecture notes, so the facade checks
// assert on numbers this file can spell out. The real shipped notes (and the
// note-aware path through the store) are covered by group I below.
const store = new KnowledgeStore(makeProvider(G_COURSES, G_QUESTIONS, []));
const storeStats = store.stats();
const expectedChunkCount =
  chunker.buildChunks(corpus.buildDocuments(G_COURSES, G_QUESTIONS, [])).length;
check('G 检索门面', `懒构建：门面统计的块数与「语料 → 分块」独立跑一遍的结果一致（${expectedChunkCount} 块）`,
  storeStats.chunkCount === expectedChunkCount && storeStats.chunkCount > 0 &&
  storeStats.termCount > 0 && storeStats.avgChunkLength > 0,
  storeStats, { chunkCount: expectedChunkCount, termCount: '>0', avgChunkLength: '>0' });

const storeHits = store.search('三次握手');
check('G 检索门面', '端到端命中：只凭课程目录 + 题库就能检索到题解',
  storeHits.length > 0 && storeHits[0].chunk.docId === 'doc_q_q_tcp',
  storeHits.map(h => `${h.chunk.chunkId}:${h.score}`), 'doc_q_q_tcp first');

check('G 检索门面', '同一 query 两次 → 完全相同的 chunkId 与分数（确定性）',
  (() => {
    const a = store.search('三次握手 TCP');
    const b = store.search('三次握手 TCP');
    return a.map(h => `${h.chunk.chunkId}:${h.score}`).join('|') ===
      b.map(h => `${h.chunk.chunkId}:${h.score}`).join('|');
  })(), 'identical', true);

check('G 检索门面', '未命中返回空，交给调用方降级（不返回兜底内容）',
  store.search('量子纠缠的贝尔不等式').length === 0,
  store.search('量子纠缠的贝尔不等式').length, 0);

check('G 检索门面', `默认 topK = ${KNOWLEDGE_DEFAULT_TOP_K}，且默认调用不会超出该上限`,
  KNOWLEDGE_DEFAULT_TOP_K === 4 && store.search('计算机网络 传输层 三次握手').length <= 4,
  { topK: KNOWLEDGE_DEFAULT_TOP_K, returned: store.search('计算机网络 传输层 三次握手').length },
  { topK: 4, returned: '<=4' });

check('G 检索门面', 'getInstance 返回同一实例（索引全进程只建一次）',
  KnowledgeStore.getInstance() === KnowledgeStore.getInstance(),
  'same instance', 'same instance');

check('G 检索门面', 'invalidate 后重新构建，检索依旧可用',
  (() => {
    store.invalidate();
    return store.search('三次握手').length > 0 && store.stats().chunkCount === expectedChunkCount;
  })(), 'rebuilt', true);

check('G 检索门面', '语料构建抛异常时降级为空索引，不把异常抛给会话',
  (() => {
    const broken = new KnowledgeStore({
      getCourses() { throw new Error('corpus unavailable'); },
      getQuestions() { return []; },
      getLectures() { return []; },
    });
    return broken.search('三次握手').length === 0 && broken.stats().chunkCount === 0;
  })(), 'degraded to empty', true);

check('G 检索门面', '语料来源只有讲义、课程、题库三项公开数据（不碰个人学习数据）',
  (() => {
    const asked = [];
    const probe = new KnowledgeStore({
      getCourses() { asked.push('courses'); return []; },
      getQuestions() { asked.push('questions'); return []; },
      getLectures() { asked.push('lectures'); return []; },
    });
    probe.stats();
    return asked.join('|') === 'courses|questions|lectures';
  })(), 'courses|questions|lectures', 'courses|questions|lectures');

check('G 检索门面', 'buildContextBlock：空命中返回空串（不产生空的资料块）',
  store.buildContextBlock([]) === '', JSON.stringify(store.buildContextBlock([])), "''");

const block = store.buildContextBlock(storeHits);
check('G 检索门面', 'buildContextBlock：带编号、来源、出处、知识点与原文',
  block.indexOf('【检索到的课程资料】') === 0 &&
  block.indexOf('[1]（题库解析）') > 0 &&
  block.indexOf('题目：三次握手的第二步是什么？') > 0 &&
  block.indexOf('知识点：计算机网络') > 0 &&
  block.indexOf('服务端回 SYN+ACK') > 0,
  block.slice(0, 200), 'header + numbered passage + citation + tag + text');

check('G 检索门面', 'buildContextBlock 不含引用指令（引用规则只写在系统提示里，避免两处口径）',
  block.indexOf('标注') < 0 && block.indexOf('请用') < 0,
  { hasInstruction: block.indexOf('标注') >= 0 || block.indexOf('请用') >= 0 }, { hasInstruction: false });

check('G 检索门面', 'citationOf：有标题路径用路径，没有才回退到 title',
  store.citationOf({ chunk: makeChunk('k_x', '标题', '正文', '课程 › 章节'), score: 1, matchedTerms: [] }) === '课程 › 章节' &&
  store.citationOf({ chunk: makeChunk('k_y', '标题', '正文', ''), score: 1, matchedTerms: [] }) === '标题',
  {
    withPath: store.citationOf({ chunk: makeChunk('k_x', '标题', '正文', '课程 › 章节'), score: 1, matchedTerms: [] }),
    without: store.citationOf({ chunk: makeChunk('k_y', '标题', '正文', ''), score: 1, matchedTerms: [] }),
  },
  { withPath: '课程 › 章节', without: '标题' });

check('G 检索门面', '来源文案四类齐全（课程大纲 / 题库解析 / 错题本 / 课程笔记）',
  describeKnowledgeSource('course') === '课程大纲' &&
  describeKnowledgeSource('question_bank') === '题库解析' &&
  describeKnowledgeSource('error_book') === '错题本' &&
  describeKnowledgeSource('course_note') === '课程笔记',
  ['course', 'question_bank', 'error_book', 'course_note'].map(describeKnowledgeSource),
  ['课程大纲', '题库解析', '错题本', '课程笔记']);

// ---------- F. static guardrails ----------

function stripArkTsComments(source) {
  return source.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
}

function readSource(relativePath) {
  return stripArkTsComments(fs.readFileSync(path.join(root, relativePath), 'utf8'));
}

const chunkerSrc = readSource(`${SERVICE_DIR}KnowledgeChunker.ets`);
const indexSrc = readSource(`${SERVICE_DIR}KnowledgeIndex.ets`);
const corpusSrc = readSource(`${SERVICE_DIR}KnowledgeSeedCorpus.ets`);
const catalogSrc = readSource(`${SERVICE_DIR}KnowledgeCourseCatalog.ets`);
const storeSrc = readSource(`${SERVICE_DIR}KnowledgeStore.ets`);
const codecSrc = readSource(`${SERVICE_DIR}KnowledgeSnapshotCodec.ets`);
const ragSources = [chunkerSrc, indexSrc, corpusSrc, catalogSrc, storeSrc, codecSrc];

check('F 静态', `六个 RAG service（含目录、门面与快照编解码）都不读时钟、不用随机数（同输入必然同输出）`,
  ragSources.every(src => src.indexOf('Date.now') < 0 && src.indexOf('Math.random') < 0),
  ragSources.map(src => ({ now: src.indexOf('Date.now') >= 0, random: src.indexOf('Math.random') >= 0 })),
  'no clock, no RNG');

check('F 静态', '五个 RAG service 都不碰 AppStorage / fileIo（保持纯逻辑，可离线裸测）',
  ragSources.every(src => src.indexOf('AppStorage') < 0 && src.indexOf('fileIo') < 0),
  ragSources.map(src => ({ appStorage: src.indexOf('AppStorage') >= 0, fileIo: src.indexOf('fileIo') >= 0 })),
  'no I/O');



check('F 静态', '乱码判定只有一处：chunker 复用 isCorruptedText，没有第二份实现',
  chunkerSrc.indexOf('isCorruptedText') >= 0 &&
  chunkerSrc.indexOf('function isCorruptedText') < 0 &&
  chunkerSrc.indexOf('锛') < 0 && chunkerSrc.indexOf('0xE000') < 0,
  {
    usesShared: chunkerSrc.indexOf('isCorruptedText') >= 0,
    definesOwn: chunkerSrc.indexOf('function isCorruptedText') >= 0,
    markerList: chunkerSrc.indexOf('锛') >= 0 || chunkerSrc.indexOf('0xE000') >= 0,
  },
  { usesShared: true, definesOwn: false, markerList: false });

check('F 静态', 'tag 归一化复用 ErrorBookPracticeSource，没有第二张「未分类」映射表',
  chunkerSrc.indexOf('normalizeKnowledgeTag') >= 0 &&
  corpusSrc.indexOf('normalizeKnowledgeTag') >= 0 &&
  chunkerSrc.indexOf("'未分类'") < 0 && corpusSrc.indexOf("'未分类'") < 0,
  {
    chunker: chunkerSrc.indexOf('normalizeKnowledgeTag') >= 0,
    corpus: corpusSrc.indexOf('normalizeKnowledgeTag') >= 0,
    hardcoded: chunkerSrc.indexOf("'未分类'") >= 0 || corpusSrc.indexOf("'未分类'") >= 0,
  },
  { chunker: true, corpus: true, hardcoded: false });

check('F 静态', '题干去重复用 normalizeQuestionTitle（与错题本同一套清洗规则）',
  corpusSrc.indexOf('normalizeQuestionTitle') >= 0,
  corpusSrc.indexOf('normalizeQuestionTitle') >= 0, true);

check('F 静态', '目录里的课程名去重也走 normalizeQuestionTitle，没有第二套标题清洗',
  catalogSrc.indexOf('normalizeQuestionTitle') >= 0 &&
  catalogSrc.indexOf('function normalizeQuestionTitle') < 0,
  {
    reuses: catalogSrc.indexOf('normalizeQuestionTitle') >= 0,
    redefines: catalogSrc.indexOf('function normalizeQuestionTitle') >= 0,
  },
  { reuses: true, redefines: false });

check('F 静态', '检索门面不重复实现乱码判定 / tag 归一化 / 题干清洗（只有一处判定）',
  storeSrc.indexOf('isCorruptedText') < 0 && storeSrc.indexOf('normalizeKnowledgeTag') < 0 &&
  storeSrc.indexOf('normalizeQuestionTitle') < 0 && storeSrc.indexOf("'未分类'") < 0,
  {
    corruption: storeSrc.indexOf('isCorruptedText') >= 0,
    tag: storeSrc.indexOf('normalizeKnowledgeTag') >= 0,
    title: storeSrc.indexOf('normalizeQuestionTitle') >= 0,
  },
  { corruption: false, tag: false, title: false });

check('F 静态', '检索门面把语料来源收敛到一个 provider 类，viewmodel 层不直接碰分块与索引',
  storeSrc.indexOf('class KnowledgeCorpusProvider') >= 0 &&
  storeSrc.indexOf('KnowledgeChunker') >= 0 && storeSrc.indexOf('KnowledgeSeedCorpus') >= 0,
  {
    provider: storeSrc.indexOf('class KnowledgeCorpusProvider') >= 0,
    usesChunker: storeSrc.indexOf('KnowledgeChunker') >= 0,
  },
  { provider: true, usesChunker: true });

check('F 静态', 'BM25 参数只在 Bm25Config 里出现一次，打分路径全部走 this.config',
  indexSrc.indexOf('this.config.k1') >= 0 && indexSrc.indexOf('this.config.b') >= 0 &&
  indexSrc.split('1.2').length - 1 === 1 && indexSrc.split('0.75').length - 1 === 1,
  {
    usesK1: indexSrc.indexOf('this.config.k1') >= 0,
    usesB: indexSrc.indexOf('this.config.b') >= 0,
    k1Literals: indexSrc.split('1.2').length - 1,
    bLiterals: indexSrc.split('0.75').length - 1,
  },
  { usesK1: true, usesB: true, k1Literals: 1, bLiterals: 1 });

// ---------- H. intent routing + wiring guardrails ----------

const routerSrc = readSource('features/aiagent/src/main/ets/service/IntentRouter.ets');
const routerModule = loadArkTs('features/aiagent/src/main/ets/service/IntentRouter.ets');
const router = new routerModule.IntentRouter();
const Intent = routerModule.ChatIntent;

check('H 路由', 'KNOWLEDGE 已加入意图枚举',
  Intent.KNOWLEDGE === 'knowledge',
  Intent.KNOWLEDGE, 'knowledge');

const routeCases = [
  // PRACTICE must keep winning: a practice request that mentions knowledge
  // words is still a practice request.
  ['帮我出几道极限题练练手', Intent.PRACTICE, '练习'],
  ['讲讲这道练习题涉及的知识点', Intent.PRACTICE, '练习优先于知识'],
  // ANALYTICS must keep winning: anything about the learner's own data has to
  // reach the tools, never the retriever.
  ['帮我分析一下我的学习情况', Intent.ANALYTICS, '学习情况'],
  ['我的课程进度怎么样', Intent.ANALYTICS, '课程进度'],
  ['为什么我的成绩下降了', Intent.ANALYTICS, '数据词优先于「为什么」'],
  ['如何提高考试成绩', Intent.ANALYTICS, '数据词优先于「如何」'],
  // Subject questions take the new path.
  ['什么是三次握手', Intent.KNOWLEDGE, '什么是'],
  ['二叉搜索树的中序遍历有什么特点', Intent.KNOWLEDGE, '概念问句'],
  ['进程和线程的区别是什么', Intent.KNOWLEDGE, '区别'],
  ['解释一下动态规划的重叠子问题', Intent.KNOWLEDGE, '解释'],
  // Everything else stays a plain, search-free reply.
  ['你好呀', Intent.CHAT, '闲聊'],
  ['今天天气不错', Intent.CHAT, '闲聊'],
];
for (const [text, expected, why] of routeCases) {
  const got = router.route(text);
  check('H 路由', `"${text}" → ${expected}（${why}）`, got === expected, got, expected);
}

check('H 路由', '判定顺序写死在 route 里：PRACTICE → ANALYTICS → KNOWLEDGE',
  (() => {
    const body = routerSrc.substring(routerSrc.indexOf('route(text'));
    const practice = body.indexOf('PRACTICE_KEYWORDS');
    const analytics = body.indexOf('ANALYTICS_KEYWORDS');
    const knowledge = body.indexOf('KNOWLEDGE_KEYWORDS');
    return practice >= 0 && analytics > practice && knowledge > analytics;
  })(),
  (() => {
    const body = routerSrc.substring(routerSrc.indexOf('route(text'));
    return {
      practice: body.indexOf('PRACTICE_KEYWORDS'),
      analytics: body.indexOf('ANALYTICS_KEYWORDS'),
      knowledge: body.indexOf('KNOWLEDGE_KEYWORDS'),
    };
  })(),
  'practice < analytics < knowledge');

const chatVmSrc = readSource('features/aiagent/src/main/ets/viewmodel/ChatViewModel.ets');
const rkStart = chatVmSrc.indexOf('private async runKnowledgeChat');
// Bounded on the next method that FOLLOWS it in the file, which is runAgentChat.
const rkEnd = chatVmSrc.indexOf('private async runAgentChat');
const knowledgeBody = rkStart >= 0 && rkEnd > rkStart ? chatVmSrc.substring(rkStart, rkEnd) : '';

check('H 接线', 'ChatViewModel 把 KNOWLEDGE 分流到知识问答分支',
  chatVmSrc.indexOf('ChatIntent.KNOWLEDGE') >= 0 && chatVmSrc.indexOf('runKnowledgeChat') >= 0 &&
  knowledgeBody.length > 0,
  {
    branch: chatVmSrc.indexOf('ChatIntent.KNOWLEDGE') >= 0,
    method: chatVmSrc.indexOf('runKnowledgeChat') >= 0,
    bodyLength: knowledgeBody.length,
  },
  { branch: true, method: true, bodyLength: '>0' });

check('H 接线', '知识问答只发一次对话请求，不进 agent 工具循环',
  knowledgeBody.indexOf('chatWithFallback') >= 0 && knowledgeBody.indexOf('agentService') < 0,
  {
    singleRequest: knowledgeBody.indexOf('chatWithFallback') >= 0,
    usesAgent: knowledgeBody.indexOf('agentService') >= 0,
  },
  { singleRequest: true, usesAgent: false });

check('H 接线', '检索为空时降级为普通对话（宁可不过度作答，也不编造出处）',
  knowledgeBody.indexOf('runPlainChat') >= 0 && knowledgeBody.indexOf('length === 0') >= 0,
  {
    fallsBack: knowledgeBody.indexOf('runPlainChat') >= 0,
    guardsEmpty: knowledgeBody.indexOf('length === 0') >= 0,
  },
  { fallsBack: true, guardsEmpty: true });

check('H 接线', '检索资料作为系统消息注入，且排在历史之后、用户提问之前',
  chatVmSrc.indexOf('extraSystemBlock: string = ') >= 0 &&
  chatVmSrc.indexOf('blockMsg.role = \'system\'') >= 0 &&
  chatVmSrc.indexOf('buildContextBlock') >= 0,
  {
    param: chatVmSrc.indexOf('extraSystemBlock: string = ') >= 0,
    injection: chatVmSrc.indexOf('blockMsg.role = \'system\'') >= 0,
  },
  { param: true, injection: true });

const constantsSrc = readSource('features/aiagent/src/main/ets/utils/AiConstants.ets');
check('H 提示词', '知识问答系统提示要求标注出处、并禁止编造出处',
  constantsSrc.indexOf('KNOWLEDGE_SYSTEM_PROMPT') >= 0 &&
  constantsSrc.indexOf('【出处】') >= 0 && constantsSrc.indexOf('不得编造课程出处') >= 0,
  {
    prompt: constantsSrc.indexOf('KNOWLEDGE_SYSTEM_PROMPT') >= 0,
    citation: constantsSrc.indexOf('【出处】') >= 0,
    noFabrication: constantsSrc.indexOf('不得编造课程出处') >= 0,
  },
  { prompt: true, citation: true, noFabrication: true });

const toolsSrc = readSource(`${SERVICE_DIR}AgentTools.ets`);
check('H 工具', 'search_course_knowledge 三处齐全：执行分支、工具定义、步骤文案',
  (toolsSrc.split('search_course_knowledge').length - 1) >= 3 &&
  toolsSrc.indexOf('正在检索课程知识…') >= 0,
  {
    occurrences: toolsSrc.split('search_course_knowledge').length - 1,
    label: toolsSrc.indexOf('正在检索课程知识…') >= 0,
  },
  { occurrences: '>=3', label: true });

check('H 工具', '第 8 个工具是第一个带参数的：query 为必填，其余 7 个仍无参数',
  toolsSrc.indexOf('required: [\'query\']') >= 0 &&
  toolsSrc.indexOf("properties: properties") >= 0,
  {
    required: toolsSrc.indexOf('required: [\'query\']') >= 0,
    properties: toolsSrc.indexOf('properties: properties') >= 0,
  },
  { required: true, properties: true });

check('H 工具', 'query 缺失或参数格式错误时返回 error，而不是静默做一次空检索',
  toolsSrc.indexOf('缺少 query 参数') >= 0 && toolsSrc.indexOf('function parseToolQuery') >= 0,
  {
    explicitError: toolsSrc.indexOf('缺少 query 参数') >= 0,
    parser: toolsSrc.indexOf('function parseToolQuery') >= 0,
  },
  { explicitError: true, parser: true });

check('H 工具', '知识库未命中时工具明确回报「课程资料未覆盖」，把不编造写进返回值',
  toolsSrc.indexOf('课程资料未覆盖该知识点') >= 0,
  toolsSrc.indexOf('课程资料未覆盖该知识点') >= 0, true);

// ---------- I. shipped lecture notes ----------

const notes = buildLectureNotes();
const catalogIds = catalog.map(c => c.courseId).slice().sort();
const noteIds = notes.map(n => n.courseId).slice().sort();
const missingNotes = catalogIds.filter(id => noteIds.indexOf(id) < 0);
const orphanNotes = noteIds.filter(id => catalogIds.indexOf(id) < 0);

check('I 讲义', `讲义与目录逐门对齐：${notes.length} 门，courseId 集合完全一致`,
  notes.length === catalog.length && missingNotes.length === 0 && orphanNotes.length === 0,
  { notes: notes.length, catalog: catalog.length, missingNotes, orphanNotes },
  { notes: catalog.length, missingNotes: [], orphanNotes: [] });

const MIN_NOTE_CHARS = 400;
const thinNotes = notes.filter(n => n.markdown.trim().length < MIN_NOTE_CHARS);
const incompleteNotes = notes.filter(n => !n.courseId || !n.title || !n.category || !n.knowledgeTag);
check('I 讲义', `每门讲义 id / 标题 / 分类 / tag 齐全，正文不少于 ${MIN_NOTE_CHARS} 字`,
  incompleteNotes.length === 0 && thinNotes.length === 0,
  {
    incomplete: incompleteNotes.map(n => n.courseId),
    thinnest: Math.min(...notes.map(n => n.markdown.trim().length)),
  },
  { incomplete: [], thinnest: `>=${MIN_NOTE_CHARS}` });

// The opening heading is what puts the course name into every chunk's citation
// path, so it is structure, not decoration.
const badOpening = notes.filter(n => n.markdown.split('\n')[0].trim() !== `## ${n.title}`);
check('I 讲义', '每门讲义都以「## 课程名」开头（出处才能带上课程名）',
  badOpening.length === 0,
  badOpening.map(n => n.markdown.split('\n')[0].trim()),
  'all open with ## <course title>');

// Course title is the tag the question bank uses for the same subject, so a
// learner who just failed a question and asks about it lands on the note.
const badTag = notes.filter(n => n.knowledgeTag !== n.title);
check('I 讲义', '讲义 tag 取课程名（与题库同科目的 tag 同口径，无需第二张映射表）',
  badTag.length === 0,
  badTag.map(n => `${n.title}→${n.knowledgeTag}`),
  []);

const sectionCounts = notes.map(n =>
  n.markdown.split('\n').filter(line => /^#{2,4} /.test(line.trim())).length);
check('I 讲义', '每门讲义至少 4 个二~四级标题（保证能被切成多个可检索章节）',
  Math.min(...sectionCounts) >= 4,
  { min: Math.min(...sectionCounts), max: Math.max(...sectionCounts) },
  { min: '>=4' });

const BACKTICK = String.fromCharCode(96);
const backtickNotes = notes.filter(n => n.markdown.indexOf(BACKTICK) >= 0);
check('I 讲义', '讲义不含反引号（模板字符串里刻意避开，防止转义把正文吃掉）',
  backtickNotes.length === 0,
  backtickNotes.map(n => n.title),
  []);

const twice = buildLectureNotes();
check('I 讲义', '讲义构建是纯的：两次调用得到相同的 courseId 与正文长度序列',
  twice.map(n => `${n.courseId}:${n.markdown.length}`).join('|') ===
  notes.map(n => `${n.courseId}:${n.markdown.length}`).join('|'),
  'identical', 'identical');

// ---------- I. lecture notes: corpus adapter ----------

const noteDocs = corpus.buildDocuments([], [], notes);
check('I 适配', `讲义 → 文档：docId 前缀 doc_note_、sourceType=course_note、正文原样入档（${noteDocs.length} 篇）`,
  noteDocs.length === notes.length &&
  noteDocs.every((d, i) => d.docId === `doc_note_${notes[i].courseId}` &&
    d.sourceType === 'course_note' &&
    d.courseId === notes[i].courseId &&
    d.text === notes[i].markdown.trim()),
  {
    count: noteDocs.length,
    firstId: noteDocs[0].docId,
    verbatim: noteDocs[0].text === notes[0].markdown.trim(),
  },
  { count: notes.length, firstId: 'doc_note_1', verbatim: true });

check('I 适配', '讲义按 courseId 去重：同一门课交两遍只产生一篇文档',
  corpus.buildDocuments([], [], [notes[0], notes[0]]).length === 1,
  corpus.buildDocuments([], [], [notes[0], notes[0]]).length, 1);

check('I 适配', '缺 id / 缺标题 / 缺正文的讲义都被跳过（不产生空文档）',
  corpus.buildDocuments([], [], [
    { courseId: '', title: '无 id', category: 'c', knowledgeTag: 't', markdown: '正文'.repeat(30) },
    { courseId: '98', title: '   ', category: 'c', knowledgeTag: 't', markdown: '正文'.repeat(30) },
    { courseId: '99', title: '无正文', category: 'c', knowledgeTag: 't', markdown: '   ' },
    notes[1],
  ]).length === 1,
  corpus.buildDocuments([], [], [
    { courseId: '', title: '无 id', category: 'c', knowledgeTag: 't', markdown: '正文'.repeat(30) },
    { courseId: '98', title: '   ', category: 'c', knowledgeTag: 't', markdown: '正文'.repeat(30) },
    { courseId: '99', title: '无正文', category: 'c', knowledgeTag: 't', markdown: '   ' },
    notes[1],
  ]).length, 1);

check('I 适配', '讲义 tag 归一化：乱码 tag → 未分类（复用同一套判定）',
  corpus.buildDocuments([], [], [
    { courseId: '97', title: '乱码标签讲义', category: 'c', knowledgeTag: '鏁版嵁缁撴瀯', markdown: '正文'.repeat(30) },
  ])[0].knowledgeTag === '未分类',
  corpus.buildDocuments([], [], [
    { courseId: '97', title: '乱码标签讲义', category: 'c', knowledgeTag: '鏁版嵁缁撴瀯', markdown: '正文'.repeat(30) },
  ])[0].knowledgeTag, '未分类');

check('I 适配', '讲义 tag 为空时回退到课程名，而不是落到未分类',
  corpus.buildDocuments([], [], [
    { courseId: '96', title: '操作系统', category: 'c', knowledgeTag: '', markdown: '正文'.repeat(30) },
  ])[0].knowledgeTag === '操作系统',
  corpus.buildDocuments([], [], [
    { courseId: '96', title: '操作系统', category: 'c', knowledgeTag: '', markdown: '正文'.repeat(30) },
  ])[0].knowledgeTag, '操作系统');

// ---------- I. lecture notes: end-to-end through the store ----------

// The real provider, fed a one-question bank: the point is the shipped notes
// and the shipped catalogue, which are the two things this milestone added.
global.__providerBank = [
  {
    id: 'q_tcp_note', title: 'TCP 相比 UDP 最典型的特征是？',
    options: ['无连接', '可靠传输', '不校验数据', '一定更快'], correctIndex: 1,
    knowledgeTag: '计算机网络',
    explanation: 'TCP 面向连接，提供可靠传输；UDP 无连接、开销较小。',
    recommendation: '比较协议时从连接性、可靠性、开销和典型场景四个维度入手。',
  },
];
const realProvider = new KnowledgeCorpusProvider();
const realStore = new KnowledgeStore(realProvider);

const realDocs = corpus.buildDocuments(
  realProvider.getCourses(), realProvider.getQuestions(), realProvider.getLectures());
const realChunks = chunker.buildChunks(realDocs);
const chunksPerNoteDoc = new Map();
realChunks.forEach(c => {
  if (c.sourceType === 'course_note') {
    chunksPerNoteDoc.set(c.docId, (chunksPerNoteDoc.get(c.docId) || 0) + 1);
  }
});
const noteChunkCount = realChunks.filter(c => c.sourceType === 'course_note').length;
const thinChunkedNotes = notes.filter(n => (chunksPerNoteDoc.get(`doc_note_${n.courseId}`) || 0) < 3);

check('I 端到端', `每门讲义至少切出 3 块（碎片化不足会丢检索信号），共 ${noteChunkCount} 块`,
  thinChunkedNotes.length === 0,
  thinChunkedNotes.map(n => `${n.title}:${chunksPerNoteDoc.get(`doc_note_${n.courseId}`) || 0}`),
  []);

check('I 端到端', '门面懒构建的结果与独立计算逐块一致（讲义确实进索引了）',
  realStore.stats().chunkCount === realChunks.length && realStore.stats().chunkCount > noteChunkCount,
  { store: realStore.stats().chunkCount, independent: realChunks.length, notes: noteChunkCount },
  { equal: true, notes: '>0' });

const tcpHits = realStore.search('TCP 三次握手 建立连接', 5);
const tcpNoteHit = tcpHits.find(h => h.chunk.sourceType === 'course_note');
check('I 端到端', '「三次握手」命中课程讲义，而不是只能命中题库解析',
  Boolean(tcpNoteHit),
  tcpHits.map(h => `${h.chunk.docId}#${h.chunk.title}`),
  'a course_note hit');

check('I 端到端', '命中出处可读：引用路径带课程名与章节名',
  Boolean(tcpNoteHit) && realStore.citationOf(tcpNoteHit).indexOf('计算机网络') >= 0 &&
  realStore.citationOf(tcpNoteHit).indexOf(' › ') > 0,
  tcpNoteHit ? realStore.citationOf(tcpNoteHit) : null,
  '计算机网络 › …');

// The closed loop that matters for a learner: fail a question, ask why, land on
// the note. Every tag the shipped question bank uses must reach a note.
const BANK_TAGS = [
  '函数与极限', '导数与微分', '不定积分', '定积分', '无穷级数',
  '数据结构', '算法设计与分析', '操作系统', '计算机网络',
  '数据库系统原理', '编译原理', '软件工程',
];
const tagsWithoutNote = BANK_TAGS.filter(tag =>
  !realStore.search(tag, 5).some(h => h.chunk.sourceType === 'course_note'));
check('I 端到端', `题库的 ${BANK_TAGS.length} 个知识点都能检索到讲义（做题→追问的闭环）`,
  tagsWithoutNote.length === 0,
  tagsWithoutNote,
  []);

check('I 端到端', '资料块带上课程笔记的来源文案，模型才知道引用的是讲义而不是题目',
  (() => {
    if (!tcpNoteHit) {
      return false;
    }
    const block = realStore.buildContextBlock([tcpNoteHit]);
    return block.indexOf('课程笔记') >= 0 && block.indexOf('[1]') >= 0 &&
      block.indexOf('知识点：计算机网络') >= 0;
  })(), 'labelled course notes', true);

// ---------- I. lecture notes: static guardrails ----------

const noteSources = NOTE_FILES.map(([file]) => readSource(`${SERVICE_DIR}${file}`));
const noteSupportSrc = readSource(`${SERVICE_DIR}KnowledgeNotesSupport.ets`);
const noteCatalogSrc = readSource(`${SERVICE_DIR}KnowledgeNotesCatalog.ets`);
const noteLayerSources = [noteSupportSrc, noteCatalogSrc].concat(noteSources);

check('I 静态', `${noteLayerSources.length} 个讲义文件（含聚合入口与构造器）都不读时钟、不用随机数、不碰 I/O`,
  noteLayerSources.every(src => src.indexOf('Date.now') < 0 && src.indexOf('Math.random') < 0 &&
    src.indexOf('AppStorage') < 0 && src.indexOf('fileIo') < 0),
  {
    strict: noteLayerSources.filter(src => src.indexOf('Date.now') >= 0 || src.indexOf('Math.random') >= 0).length,
    io: noteLayerSources.filter(src => src.indexOf('AppStorage') >= 0 || src.indexOf('fileIo') >= 0).length,
  },
  { strict: 0, io: 0 });

check('I 静态', '所有讲义都经 makeLecture 构造（单一构造入口，没有各自 new）',
  noteSources.every(src => src.indexOf('makeLecture') >= 0 && src.indexOf('new SeedLectureInput') < 0),
  noteSources.filter(src => src.indexOf('makeLecture') < 0 || src.indexOf('new SeedLectureInput') >= 0).length,
  0);

check('I 静态', '讲义层不重复实现 tag 归一化 / 乱码判定（只有一处判定）',
  noteLayerSources.every(src => src.indexOf('normalizeKnowledgeTag') < 0 &&
    src.indexOf('isCorruptedText') < 0 && src.indexOf("'未分类'") < 0),
  noteLayerSources.map(src => ({
    tag: src.indexOf('normalizeKnowledgeTag') >= 0,
    corruption: src.indexOf('isCorruptedText') >= 0,
  })).filter(x => x.tag || x.corruption).length,
  0);

check('I 静态', `聚合入口没有漏掉任何讲义文件（${NOTE_FILES.length} 个 builder 之和 = ${notes.length} 门）`,
  NOTE_FILES.reduce((sum, [, builder]) => sum + global.__noteBuilders[builder]().length, 0) === notes.length,
  NOTE_FILES.reduce((sum, [, builder]) => sum + global.__noteBuilders[builder]().length, 0),
  notes.length);

// ---------- J. index persistence (filesDir + derived cache keys) ----------

const { hashString, fingerprintChunks, encodeSnapshot, decodeSnapshot, KNOWLEDGE_SNAPSHOT_VERSION } = codecModule;
const { KnowledgeIndexStore } = global.__indexStoreModule;

check('J 编码', 'hashString 定长 7 位十六进制、同输入同输出、异输入异输出',
  hashString('三次握手') === hashString('三次握手') &&
  hashString('三次握手') !== hashString('四次挥手') &&
  hashString('三次握手').length === 7 && hashString('').length === 7,
  { same: hashString('三次握手'), other: hashString('四次挥手') },
  'stable 7-char hex, distinct');

const fpA = fingerprintChunks(chunker.buildChunks(corpus.buildDocuments(G_COURSES, G_QUESTIONS)));
const fpB = fingerprintChunks(chunker.buildChunks(corpus.buildDocuments(G_COURSES, G_QUESTIONS)));
const fpEdited = fingerprintChunks(chunker.buildChunks(corpus.buildDocuments(G_COURSES, G_QUESTIONS))
  .map((c, i) => (i === 0 ? Object.assign({}, c, { text: c.text + '补充一段' }) : c)));

check('J 编码', '语料指纹是确定性的：同一语料两次计算相同',
  fpA === fpB && fpA.length === 7, { a: fpA, b: fpB }, 'identical');

check('J 编码', '语料指纹会随正文变化而变（改了讲义就必须重建）',
  fpA !== fpEdited, { before: fpA, after: fpEdited }, 'different');

check('J 编码', '语料指纹会随块数变化而变（增删课程同理）',
  fingerprintChunks(chunker.buildChunks(corpus.buildDocuments(G_COURSES, G_QUESTIONS))) !==
  fingerprintChunks(chunker.buildChunks(corpus.buildDocuments(G_COURSES, [])).slice(0, 1)),
  'differs', 'differs');

check('J 编码', '空语料不抛异常（首启失败也不能把门面打挂）',
  (() => { try { return typeof fingerprintChunks([]) === 'string'; } catch (e) { return false; } })(),
  'string', true);

// --- state round trip: the persisted postings must reproduce the same ranking ---
const rtIndex = new KnowledgeIndex();
rtIndex.build(realChunks);
const rtState = rtIndex.exportState();
const rtJson = encodeSnapshot((() => {
  const snap = { version: KNOWLEDGE_SNAPSHOT_VERSION, fingerprint: 'fp', signature: 'sg',
    chunks: realChunks, state: rtState, vectors: [] };
  return snap;
})());
const rtDecoded = decodeSnapshot(rtJson);
const rtRestored = new KnowledgeIndex();
const rtOk = rtRestored.importState(rtDecoded.state, rtDecoded.chunks);
const rtBefore = rtIndex.search('TCP 三次握手 为什么要三次', 5).map(h => h.chunk.chunkId).join('|');
const rtAfter = rtRestored.search('TCP 三次握手 为什么要三次', 5).map(h => h.chunk.chunkId).join('|');

check('J 状态', '倒排表导出→序列化→反序列化→导入后，检索结果逐条一致',
  rtOk && rtAfter === rtBefore && rtBefore.length > 0,
  { imported: rtOk, before: rtBefore.slice(0, 60), after: rtAfter.slice(0, 60) },
  { imported: true, same: true });

check('J 状态', '导出的状态与索引规模一致（terms 与 postings 等长、chunkLengths 对齐 chunk 数）',
  rtState.terms.length === rtState.postings.length &&
  rtState.chunkLengths.length === realChunks.length && rtState.terms.length > 1000,
  { terms: rtState.terms.length, postings: rtState.postings.length, lengths: rtState.chunkLengths.length },
  { equalPairs: true, lengths: realChunks.length });

check('J 状态', '导入时 chunk 数对不上 → 拒绝导入，且不留下半截索引',
  (() => {
    const victim = new KnowledgeIndex();
    const rejected = !victim.importState(rtState, realChunks.slice(0, 3));
    return rejected && victim.search('三次握手', 5).length === 0;
  })(), 'rejected + empty', true);

check('J 状态', '导入时倒排表长度为奇数 → 拒绝（损坏的数据必须读不出结果，而不是读出错结果）',
  (() => {
    const broken = { chunkLengths: rtState.chunkLengths.slice(), averageLength: rtState.averageLength,
      terms: ['三次'], postings: [[0, 1, 1]] };
    return new KnowledgeIndex().importState(broken, realChunks) === false;
  })(), false, false);

// --- decode rejects every shape of bad file ---
check('J 解码', '空串 / 非 JSON / 版本不符 → 一律 null（回退重建，不试图修复）',
  decodeSnapshot('') === null && decodeSnapshot('这不是 json') === null &&
  (() => {
    const wrongVersion = JSON.parse(rtJson);
    wrongVersion.version = KNOWLEDGE_SNAPSHOT_VERSION + 1;
    return decodeSnapshot(JSON.stringify(wrongVersion)) === null;
  })(),
  'all null', 'all null');

check('J 解码', 'chunkLengths 与 chunk 数不一致 → null',
  (() => {
    const bad = JSON.parse(rtJson);
    bad.state.chunkLengths = bad.state.chunkLengths.slice(0, 2);
    return decodeSnapshot(JSON.stringify(bad)) === null;
  })(), null, null);

check('J 解码', '倒排表里混入非数值 → null（不让 NaN 进打分公式）',
  (() => {
    const bad = JSON.parse(rtJson);
    bad.state.postings[0] = ['三次', 1];
    return decodeSnapshot(JSON.stringify(bad)) === null;
  })(), null, null);

check('J 解码', '向量的条数既不是 0 也不是 chunk 数 → null（位置错位会算错块）',
  (() => {
    const bad = JSON.parse(rtJson);
    bad.vectors = [[1, 0, 0]];
    return decodeSnapshot(JSON.stringify(bad)) === null;
  })(), null, null);

check('J 解码', '合法载荷解码后 chunk 字段逐项还原（含 sourceType 与 headingPath）',
  rtDecoded !== null && rtDecoded.chunks.length === realChunks.length &&
  rtDecoded.chunks[0].chunkId === realChunks[0].chunkId &&
  rtDecoded.chunks[0].headingPath === realChunks[0].headingPath &&
  rtDecoded.chunks[0].sourceType === realChunks[0].sourceType &&
  rtDecoded.fingerprint === 'fp' && rtDecoded.signature === 'sg',
  { chunks: rtDecoded ? rtDecoded.chunks.length : -1, first: rtDecoded ? rtDecoded.chunks[0].chunkId : '' },
  { chunks: realChunks.length, first: realChunks[0].chunkId });

check('J 状态', '构建签名非空、确定，并且与语料指纹是两把独立的钥匙',
  (() => {
    const a = new KnowledgeIndex().buildSignature();
    const b = new KnowledgeIndex().buildSignature();
    return a.length === 7 && a === b && a !== fingerprintChunks([]);
  })(), new KnowledgeIndex().buildSignature(), 'stable 7-char, distinct from fingerprint');

// --- disabled by default: no AppStorage means no cache, not a crash ---
const bareStore = new KnowledgeIndexStore();
check('J 降级', '没有 filesDir（单测 / 预览场景）时持久化整体禁用，读写都不抛异常',
  bareStore.isEnabled() === false && bareStore.snapshotPath() === null &&
  bareStore.load('x', 'y') === null && bareStore.save({}) === false &&
  (() => { bareStore.clear(); return true; })(),
  { enabled: bareStore.isEnabled(), path: bareStore.snapshotPath() }, 'silently disabled');

// --- live read/write against an in-memory file system ---
const FS_STUB = `
const __fs = global.__fsStub;
const AppStorage = {
  get(key) { return __fs.dirs[key]; },
  setOrCreate(key, value) { __fs.dirs[key] = value; },
};
const fileIo = {
  readTextSync(p) { if (!(p in __fs.files)) { throw new Error('ENOENT'); } return __fs.files[p]; },
  openSync(p, flags) { __fs.files[p] = ''; __fs.opens++; return { fd: p }; },
  writeSync(fd, data) { __fs.files[fd] = (__fs.files[fd] || '') + data; return data.length; },
  closeSync(file) { __fs.closes++; },
  unlinkSync(p) { if (!(p in __fs.files)) { throw new Error('ENOENT'); } delete __fs.files[p]; },
};
`;

const SNAPSHOT_PATH = '/data/files/knowledgeIndex.json';

// The stub is installed *before* the module is loaded, because a module-level
// `const __fs = global.__fsStub` captures the object once. Replacing the global
// afterwards would leave the module pointing at the old one, and the store would
// silently behave as "persistence disabled" instead of failing — so resetFs
// mutates in place rather than reassigning.
global.__fsStub = { files: {}, dirs: { filesDir: '/data/files' }, opens: 0, closes: 0 };
const liveIndexStoreModule = global.__loadIndexStore(FS_STUB);

function resetFs() {
  const fsStub = global.__fsStub;
  fsStub.files = {};
  fsStub.dirs = { filesDir: '/data/files' };
  fsStub.opens = 0;
  fsStub.closes = 0;
  return fsStub;
}

function buildStore() {
  return new KnowledgeStore(realProvider, new liveIndexStoreModule.KnowledgeIndexStore());
}
/** A store whose index has actually been assembled — `getLoadSource` is only
 *  meaningful after that, since it reports how the build went. */
function runStore() {
  const store = buildStore();
  store.warmUp();
  return store;
}
function msOf(fn) {
  const t0 = process.hrtime.bigint();
  const out = fn();
  return { ms: Number(process.hrtime.bigint() - t0) / 1e6, out };
}

check('J 落盘', '内存文件系统桩已生效（否则下面全是「持久化被禁用」的假绿）',
  new liveIndexStoreModule.KnowledgeIndexStore().isEnabled() === true &&
  new liveIndexStoreModule.KnowledgeIndexStore().snapshotPath() === SNAPSHOT_PATH,
  new liveIndexStoreModule.KnowledgeIndexStore().snapshotPath(), SNAPSHOT_PATH);

const fs1 = resetFs();
const coldStore = buildStore();
const coldRun = msOf(() => coldStore.search('TCP 三次握手 为什么要三次', 5));
const coldIds = coldStore.search('TCP 三次握手 为什么要三次', 5).map(h => h.chunk.chunkId).join('|');

check('J 落盘', '首次启动：无缓存 → 全量重建，并把快照写进 filesDir',
  coldStore.getLoadSource() === 'rebuild' && coldStore.wasSnapshotSaved() === true &&
  Boolean(fs1.files[SNAPSHOT_PATH]) && fs1.opens === 1 && fs1.closes === 1,
  { source: coldStore.getLoadSource(), saved: coldStore.wasSnapshotSaved(),
    bytes: (fs1.files[SNAPSHOT_PATH] || '').length, opens: fs1.opens },
  { source: 'rebuild', saved: true, opens: 1 });

check('J 落盘', '快照只落在 filesDir 下的一个文件里，没有写进 AppStorage',
  Object.keys(fs1.dirs).join(',') === 'filesDir',
  Object.keys(fs1.dirs), 'filesDir');

const warmStore = buildStore();
const warmRun = msOf(() => warmStore.search('TCP 三次握手 为什么要三次', 5));
const warmIds = warmStore.search('TCP 三次握手 为什么要三次', 5).map(h => h.chunk.chunkId).join('|');

check('J 落盘', '二次启动：命中缓存，检索结果与全量重建逐条一致（缓存无损）',
  warmStore.getLoadSource() === 'cache' && warmIds === coldIds && coldIds.length > 0,
  { source: warmStore.getLoadSource(), same: warmIds === coldIds },
  { source: 'cache', same: true });

check('J 落盘', `实测：缓存路径不慢于全量重建（重建 ${coldRun.ms.toFixed(1)} ms / 缓存 ${warmRun.ms.toFixed(1)} ms）`,
  warmRun.ms <= coldRun.ms,
  { rebuildMs: Math.round(coldRun.ms * 100) / 100, cacheMs: Math.round(warmRun.ms * 100) / 100 },
  'cache <= rebuild');

check('J 落盘', '缓存命中时索引规模与全量重建一致',
  warmStore.stats().chunkCount === coldStore.stats().chunkCount &&
  warmStore.stats().termCount === coldStore.stats().termCount,
  { warm: warmStore.stats(), cold: coldStore.stats() },
  'identical stats');

check('J 失效', '语料指纹不匹配 → 丢掉缓存重新构建（改了讲义不会被旧索引糊弄）',
  (() => {
    const fsStub = resetFs();
    buildStore().warmUp();
    const tampered = JSON.parse(fsStub.files[SNAPSHOT_PATH]);
    tampered.fingerprint = 'deadbee';
    fsStub.files[SNAPSHOT_PATH] = JSON.stringify(tampered);
    return runStore().getLoadSource();
  })() === 'rebuild', 'see condition', 'rebuild');

check('J 失效', '构建签名不匹配 → 丢掉缓存重新构建（分词规则变了就自动失效）',
  (() => {
    const fsStub = resetFs();
    buildStore().warmUp();
    const tampered = JSON.parse(fsStub.files[SNAPSHOT_PATH]);
    tampered.signature = 'deadbee';
    fsStub.files[SNAPSHOT_PATH] = JSON.stringify(tampered);
    return runStore().getLoadSource();
  })() === 'rebuild', 'see condition', 'rebuild');

check('J 失效', '未篡改时同一份快照确实命中缓存（证明上面两条失败是篡改导致的，不是路径本身没用）',
  (() => {
    resetFs();
    buildStore().warmUp();
    return runStore().getLoadSource();
  })() === 'cache', 'see condition', 'cache');

check('J 失效', '快照文件损坏 → 重建，且检索仍然可用（缓存坏了不影响助教）',
  (() => {
    const fsStub = resetFs();
    buildStore().warmUp();
    fsStub.files[SNAPSHOT_PATH] = '{"version":1,"chunks":[{"chunkId":"half"';
    const second = runStore();
    const hits = second.search('TCP 三次握手 为什么要三次', 5);
    return second.getLoadSource() === 'rebuild' && hits.length > 0 &&
      fsStub.files[SNAPSHOT_PATH].indexOf('"chunkId"') >= 0;
  })(), 'see condition', true);

// ---------- J. static guardrails ----------
const indexStoreSrc = readSource(`${SERVICE_DIR}KnowledgeIndexStore.ets`);

check('J 静态', '快照不进 AppStorage：持久化层只读 filesDir，没有任何 setOrCreate',
  indexStoreSrc.indexOf('setOrCreate') < 0 && indexStoreSrc.indexOf("'filesDir'") >= 0,
  { setOrCreate: indexStoreSrc.indexOf('setOrCreate') >= 0,
    readsFilesDir: indexStoreSrc.indexOf("'filesDir'") >= 0 },
  { setOrCreate: false, readsFilesDir: true });

check('J 静态', '编解码器是纯的：无 fileIo / AppStorage / 时钟 / 随机数',
  codecSrc.indexOf('fileIo') < 0 && codecSrc.indexOf('AppStorage') < 0 &&
  codecSrc.indexOf('Date.now') < 0 && codecSrc.indexOf('Math.random') < 0,
  { io: codecSrc.indexOf('fileIo') >= 0 || codecSrc.indexOf('AppStorage') >= 0,
    nondeterministic: codecSrc.indexOf('Date.now') >= 0 || codecSrc.indexOf('Math.random') >= 0 },
  { io: false, nondeterministic: false });

check('J 静态', '持久化层同时校验指纹与签名，两把钥匙缺一不可',
  indexStoreSrc.indexOf('snapshot.fingerprint !== expectedFingerprint') >= 0 &&
  indexStoreSrc.indexOf('snapshot.signature !== expectedSignature') >= 0,
  { fingerprint: indexStoreSrc.indexOf('snapshot.fingerprint !== expectedFingerprint') >= 0,
    signature: indexStoreSrc.indexOf('snapshot.signature !== expectedSignature') >= 0 },
  { fingerprint: true, signature: true });

check('J 静态', '空语料不写缓存（否则一次失败会变成永久失忆）',
  storeSrc.indexOf('chunks.length === 0') >= 0 && storeSrc.indexOf('LOAD_SOURCE_EMPTY') >= 0,
  storeSrc.indexOf('chunks.length === 0') >= 0, true);

// ---------- K. labelled eval set + Recall@3 / MRR ----------

const evalSetModule = loadArkTs(`${SERVICE_DIR}KnowledgeEvalSet.ets`, MODEL_STUB);
const metricsModule = loadArkTs(`${SERVICE_DIR}KnowledgeRetrievalMetrics.ets`, MODEL_STUB);
const evalCases = evalSetModule.buildKnowledgeEvalSet();

check('K 标注集', '标注集结构合法：查询唯一、docId 与期望词都非空、期望词至少两个字',
  evalCases.length >= 25 &&
  new Set(evalCases.map(c => c.query)).size === evalCases.length &&
  evalCases.every(c => c.docId.length > 0 && c.expected.length > 0) &&
  evalCases.every(c => c.expected.every(t => typeof t === 'string' && t.length >= 2)),
  { cases: evalCases.length, unique: new Set(evalCases.map(c => c.query)).size },
  { cases: '>=25', unique: evalCases.length });

check('K 标注集', '两个分桶都有样本（否则「直接问法」会盖住「换句话问」的真实差距）',
  evalCases.filter(c => c.bucket === 'direct').length >= 10 &&
  evalCases.filter(c => c.bucket === 'paraphrase').length >= 8 &&
  evalCases.every(c => c.bucket === 'direct' || c.bucket === 'paraphrase'),
  { direct: evalCases.filter(c => c.bucket === 'direct').length,
    paraphrase: evalCases.filter(c => c.bucket === 'paraphrase').length },
  { direct: '>=10', paraphrase: '>=8' });

// A typo'd docId would score 0 silently and look like a retrieval failure.
const corpusDocIds = new Set(realChunks.map(c => c.docId));
const unknownDocIds = [...new Set(evalCases.map(c => c.docId))].filter(d => !corpusDocIds.has(d));
check('K 标注集', '每个标注的 docId 都真实存在于语料中（防手误写成不存在的文档）',
  unknownDocIds.length === 0, unknownDocIds, []);

const outcomes = evalCases.map(c => metricsModule.evaluateCase(realStore.search(c.query, 10), c, 3));
const overall = metricsModule.summarize(outcomes, 3, '');
const directReport = metricsModule.summarize(outcomes, 3, 'direct');
const paraphraseReport = metricsModule.summarize(outcomes, 3, 'paraphrase');
// The chat path hands the model the top 4 (KNOWLEDGE_DEFAULT_TOP_K), so @4 is
// what the learner actually gets; @3 is the strict number above it.
const outcomesAt4 = evalCases.map(c => metricsModule.evaluateCase(realStore.search(c.query, 10), c, 4));
const overallAt4 = metricsModule.summarize(outcomesAt4, 4, '');

check('K 基线', '整体检索质量达标：Recall@3 >= 0.80、MRR >= 0.68（数字见 actual）',
  overall.recallAtK >= 0.80 && overall.mrr >= 0.68,
  { recallAt3: overall.recallAtK, mrr: overall.mrr, recallAt4: overallAt4.recallAtK,
    cases: overall.caseCount, hits: overall.hitCount,
    direct: { recallAt3: directReport.recallAtK, mrr: directReport.mrr, cases: directReport.caseCount },
    paraphrase: { recallAt3: paraphraseReport.recallAtK, mrr: paraphraseReport.mrr,
      cases: paraphraseReport.caseCount },
    misses: overall.misses },
  { recallAt3: '>=0.80', mrr: '>=0.68' });

check('K 基线', '直接问法达标：Recall@3 >= 0.85（用课程自己的词问，就该基本能找到）',
  directReport.recallAtK >= 0.85,
  { recallAt3: directReport.recallAtK, mrr: directReport.mrr, cases: directReport.caseCount },
  { recallAt3: '>=0.85' });

check('K 基线', '换句话问达标：Recall@3 >= 0.65（比直接问法低是词法检索的固有上限）',
  paraphraseReport.recallAtK >= 0.65,
  { recallAt3: paraphraseReport.recallAtK, mrr: paraphraseReport.mrr, cases: paraphraseReport.caseCount },
  { recallAt3: '>=0.65' });

check('K 基线', '直接问法明显好于换句话问（这正是引入语义检索的理由，不是缺陷）',
  directReport.recallAtK >= paraphraseReport.recallAtK,
  { direct: directReport.recallAtK, paraphrase: paraphraseReport.recallAtK },
  'direct >= paraphrase');

check('K 基线', '放大到 4 条不比 3 条更差（提示词预算内多给一条不应有害）',
  overallAt4.recallAtK >= overall.recallAtK,
  { at3: overall.recallAtK, at4: overallAt4.recallAtK }, 'at4 >= at3');

check('K 指标', '分桶统计只统计本桶：两个桶的题数之和等于总数',
  directReport.caseCount + paraphraseReport.caseCount === overall.caseCount &&
  directReport.bucket === 'direct' && paraphraseReport.bucket === 'paraphrase',
  { direct: directReport.caseCount, paraphrase: paraphraseReport.caseCount, all: overall.caseCount },
  { sum: overall.caseCount });

// --- metric correctness on hand-made rankings: a metric that cannot fail is useless ---
// Plain objects are enough: the metrics only ever read `hit.chunk.*`.
const perfectCase = { query: 'q', docId: 'doc_x', expected: ['三次握手'], bucket: 'direct', note: '' };
function hitOf(docId, headingPath, text) {
  return {
    chunk: { chunkId: `${docId}#h`, docId, headingPath, text, title: '', knowledgeTag: '',
      sourceType: 'course_note', chunkIndex: 0, courseId: '' },
    score: 1, matchedTerms: [], retriever: 'bm25',
  };
}
const rel = hitOf('doc_x', 'x › 三次握手', '过程');
const irr = hitOf('doc_x', 'x › 其它', '无关内容');

check('K 指标', '第一名命中 → rank 1，RR 1，Recall@3 1',
  (() => { const o = metricsModule.evaluateCase([rel, irr], perfectCase, 3);
    return o.rank === 1 && o.reciprocalRank === 1 && o.matchedTerm === '三次握手'; })(),
  'rank1', 'rank1');
check('K 指标', '第二名命中 → rank 2，RR 0.5',
  (() => { const o = metricsModule.evaluateCase([irr, rel], perfectCase, 3);
    return o.rank === 2 && o.reciprocalRank === 0.5; })(), 'rank2/RR0.5', 'rank2/RR0.5');
check('K 指标', '命中掉出 top-K → rank 0，该题计入 misses',
  (() => {
    const o = metricsModule.evaluateCase([irr, irr, irr, rel], perfectCase, 3);
    const rep = metricsModule.summarize([o], 3, '');
    return o.rank === 0 && rep.recallAtK === 0 && rep.mrr === 0 && rep.misses.length === 1;
  })(), 'miss', 'miss');
check('K 指标', 'docId 对不上 → 即使正文含期望词也不算命中（防止跨课程误判为正确）',
  metricsModule.isRelevantHit(hitOf('doc_other', 'x › 三次握手', '过程'), perfectCase) === false,
  false, false);
check('K 指标', '期望词只匹配标题路径或正文，二者都算（ARP / TIME_WAIT 只出现在正文）',
  metricsModule.isRelevantHit(hitOf('doc_x', 'x › 章节', '讲了 ARP 的作用'), 
    { query: 'q', docId: 'doc_x', expected: ['ARP'], bucket: 'direct', note: '' }) === true,
  true, true);
check('K 指标', '报告文案可渲染，且带桶名时标注范围',
  metricsModule.formatRetrievalReport(overall).indexOf('Recall@3') >= 0 &&
  metricsModule.formatRetrievalReport(directReport).indexOf('[direct]') >= 0,
  metricsModule.formatRetrievalReport(overall), 'contains Recall@3');

// ---------- L. vector retrieval: embeddings, fusion, persistence ----------

const {
  LocalHashingEmbedder, EMBEDDING_DIMENSION, hashToBucket, cosineSimilarity,
  normalizeVector, documentTextFor,
} = embeddingModule;
const { KnowledgeVectorRetriever, fuseRankings, RRF_RANK_CONSTANT, RRF_DEFAULT_VECTOR_WEIGHT } = vectorModule;
const HYBRID_CANDIDATE_DEPTH_FOR_TEST = storeModule.HYBRID_CANDIDATE_DEPTH;

const embedder = new LocalHashingEmbedder();

check('L 嵌入', '本地嵌入器是确定性的：同文本两次得到同一向量，且维度正确',
  (() => {
    const a = embedder.embed('TCP 三次握手的过程');
    const b = embedder.embed('TCP 三次握手的过程');
    return a.length === EMBEDDING_DIMENSION && JSON.stringify(a) === JSON.stringify(b);
  })(), EMBEDDING_DIMENSION, EMBEDDING_DIMENSION);

check('L 嵌入', '向量已 L2 归一化（模长为 1，允许四舍五入误差）',
  (() => {
    const v = embedder.embed('操作系统的进程与线程');
    const norm = Math.sqrt(v.reduce((a, x) => a + x * x, 0));
    return Math.abs(norm - 1) < 0.001;
  })(), 'norm~1', 'norm~1');

check('L 嵌入', '不同文本得到不同向量；空文本得到全零且不产生 NaN',
  (() => {
    const a = embedder.embed('三次握手');
    const b = embedder.embed('四次挥手');
    const empty = embedder.embed('');
    return JSON.stringify(a) !== JSON.stringify(b) &&
      empty.every(x => x === 0) && empty.every(x => Number.isFinite(x));
  })(), 'distinct + zero', 'distinct + zero');

check('L 嵌入', '签名包含模型名、维度与分词行为，且随维度变化（换嵌入器必须失效缓存）',
  (() => {
    const sig = embedder.signature();
    return sig.indexOf('local-hash-v1') === 0 && sig.indexOf(`:${EMBEDDING_DIMENSION}:`) > 0 &&
      sig !== new LocalHashingEmbedder(64).signature();
  })(), embedder.signature(), 'model:dim:tokenizerHash');

check('L 嵌入', '哈希落桶始终在 [0, 维度) 内，且维度非法时退化为 0 而不是抛异常',
  ['三次', '握手', 'tcp', '2020'].every(t => {
    const b = hashToBucket(t, EMBEDDING_DIMENSION);
    return b >= 0 && b < EMBEDDING_DIMENSION;
  }) && hashToBucket('三次', 0) === 0 && hashToBucket('三次', -5) === 0,
  'in range', 'in range');

check('L 嵌入', '文档侧文本统一由 documentTextFor 组装（标题路径进向量，避免与调用方各写一份）',
  (() => {
    const text = documentTextFor({ headingPath: '计算机网络 › 传输层', title: 'TCP', text: '正文' });
    return text.indexOf('计算机网络 › 传输层') === 0 && documentTextFor(null) === '';
  })(), 'heading first', 'heading first');

check('L 相似度', '相同向量余弦为 1，正交为 0，长度不一致与零向量都返回 0',
  (() => {
    const v = embedder.embed('数据结构 二叉搜索树');
    const w = embedder.embed('操作系统 死锁');
    return Math.abs(cosineSimilarity(v, v) - 1) < 0.001 && cosineSimilarity([1, 0], [0, 1]) === 0 &&
      cosineSimilarity([1, 0], [1, 0, 0]) === 0 && cosineSimilarity([0, 0], [1, 0]) === 0;
  })(), '1 / 0 / 0 / 0', '1 / 0 / 0 / 0');

// --- vector retriever: pairing, ordering, degradation ---
const denseTexts = [
  '计算机网络 › 传输层 › TCP 三次握手\nTCP 三次握手\n建立连接需要三次握手，目的是同步初始序号。',
  '操作系统 › 进程管理 › 进程与线程\n进程与线程\n进程是资源分配单位，线程是调度单位。',
  '数据结构 › 树 › 二叉搜索树\n二叉搜索树\n左子树小于根，中序遍历得到有序序列。',
  '数据库系统原理 › 事务\n事务\nACID 分别表示原子性、一致性、隔离性、持久性。',
];
const denseChunks = denseTexts.map((text, i) => ({
  chunkId: `k_dense_${i}`, docId: `doc_dense_${i}`, title: text.split('\n')[1],
  headingPath: text.split('\n')[0], courseId: '', knowledgeTag: '', sourceType: 'course_note',
  text: text.split('\n')[2], chunkIndex: i,
}));
const denseVectors = denseChunks.map(c => embedder.embed(documentTextFor(c)));
const denseRetriever = new KnowledgeVectorRetriever();

check('L 向量', 'build 拒绝数量或宽度不一致的向量（位置错位会算错块，宁可不用）',
  denseRetriever.build(denseVectors.slice(0, 2), denseChunks) === false &&
  denseRetriever.build([[1, 2], [1, 2, 3]], denseChunks.slice(0, 2)) === false &&
  denseRetriever.build([], []) === false &&
  denseRetriever.isEmpty() === true,
  { stillEmpty: denseRetriever.isEmpty() }, true);

check('L 向量', 'build 成功后 size/dimension 正确，且导出的是副本（外部改不到内部）',
  (() => {
    const ok = denseRetriever.build(denseVectors, denseChunks);
    const exported = denseRetriever.exportVectors();
    exported[0][0] = 999;
    return ok && denseRetriever.size() === 4 && denseRetriever.dimension() === EMBEDDING_DIMENSION &&
      denseRetriever.exportVectors()[0][0] !== 999;
  })(), { size: denseRetriever.size() }, { size: 4 });

check('L 向量', '查询向量宽度不匹配 → 返回空，而不是拿截断的向量去比',
  denseRetriever.search([1, 0, 0], 3).length === 0, 0, 0);

check('L 向量', '「三次握手」的查询向量把对应的那一块排在第一',
  (() => {
    const hits = denseRetriever.search(embedder.embed('TCP 三次握手 建立连接'), 4);
    return hits.length > 0 && hits[0].chunk.chunkId === 'k_dense_0' &&
      hits[0].retriever === 'vector';
  })(), denseRetriever.search(embedder.embed('TCP 三次握手 建立连接'), 4)
    .map(h => h.chunk.chunkId), ['k_dense_0', '...']);

check('L 向量', '结果是全序且分数单调不增（同分按 chunkId 兜底，可复现）',
  (() => {
    const hits = denseRetriever.search(embedder.embed('进程 线程 调度'), 4);
    for (let i = 1; i < hits.length; i++) {
      if (hits[i - 1].score < hits[i].score) return false;
    }
    return true;
  })(), 'monotone', 'monotone');

// --- fusion ---
function lexHit(chunkId, score) {
  return { chunk: { chunkId, docId: 'd', title: '', headingPath: '', courseId: '',
    knowledgeTag: '', sourceType: 'course_note', text: '', chunkIndex: 0 },
  score, matchedTerms: ['a'], retriever: 'bm25' };
}
const fusedOnlyTop = fuseRankings([lexHit('k_x', 9), lexHit('k_y', 8)], [], 5);
const fusedAgreement = fuseRankings([lexHit('k_x', 9), lexHit('k_y', 8)],
  [{ ...lexHit('k_y', 0.5), retriever: 'vector' }, { ...lexHit('k_z', 0.4), retriever: 'vector' }], 5);

check('L 融合', '只给一路排序时退化为该路的顺序（融合不会凭空造出命中）',
  fusedOnlyTop.map(h => h.chunk.chunkId).join('|') === 'k_x|k_y',
  fusedOnlyTop.map(h => h.chunk.chunkId), ['k_x', 'k_y']);

check('L 融合', '两路都认可的排在只有一路认可的前面（RRF 的核心性质）',
  (() => {
    const ids = fusedAgreement.map(h => h.chunk.chunkId);
    return ids.indexOf('k_y') < ids.indexOf('k_x') && ids.length === 3;
  })(), fusedAgreement.map(h => h.chunk.chunkId), 'k_y before k_x');

check('L 融合', '融合结果标记为 hybrid，分数是「词法 1/(60+rank) + 稠密 权重/(60+rank)」',
  (() => {
    const y = fusedAgreement.find(h => h.chunk.chunkId === 'k_y');
    // k_y is rank 2 lexically and rank 1 densely.
    const expected = Math.round((1 / (RRF_RANK_CONSTANT + 2) +
      RRF_DEFAULT_VECTOR_WEIGHT / (RRF_RANK_CONSTANT + 1)) * 10000) / 10000;
    return y.retriever === 'hybrid' && y.score === expected;
  })(), fusedAgreement.find(h => h.chunk.chunkId === 'k_y').score, '1/62 + 0.35/61');

check('L 融合', '两路的命中词合并去重；空输入得到空结果',
  (() => {
    const merged = fuseRankings([{ ...lexHit('k_m', 5), matchedTerms: ['三次', '握手'] }],
      [{ ...lexHit('k_m', 0.9), matchedTerms: ['握手', '连接'], retriever: 'vector' }], 3);
    return merged.length === 1 && merged[0].matchedTerms.join(',') === '三次,握手,连接' &&
      fuseRankings([], [], 5).length === 0;
  })(), '三次,握手,连接', '三次,握手,连接');

// --- vectors survive the snapshot round trip ---
const vectorSnapshot = {
  version: KNOWLEDGE_SNAPSHOT_VERSION, fingerprint: 'fp2', signature: 'sg2',
  vectorSignature: embedder.signature(), chunks: denseChunks, state: (() => {
    const ix = new KnowledgeIndex();
    ix.build(denseChunks);
    return ix.exportState();
  })(), vectors: denseVectors,
};
const vectorJson = encodeSnapshot(vectorSnapshot);
const vectorDecoded = decodeSnapshot(vectorJson);
const restoredRetriever = new KnowledgeVectorRetriever();
const restoredOk = vectorDecoded !== null &&
  restoredRetriever.build(vectorDecoded.vectors, vectorDecoded.chunks);

check('L 落盘', '向量能随快照完整往返（不同嵌入器的向量必须能分别识别与恢复）',
  restoredOk && restoredRetriever.size() === 4 &&
  vectorDecoded.vectorSignature === embedder.signature() &&
  JSON.stringify(restoredRetriever.exportVectors()) === JSON.stringify(denseVectors),
  { restored: restoredRetriever.size(), signature: vectorDecoded ? vectorDecoded.vectorSignature : '' },
  { restored: 4, signature: embedder.signature() });

check('L 落盘', '带向量但没有来源签名 → 拒绝读取（来源不明的向量不可校验，不如重算）',
  (() => {
    const bad = JSON.parse(vectorJson);
    bad.vectorSignature = '';
    return decodeSnapshot(JSON.stringify(bad)) === null;
  })(), null, null);

check('L 落盘', '向量数量与块数不一致 → 拒绝读取',
  (() => {
    const bad = JSON.parse(vectorJson);
    bad.vectors = bad.vectors.slice(0, 2);
    return decodeSnapshot(JSON.stringify(bad)) === null;
  })(), null, null);

// --- store integration: install, cache, degrade ---
const vectorFs = resetFs();
const vectorStore = runStore();
const storedHits = vectorStore.search('TCP 三次握手 为什么要三次', 4).map(h => h.chunk.chunkId);
const installed = vectorStore.prepareVectors(
  { model: embedder.model(), dimension: EMBEDDING_DIMENSION,
    vectors: realChunks.map(c => embedder.embed(documentTextFor(c))) },
  embedder.signature());

check('L 门面', 'prepareVectors 把稠密侧装上，并把向量一起写进快照',
  installed === true && vectorStore.hasVectors() === true &&
  vectorStore.hasVectorsFor(embedder.signature()) === true &&
  vectorStore.hasVectorsFor('other-embedder:256:0000000') === false,
  { installed, hasVectors: vectorStore.hasVectors() }, { installed: true, hasVectors: true });

const secondVectorStore = runStore();
check('L 门面', '二次启动时向量直接从快照恢复：无需重新嵌入，签名可直接比对',
  secondVectorStore.hasVectorsFor(embedder.signature()) === true &&
  secondVectorStore.getLoadSource() === 'cache',
  { source: secondVectorStore.getLoadSource(), hasVectors: secondVectorStore.hasVectors() },
  { source: 'cache', hasVectors: true });

check('L 门面', 'prepareVectors 数量对不上 → 拒绝安装，稠密侧保持为空（不半装）',
  (() => {
    resetFs();
    const fresh = runStore();
    const wrong = { model: 'x', dimension: 4, vectors: [[1, 0, 0, 0]] };
    return fresh.prepareVectors(wrong, 'sig') === false && fresh.hasVectors() === false;
  })(), 'rejected', 'rejected');

check('L 门面', '没有稠密侧时 searchHybrid 静默退化为纯 BM25（调用方不必自己分支）',
  (() => {
    resetFs();
    const fresh = runStore();
    const hybrid = fresh.searchHybrid('TCP 三次握手 为什么要三次', embedder.embed('TCP 三次握手 为什么要三次'), 4);
    const lexical = fresh.search('TCP 三次握手 为什么要三次', 4);
    return hybrid.map(h => h.chunk.chunkId).join('|') === lexical.map(h => h.chunk.chunkId).join('|');
  })(), 'same as bm25', 'same as bm25');

check('L 门面', '装了向量后 searchHybrid 返回融合结果，分数不超过 RRF 理论最大值',
  (() => {
    const hybrid = vectorStore.searchHybrid('TCP 三次握手 为什么要三次', embedder.embed('TCP 三次握手 为什么要三次'), 4);
    // 1/(60+1) from BM25 (weight 1) plus the weighted dense term.
    const ceiling = Math.round((1 + RRF_DEFAULT_VECTOR_WEIGHT) / (RRF_RANK_CONSTANT + 1) * 10000) / 10000;
    return hybrid.length > 0 && hybrid.every(h => h.retriever === 'hybrid') &&
      hybrid.every(h => h.score > 0 && h.score <= ceiling);
  })(), vectorStore.searchHybrid('TCP 三次握手 为什么要三次', embedder.embed('TCP 三次握手 为什么要三次'), 4)
    .map(h => `${h.chunk.chunkId}:${h.score}`), 'hybrid hits within ceiling');

check('L 失效', 'invalidate 同时丢掉稠密侧（改了语料不能留下旧向量继续用）',
  (() => {
    const fresh = runStore();
    fresh.prepareVectors({ model: 'x', dimension: EMBEDDING_DIMENSION,
      vectors: realChunks.map(c => embedder.embed(documentTextFor(c))) }, 'sig-x');
    const before = fresh.hasVectors();
    fresh.invalidate();
    const after = fresh.hasVectors();
    return before === true && after === false;
  })(), 'installed then cleared', true);

// ---------- L. hybrid vs lexical on the labelled set (the honest comparison) ----------
// The local hashed embedder is a stand-in, not a semantic model, and the point
// of this section is to find out what it is actually worth instead of assuming.
// The dense list is swept by weight: at 0 the fusion reproduces BM25 exactly,
// and every step up hands it more power to reorder the lexical ranking.
const evalEmbedder = new LocalHashingEmbedder();
const evalVectors = realChunks.map(c => evalEmbedder.embed(documentTextFor(c)));
const evalStore = runStore();
const evalInstalled = evalStore.prepareVectors(
  { model: evalEmbedder.model(), dimension: EMBEDDING_DIMENSION, vectors: evalVectors },
  evalEmbedder.signature());
const evalDense = new KnowledgeVectorRetriever();
evalDense.build(evalVectors, realChunks);

/** Evaluates one dense weight end-to-end through the fusion. */
function evaluateWeight(weight) {
  const rows = evalCases.map(c => {
    const lexical = evalStore.search(c.query, HYBRID_CANDIDATE_DEPTH_FOR_TEST);
    const dense = evalDense.search(evalEmbedder.embed(c.query), HYBRID_CANDIDATE_DEPTH_FOR_TEST);
    const hits = fuseRankings(lexical, dense, HYBRID_CANDIDATE_DEPTH_FOR_TEST, undefined, weight);
    return metricsModule.evaluateCase(hits, c, 3);
  });
  const all = metricsModule.summarize(rows, 3, '');
  return {
    recallAt3: all.recallAtK,
    mrr: all.mrr,
    paraphraseRecallAt3: metricsModule.summarize(rows, 3, 'paraphrase').recallAtK,
  };
}

const weightSweep = [0, 0.2, 0.35, 0.5, 0.75, 1].map(w => ({ weight: w, ...evaluateWeight(w) }));
const lexicalOnly = weightSweep[0];
const bestWeight = weightSweep.reduce((best, row) => (row.recallAt3 > best.recallAt3 ? row : best),
  weightSweep[0]);

check('L 对比', '混合检索装得上，且两路都在工作（否则下面的对比没有意义）',
  evalInstalled === true && evalStore.hasVectors() === true && evalDense.size() === realChunks.length,
  { installed: evalInstalled, dense: evalDense.size(), chunks: realChunks.length },
  { installed: true, dense: realChunks.length });

check('L 对比', '稠密权重扫参结果（权重 0 即纯 BM25，数字见 actual，不预设谁赢）',
  lexicalOnly.recallAt3 > 0,
  { sweep: weightSweep, best: bestWeight, configured: RRF_DEFAULT_VECTOR_WEIGHT },
  'see actual');

check('L 对比', '权重 0 时融合与纯 BM25 完全一致（证明扫参的基线是真的基线）',
  lexicalOnly.recallAt3 === overall.recallAtK && lexicalOnly.mrr === overall.mrr,
  { fusedW0: lexicalOnly, bm25: { recallAt3: overall.recallAtK, mrr: overall.mrr } },
  'identical');

// This is a *recorded measurement*, not a preference. If a future embedder
// makes the dense side genuinely semantic, this check starts failing and forces
// the decision to be revisited rather than quietly left off.
check('L 对比', '实测结论：本地哈希嵌入器没有语义增益（换句话问的召回反而下降），因此不作为默认路径',
  bestWeight.recallAt3 <= lexicalOnly.recallAt3 &&
  bestWeight.paraphraseRecallAt3 <= lexicalOnly.paraphraseRecallAt3,
  { best: bestWeight, lexical: lexicalOnly },
  'dense side does not beat BM25 on this corpus');

check('L 静态', '默认检索路径仍是词法的：KnowledgeStore.search 不依赖向量检索器',
  (() => {
    const searchBody = storeSrc.substring(
      storeSrc.indexOf('  search(query: string'),
      storeSrc.indexOf('  searchHybrid('));
    return searchBody.length > 0 && searchBody.indexOf('vectorRetriever') < 0 &&
      searchBody.indexOf('fuseRankings') < 0;
  })(), 'lexical only', 'lexical only');

check('L 静态', '没有任何服务会自动装上本地嵌入器（稠密侧只能被显式安装）',
  [storeSrc, chatVmSrc, toolsSrc, routerSrc].every(src => src.indexOf('LocalHashingEmbedder') < 0),
  { store: storeSrc.indexOf('LocalHashingEmbedder') >= 0,
    chat: chatVmSrc.indexOf('LocalHashingEmbedder') >= 0 },
  { store: false, chat: false });

// ---------- L. embedding proxy: the one network-facing piece ----------
// Loaded against an in-memory `http` stub, installed before the module loads so
// the module-level capture sees it (the same trap as the fs stub in group J).
global.__httpStub = {
  created: 0, destroyed: 0, calls: [], responseCode: 200, result: '',
  rejectOnRequest: false,
};
const HTTP_STUB = `
const __http = global.__httpStub;
const http = {
  RequestMethod: { POST: 'POST' },
  HttpDataType: { STRING: 0 },
  createHttp() {
    __http.created++;
    return {
      request(url, options) {
        __http.calls.push({ url, options });
        if (__http.rejectOnRequest) {
          return Promise.reject(new Error('network down'));
        }
        return Promise.resolve({ responseCode: __http.responseCode, result: __http.result });
      },
      destroy() { __http.destroyed++; },
    };
  },
};
const Logger = { info() {}, warn() {}, error() {}, debug() {} };
`;
const aiBackendModule = loadArkTs(`${SERVICE_DIR}AiBackend.ets`);
global.__aiBackendModule = aiBackendModule;
const proxyModule = loadArkTs(`${SERVICE_DIR}KnowledgeEmbeddingProxy.ets`,
  `${MODEL_STUB}\nconst { KnowledgeEmbeddingBatch } = global.__embeddingModule;\n` +
  `const { AiBackend, BACKEND_EMBED_PATH } = global.__aiBackendModule;\n${HTTP_STUB}`);
const proxySrc = readSource(`${SERVICE_DIR}KnowledgeEmbeddingProxy.ets`);

async function runEmbeddingProxyChecks() {
  const { KnowledgeEmbeddingProxy, parseEmbeddingResponse } = proxyModule;
  const resetHttp = () => {
    const s = global.__httpStub;
    s.created = 0; s.destroyed = 0; s.calls = []; s.responseCode = 200; s.result = '';
    s.rejectOnRequest = false;
    return s;
  };

  const off = new KnowledgeEmbeddingProxy('');
  check('L 代理', '未配置代理时 isConfigured 为 false，embed 返回 null 且一个请求都不发',
    off.isConfigured() === false && await off.embed(['三次握手']) === null &&
    global.__httpStub.created === 0,
    { configured: off.isConfigured(), requests: global.__httpStub.created }, { configured: false, requests: 0 });

  const on = new KnowledgeEmbeddingProxy('https://api.example.edu/rag/', 'session-token');
  check('L 代理', '末尾斜杠被规范化，请求路径为 {base}/embed',
    on.isConfigured() === true && on.url() === 'https://api.example.edu/rag/embed', on.url(),
    'https://api.example.edu/rag/embed');

  const stub = resetHttp();
  stub.result = JSON.stringify({ model: 'bge-large-zh', dimension: 3, vectors: [[1, 0, 0], [0, 1, 0]] });
  const batch = await on.embed(['三次握手', '四次挥手']);
  check('L 代理', '成功路径返回批次；请求发到正确 URL、带上应用会话令牌、且请求对象被销毁',
    batch !== null && batch.model === 'bge-large-zh' && batch.dimension === 3 &&
    batch.vectors.length === 2 &&
    stub.calls[0].url === 'https://api.example.edu/rag/embed' &&
    stub.calls[0].options.header['Authorization'] === 'Bearer session-token' &&
    stub.created === 1 && stub.destroyed === 1,
    { model: batch ? batch.model : '', dim: batch ? batch.dimension : 0,
      auth: stub.calls[0].options.header['Authorization'],
      created: stub.created, destroyed: stub.destroyed },
    { model: 'bge-large-zh', auth: 'Bearer session-token', destroyed: 1 });

  check('L 代理', '请求体只带 model 与 inputs，不含任何密钥字段',
    (() => {
      const body = JSON.parse(stub.calls[0].options.extraData);
      return Object.keys(body).join(',') === 'model,inputs' && Array.isArray(body.inputs) &&
        typeof body.model === 'string';
    })(), Object.keys(JSON.parse(stub.calls[0].options.extraData)), ['model', 'inputs']);

  check('L 代理', '无会话令牌时不发 Authorization 头（客户端没有厂商密钥可发）',
    (() => {
      resetHttp();
      return new KnowledgeEmbeddingProxy('https://api.example.edu/rag').url() ===
        'https://api.example.edu/rag/embed' && proxySrc.indexOf('Authorization') >= 0;
    })(), 'no vendor key', 'no vendor key');

  check('L 代理', '非 200 / 传输异常 → 一律 null（失败必须降级，不能把提问打挂）', await (async () => {
    resetHttp();
    global.__httpStub.responseCode = 503;
    const bad = await on.embed(['x']);
    resetHttp();
    global.__httpStub.rejectOnRequest = true;
    const thrown = await on.embed(['x']);
    return bad === null && thrown === null && global.__httpStub.destroyed >= 1;
  })(), 'null / null', 'null / null');

  check('L 代理', '响应非法 JSON、向量条数不符、行内混入非数值 → 全部 null（位置错位比不检索更糟）',
    await (async () => {
      resetHttp();
      global.__httpStub.result = '不是 json';
      const a = await on.embed(['x', 'y']);
      resetHttp();
      global.__httpStub.result = JSON.stringify({ model: 'm', dimension: 2, vectors: [[1, 0]] });
      const b = await on.embed(['x', 'y']);
      resetHttp();
      global.__httpStub.result = JSON.stringify({ model: 'm', dimension: 2, vectors: [[1, 'x'], [0, 1]] });
      const c = await on.embed(['x', 'y']);
      resetHttp();
      global.__httpStub.result = JSON.stringify({ model: 'm', dimension: 2, vectors: [[1, 0], [0]] });
      const d = await on.embed(['x', 'y']);
      return a === null && b === null && c === null && d === null;
    })(), 'all null', 'all null');

  check('L 代理', '配置来源复用 AiBackend（同一份后端配置），代理自己不另设一份 URL 键',
    typeof KnowledgeEmbeddingProxy.current === 'function' &&
    KnowledgeEmbeddingProxy.current().isConfigured() === false &&
    proxySrc.indexOf('AiBackend') >= 0 &&
    proxySrc.indexOf('BACKEND_URL_KEY') < 0,
    'delegates', 'delegates');

  check('L 代理', '纯解析函数可独立测试：合法载荷解码，空串为 null',
    (() => {
      const ok = parseEmbeddingResponse(JSON.stringify({ model: 'm', dimension: 2, vectors: [[1, 0], [0, 1]] }), 2);
      return ok !== null && ok.dimension === 2 && ok.vectors.length === 2 &&
        parseEmbeddingResponse('', 1) === null;
    })(), 'parsed', 'parsed');

  check('L 代理静态', '代理客户端不引用聊天密钥与常量文件（不重演 P0：客户端不得持有厂商密钥）',
    proxySrc.indexOf('ApiKeyStore') < 0 && proxySrc.indexOf('AiConstants') < 0 &&
    proxySrc.indexOf('apiKey') < 0 && proxySrc.indexOf('API_KEY') < 0,
    { apiKeyStore: proxySrc.indexOf('ApiKeyStore') >= 0, constants: proxySrc.indexOf('AiConstants') >= 0,
      apiKey: proxySrc.indexOf('apiKey') >= 0 },
    { apiKeyStore: false, constants: false, apiKey: false });
}

// ---------- M. start-up warm-up wiring ----------
//
// Three of these properties are invisible in a running app, which is exactly
// why they are pinned here: an inline warm-up only makes start-up slower, a
// warm-up that runs before `filesDir` exists silently disables the disk cache
// while looking perfectly healthy, and a warm-up that fires too often just
// rebuilds the same index. None of them throws, so none of them would be
// noticed in manual testing.

const ENTRY_ABILITY_PATH = 'entry/src/main/ets/entryability/EntryAbility.ets';
const entryAbilitySrc = readSource(ENTRY_ABILITY_PATH);
const agentBarrelSrc = readSource('features/aiagent/Index.ets');

/** Runs `fn` with a setTimeout that captures timers instead of scheduling them. */
function withTimerCapture(fn) {
  const original = global.setTimeout;
  const timers = [];
  let thrown = null;
  global.setTimeout = (callback, delay) => {
    timers.push({ callback, delay });
    return timers.length;
  };
  try {
    fn();
  } catch (error) {
    thrown = error;
  }
  global.setTimeout = original;
  return { timers, thrown };
}

check('M 接线', 'barrel 是模块唯一的公开面：KnowledgeStore 从这里导出，entry 不必伸手进 feature 内部',
  agentBarrelSrc.indexOf('export { KnowledgeStore }') >= 0 &&
  agentBarrelSrc.indexOf("./src/main/ets/service/KnowledgeStore") >= 0,
  { exported: agentBarrelSrc.indexOf('export { KnowledgeStore }') >= 0 },
  'exported from the barrel');

check('M 接线', 'EntryAbility 从 @safe/aiagent 导入并调用 scheduleWarmUp，而不是在启动路径上同步 warmUp',
  entryAbilitySrc.indexOf("from '@safe/aiagent'") >= 0 &&
  entryAbilitySrc.indexOf('KnowledgeStore.scheduleWarmUp()') >= 0 &&
  entryAbilitySrc.indexOf('.warmUp()') < 0,
  { imported: entryAbilitySrc.indexOf("@safe/aiagent") >= 0,
    scheduled: entryAbilitySrc.indexOf('KnowledgeStore.scheduleWarmUp()') >= 0,
    syncWarmUp: entryAbilitySrc.indexOf('.warmUp()') >= 0 },
  { imported: true, scheduled: true, syncWarmUp: false });

const filesDirAt = entryAbilitySrc.indexOf("setOrCreate('filesDir'");
const loadContentAt = entryAbilitySrc.indexOf('loadContent(');
check('M 接线', 'filesDir 在 loadContent 之前发布（晚于页面就会让预热与页面都找不到缓存，且不报任何错）',
  filesDirAt >= 0 && loadContentAt >= 0 && filesDirAt < loadContentAt,
  { filesDirAt, loadContentAt }, 'filesDir published first');

check('M 静态', '预热不联网：KnowledgeStore 不引用嵌入代理，启动不会偷偷发出请求',
  storeSrc.indexOf('EmbeddingProxy') < 0 && storeSrc.indexOf('http') < 0,
  { proxy: storeSrc.indexOf('EmbeddingProxy') >= 0, http: storeSrc.indexOf('http') >= 0 },
  { proxy: false, http: false });

const warmTarget = KnowledgeStore.getInstance();
warmTarget.invalidate();
KnowledgeStore.resetWarmUpSchedule();

const warmFirst = withTimerCapture(() => KnowledgeStore.scheduleWarmUp());
check('M 预热', '调度本身同步返回、不构建：索引仍为空，构建只被排进定时器（启动不被拖住）',
  warmFirst.thrown === null && warmFirst.timers.length === 1 &&
  warmFirst.timers[0].delay === KNOWLEDGE_WARMUP_DELAY_MS && warmTarget.getLoadSource() === 'empty',
  { thrown: warmFirst.thrown === null, timers: warmFirst.timers.length,
    delay: warmFirst.timers.length > 0 ? warmFirst.timers[0].delay : -1,
    source: warmTarget.getLoadSource() },
  { thrown: true, timers: 1, delay: KNOWLEDGE_WARMUP_DELAY_MS, source: 'empty' });

check('M 预热', '延迟是「躲开首帧」而不是「一直拖」：大于 0 且不超过 2 秒',
  KNOWLEDGE_WARMUP_DELAY_MS > 0 && KNOWLEDGE_WARMUP_DELAY_MS <= 2000,
  KNOWLEDGE_WARMUP_DELAY_MS, '0 < delay <= 2000 ms');

warmFirst.timers[0].callback();
const warmSourceAfterRun = warmTarget.getLoadSource();
const warmHits = warmTarget.search('TCP 三次握手 为什么要三次', 3);
check('M 预热', '定时器一触发索引就绪、检索立刻可用（「不占第一个聊天回合」这才算兑现）',
  (warmSourceAfterRun === 'rebuild' || warmSourceAfterRun === 'cache') && warmHits.length > 0,
  { source: warmSourceAfterRun, hits: warmHits.length }, { source: 'rebuild|cache', hits: '> 0' });

const warmSecond = withTimerCapture(() => {
  KnowledgeStore.scheduleWarmUp();
  KnowledgeStore.scheduleWarmUp();
});
check('M 预热', '排过就不再排：Ability 在同一进程里重建也不会排第二个定时器（构建本身也已幂等）',
  warmSecond.timers.length === 0, warmSecond.timers.length, 0);

const warmThird = withTimerCapture(() => {
  KnowledgeStore.resetWarmUpSchedule();
  KnowledgeStore.scheduleWarmUp(0);
});
check('M 预热', '重置钩子之后可以重新排期，自定义延迟被透传（否则上面那条只证明「永远不再排」）',
  warmThird.timers.length === 1 && warmThird.timers[0].delay === 0,
  { timers: warmThird.timers.length,
    delay: warmThird.timers.length > 0 ? warmThird.timers[0].delay : -1 },
  { timers: 1, delay: 0 });

const warmFourth = withTimerCapture(() => {
  KnowledgeStore.resetWarmUpSchedule();
  KnowledgeStore.scheduleWarmUp(0);
});
const realGetInstance = KnowledgeStore.getInstance;
let warmProbeRan = false;
KnowledgeStore.getInstance = () => {
  warmProbeRan = true;
  throw new Error('warm-up probe');
};
let warmEscaped = null;
try {
  warmFourth.timers[0].callback();
} catch (error) {
  warmEscaped = String(error);
}
KnowledgeStore.getInstance = realGetInstance;
check('M 预热', '预热自身抛错也不冒泡（能建不成就退化为按需构建），且探针确实跑到了——否则这条断言是空的',
  warmProbeRan === true && warmEscaped === null,
  { probeRan: warmProbeRan, escaped: warmEscaped }, { probeRan: true, escaped: null });

check('M 预热', '门面同时保留调度入口、重置钩子与公开 warmUp（离线测试与已脱离关键路径的调用方都要用）',
  typeof KnowledgeStore.scheduleWarmUp === 'function' &&
  typeof KnowledgeStore.resetWarmUpSchedule === 'function' &&
  typeof KnowledgeStore.getInstance().warmUp === 'function',
  { schedule: typeof KnowledgeStore.scheduleWarmUp, reset: typeof KnowledgeStore.resetWarmUpSchedule },
  { schedule: 'function', reset: 'function' });

// ---------- report ----------
function finish() {
  fs.writeFileSync(path.join(__dirname, 'ai_agent_p7_test_result.json'), JSON.stringify(results, null, 2));
  console.log(`${results.length - failures}/${results.length} passed`);
  process.exit(failures > 0 ? 1 : 0);
}

runEmbeddingProxyChecks().then(finish, (error) => {
  results.push({ group: 'L 代理', name: '代理测试自身不应抛异常', status: 'FAIL',
    actual: String(error), expected: 'no throw' });
  failures++;
  finish();
});

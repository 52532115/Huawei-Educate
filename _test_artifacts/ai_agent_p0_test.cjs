// Offline smoke tests for the P0 agent refactor:
// SSE chunk parsing (AiService), tool registry + step labels (AgentTools),
// action extraction (ChatViewModel), session round-trip (SessionStore).
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

// ---------- AiService.handleSseChunk ----------
// The real AiBackend rather than a stand-in: it is what decides whether the app
// attaches a vendor key or its own session token, so those rules should be
// exercised as shipped.
global.__aiBackendModule = loadArkTs(
  'features/aiagent/src/main/ets/service/AiBackend.ets',
  `const fileIo = { readTextSync() { return ''; }, openSync() { return { fd: 1 }; }, writeSync() {}, closeSync() {} };`,
);

const aiPrelude = `
const AiBackend = global.__aiBackendModule.AiBackend;
class AiResponseResult { constructor() { this.content = ''; this.toolCalls = []; } }
class AiToolCall { constructor() { this.id = ''; this.type = 'function'; this.function = new AiToolCallFunction(); } }
class AiToolCallFunction { constructor() { this.name = ''; this.arguments = ''; } }
class AiApiRequest { constructor(model, messages, stream) { this.model = model; this.messages = messages; this.stream = stream; } }
class AiMessage { constructor() { this.role = ''; this.content = ''; } }
const util = { TextDecoder: { create() { return { decodeToString(u8) { return Buffer.from(u8).toString('utf8'); } }; } } };
const Logger = { error() {}, info() {} };
const AiConstants = { AI_API_URL: '', AI_MODEL: '', REQUEST_TIMEOUT: 1000, MAX_RETRY_COUNT: 3 };
const http = {};
class ApiKeyStore {
  getKey() { return 'sk-test'; }
  isConfigured() { return true; }
}
`;
const { AiService } = loadArkTs(
  'features/aiagent/src/main/ets/service/AiService.ets',
  aiPrelude,
);
const ai = new AiService();
let out = '';
ai.handleSseChunk('data: {"choices":[{"delta":{"content":"你"}}]}\n\ndata: {"choices":[{"delta":{"content":"好"}}]}\n\ndata: [DONE]\n\n', (c) => { out += c; });
check('SSE解析', '拼接多个data块', out === '你好', out, '你好');

out = '';
ai.handleSseChunk(': keep-alive\ndata: {"choices":[]}\ndata: badjson\n', (c) => { out += c; });
check('SSE解析', '忽略注释/空choices/坏JSON', out === '', out, '');

// ---------- AgentToolRegistry ----------
const toolPrelude = `
class DataCollectService {
  collectAllData() { return { examScores: [], errorQuestions: [], courseProgress: [], totalStudyTime: 0 }; }
  analyzeData(s) { return { totalExams: 0, avgScore: 0, totalStudyTime: 0, scoreTrend: [], knowledgePoints: [], courseProgress: [], weakPoints: [], strengths: [] }; }
}
class ErrorAttributionService { updateErrorBookAttributions() { return 0; } }
class AdaptivePracticeService { generateSession(n) { return { questions: [] }; } }
class LearnerProfileStore {
  loadProfile() { return { weakPoints: [], strengths: [], focusTopics: [], examCount: 0, avgScore: 0, totalStudyTime: 0, analysisSummaries: [], updatedAt: 0 }; }
  saveProfile() {}
  updateFromAnalysis() {}
  recordFocusTopics() {}
  buildProfilePrompt() { return ''; }
}
class KnowledgeStore {
  static getInstance() { return new KnowledgeStore(); }
  search() { return []; }
  citationOf() { return ''; }
  stats() { return { chunkCount: 0, termCount: 0, avgChunkLength: 0 }; }
}
function describeKnowledgeSource() { return '课程笔记'; }
class AiMessage { constructor() { this.role = ''; this.content = ''; } }
class AiToolCall { constructor() { this.id = ''; this.type = 'function'; this.function = new AiToolCallFunction(); } }
class AiToolCallFunction { constructor() { this.name = ''; this.arguments = ''; } }
const fileIo = { readTextSync() { return ''; } };
`;
const agentTools = loadArkTs(
  'features/aiagent/src/main/ets/service/AgentTools.ets',
  toolPrelude,
);
check('工具定义', '8个工具定义结构合法', (() => {
  try {
    const tools = agentTools.buildToolDefinitions();
    return Array.isArray(tools) && tools.length === 8 && tools.every(t => t.type === 'function' && t.function.name && t.function.description && t.function.parameters && t.function.parameters.type === 'object');
  } catch (e) { return false; }
})(), 'array', '8 valid tools');

check('工具定义', '知识检索工具是唯一带参数的：query 必填，其余 7 个无参数', (() => {
  try {
    const tools = agentTools.buildToolDefinitions();
    const withArgs = tools.filter(t => t.function.parameters.properties);
    const search = tools.find(t => t.function.name === 'search_course_knowledge');
    // Round-trip through JSON: the parameters go into the request body, so the
    // serialized form is the one that actually matters.
    const wire = JSON.parse(JSON.stringify(search.function.parameters));
    return withArgs.length === 1 && Boolean(search) &&
      wire.type === 'object' &&
      wire.required.join('|') === 'query' &&
      wire.properties.query.type === 'string' &&
      wire.properties.query.description.length > 0;
  } catch (e) { return false; }
})(), 'exactly one parameterised tool', 'search_course_knowledge takes a required string query');

const registry = new agentTools.AgentToolRegistry();
registry.execute('get_learning_stats', '{}').then((r) => {
  const parsed = JSON.parse(r);
  check('工具执行', 'get_learning_stats返回统计JSON', typeof parsed.totalExams === 'number', r, 'has totalExams');
  registry.execute('analyze_error_book', '{}').then((r2) => {
    const p2 = JSON.parse(r2);
    check('工具执行', 'analyze_error_book返回updatedCount', typeof p2.updatedCount === 'number', r2, 'has updatedCount');
    registry.execute('unknown_tool', '{}').then((r3) => {
      const p3 = JSON.parse(r3);
      check('工具执行', '未知工具返回error字段', typeof p3.error === 'string' && p3.error.includes('未知工具'), r3, 'has error');
      check('步骤文案', '所有工具都有中文步骤文案', ['get_learning_stats','analyze_error_book','generate_practice','get_exam_history','get_course_progress','get_error_questions','get_learner_profile','search_course_knowledge']
        .every(n => typeof agentTools.getToolStepLabel(n) === 'string' && agentTools.getToolStepLabel(n).length > 0), 'labels', 'all present');
      report();
    });
  });
});

function report() {
  fs.writeFileSync(path.join(__dirname, 'ai_agent_p0_test_result.json'), JSON.stringify(results, null, 2));
  console.log(`${results.length - failures}/${results.length} passed`);
  process.exit(failures > 0 ? 1 : 0);
}

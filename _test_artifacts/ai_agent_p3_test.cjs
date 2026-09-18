// Offline tests for P3: user-cancel flow (ChatViewModel.cancelRequest,
// AiService fallback guard, AgentService no-fallback-after-cancel),
// agent trace logging (AgentService + AgentTraceLogger).
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

/**
 * Wall-clock values are masked in reported values only. They vary by machine
 * load (elapsed ms) or by the moment of the run (session ids, trace stamps), so
 * leaving them in turns a stable result file into per-run noise. The assertions
 * themselves still run against the real values.
 */
function maskElapsed(text) {
  return typeof text === 'string' ? text.replace(/\d+ms/g, '<ms>') : text;
}
function maskSessionId(id) {
  return typeof id === 'string' ? id.replace(/^session_\d+_/, 'session_<ts>_') : id;
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

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// ---------- Shared stubs ----------
function Observed(target) { return target; }

// ---------- Part 1: AgentTraceLogger ----------
const tracePrelude = `
const Logger = { error() {} };
`;
const fileMap = new Map();
const sizeMap = new Map();
let lastOpenedPath = '';
let lastOpenedMode = 0;
global.AppStorage = {
  data: new Map(),
  get(key) { return this.data.get(key); },
  setOrCreate(key, value) { this.data.set(key, value); },
};
global.fileIo = {
  statSync(p) {
    if (!fileMap.has(p)) { throw new Error('no such file'); }
    return { size: sizeMap.get(p) || 0 };
  },
  openSync(p, mode) {
    lastOpenedPath = p;
    lastOpenedMode = mode;
    return { fd: 1 };
  },
  writeSync(fd, text) {
    const truncate = (lastOpenedMode & 0o1000) !== 0;
    if (truncate || !fileMap.has(lastOpenedPath)) {
      fileMap.set(lastOpenedPath, text);
    } else {
      fileMap.set(lastOpenedPath, fileMap.get(lastOpenedPath) + text);
    }
    sizeMap.set(lastOpenedPath, fileMap.get(lastOpenedPath).length);
  },
  closeSync() {},
};
global.AppStorage.data.clear();
global.AppStorage.data.set('filesDir', '/tmp/p3test');

const traceMod = loadArkTs(
  'features/aiagent/src/main/ets/service/AgentTraceLogger.ets',
  tracePrelude,
);
const tracer = new traceMod.AgentTraceLogger();

// Every line carries a wall-clock prefix, which is the point of the logger — but
// it also means the raw file text changes on every run. Reporting it verbatim
// would rewrite the result file each time and turn a stable artifact into
// per-run noise, so the stamp is masked in the reported value. The assertions
// themselves still run against the unstamped-in-spirit real text.
function maskTraceTimestamps(text) {
  return text.replace(/\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\]/g, '[timestamp]');
}

tracer.log('tool get_learning_stats done: 12ms');
const traceText = fileMap.get('/tmp/p3test/agentTrace.log') || '';
check('轨迹日志', '写入文件且带时间戳前缀', traceText.indexOf('[20') >= 0 && traceText.indexOf('tool get_learning_stats done: 12ms') >= 0, maskTraceTimestamps(traceText), 'timestamped line');

tracer.log('round 1: 2 tool calls');
check('轨迹日志', '追加写入不覆盖', traceText !== fileMap.get('/tmp/p3test/agentTrace.log') &&
  fileMap.get('/tmp/p3test/agentTrace.log').indexOf('round 1: 2 tool calls') >= 0, maskTraceTimestamps(fileMap.get('/tmp/p3test/agentTrace.log')), 'appended');

// File too large -> next write truncates and only the new line remains.
const bigPath = '/tmp/p3test/agentTrace.log';
sizeMap.set(bigPath, 300 * 1024);
fileMap.set(bigPath, 'x'.repeat(300 * 1024));
tracer.log('truncate-check-line');
const afterTruncate = fileMap.get(bigPath);
check('轨迹日志', '超过256KB后截断重写', afterTruncate.indexOf('truncate-check-line') >= 0 && afterTruncate.length < 200, afterTruncate.length, 'small file after truncate');

// No filesDir -> no-op, no throw.
const noDirMod = loadArkTs(
  'features/aiagent/src/main/ets/service/AgentTraceLogger.ets',
  tracePrelude,
);
global.AppStorage.data.delete('filesDir');
let threw = false;
try {
  new noDirMod.AgentTraceLogger().log('should not write');
} catch (e) {
  threw = true;
}
check('轨迹日志', '无filesDir时不崩溃', !threw, threw, false);

// ---------- Part 2: AgentService trace + cancel ----------
(async () => {
global.AppStorage.data.set('filesDir', '/tmp/p3test');
const agentServicePrelude = `
const Logger = { error() {}, info() {} };
class AiMessage { constructor() { this.role = ''; this.content = ''; } }
class AiResponseResult { constructor() { this.content = ''; this.toolCalls = []; } }
class AiToolCall { constructor() { this.id = ''; this.type = 'function'; this.function = new AiToolCallFunction(); } }
class AiToolCallFunction { constructor() { this.name = ''; this.arguments = ''; } }
class ToolErrorResult { constructor() { this.error = ''; } }
function buildToolDefinitions() { return []; }
function buildToolCallsMessage(calls) {
  const m = new AiMessage(); m.role = 'assistant'; m.tool_calls = calls; return m;
}
function buildToolResultMessage(id, result) {
  const m = new AiMessage(); m.role = 'tool'; m.tool_call_id = id; m.content = result; return m;
}
function getToolStepLabel(name) { return '步骤:' + name; }
class AgentToolRegistry {
  async execute(name, args) { return '{"ok":true}'; }
}
const traceLines = [];
global.traceLines = traceLines;
class AgentTraceLogger {
  log(line) { traceLines.push(line); }
}
class AiService {
  constructor() {
    this.chatCalls = 0;
    this.fallbackCalls = 0;
    this.cancelled = false;
    this.mode = 'happy';
  }
  async chat(messages, tools, maxTokens) {
    this.chatCalls += 1;
    if (this.mode === 'failFirst' && tools) {
      throw new Error('api 500');
    }
    if (this.mode === 'hang') {
      await new Promise((resolve) => setTimeout(resolve, 300));
      if (this.cancelled) { throw new Error('Request cancelled'); }
    }
    if (this.chatCalls === 1) {
      const r = new AiResponseResult();
      const c = new AiToolCall();
      c.id = 'call_1';
      c.function.name = 'get_learning_stats';
      c.function.arguments = '{}';
      r.toolCalls = [c];
      return r;
    }
    const r2 = new AiResponseResult();
    r2.content = '最终回答';
    return r2;
  }
  async chatWithFallback(messages, onChunk) {
    this.fallbackCalls += 1;
    onChunk('最终回答');
    return 4;
  }
  cancelRequest() { this.cancelled = true; }
}
`;

const agentMod = loadArkTs(
  'features/aiagent/src/main/ets/service/AgentService.ets',
  agentServicePrelude,
);

// --- Flow A: happy tool path, trace lines recorded ---
global.traceLines.length = 0;
const svcA = new agentMod.AgentService();
const stepsA = [];
let chunksA = '';
await svcA.run(
  [{ role: 'user', content: '分析学习情况' }],
  (text, done) => stepsA.push({ text, done }),
  (chunk) => { chunksA += chunk; },
);
check('Agent轨迹', '步骤回调含工具文案且完成', stepsA.length === 2 && stepsA[0].text === '步骤:get_learning_stats' && stepsA[0].done === false && stepsA[1].done === true, JSON.stringify(stepsA), 'step + done');
check('Agent轨迹', '最终回答交付', chunksA === '最终回答', chunksA, '最终回答');
check('Agent轨迹', '记录run开始/轮次/工具耗时/完成', global.traceLines.some(l => l.indexOf('agent run start') >= 0) &&
  global.traceLines.some(l => l.indexOf('round 0: 1 tool calls') >= 0) &&
  global.traceLines.some(l => l.indexOf('tool get_learning_stats done') >= 0) &&
  global.traceLines.some(l => l.indexOf('final answer delivered: 4 chars, 1 rounds') >= 0) &&
  global.traceLines.some(l => l.indexOf('agent run done') >= 0), JSON.stringify(global.traceLines), 'full trace');
check('Agent轨迹', '工具耗时字段为数字ms', /tool get_learning_stats done: \d+ms/.test(global.traceLines.join('\n')), global.traceLines.join('\n'), 'duration in ms');

// --- Flow B: tool call fails, not cancelled -> plain fallback, no chatWithFallback ---
global.traceLines.length = 0;
const svcB = new agentMod.AgentService();
svcB.aiService.mode = 'failFirst';
let chunksB = '';
await svcB.run(
  [{ role: 'user', content: 'x' }],
  () => {},
  (chunk) => { chunksB += chunk; },
);
check('Agent降级', '工具调用失败后降级plain chat', chunksB === '最终回答' && svcB.aiService.chatCalls === 2 && svcB.aiService.fallbackCalls === 0, { chunksB, chatCalls: svcB.aiService.chatCalls, fallbackCalls: svcB.aiService.fallbackCalls }, 'plain fallback used');
check('Agent降级', '轨迹含降级记录', global.traceLines.some(l => l.indexOf('falling back to plain chat') >= 0) && global.traceLines.some(l => l.indexOf('plain fallback delivered') >= 0), JSON.stringify(global.traceLines), 'fallback traced');

// --- Flow C: cancelled mid-flight -> no plain fallback, no chatWithFallback ---
global.traceLines.length = 0;
const svcC = new agentMod.AgentService();
svcC.aiService.mode = 'hang';
let rejectedMsg = '';
const runPromise = svcC.run(
  [{ role: 'user', content: 'x' }],
  () => {},
  () => {},
).catch((err) => { rejectedMsg = err.message; });
await sleep(30);
svcC.cancel();
await runPromise;
check('Agent取消', '取消后以Request cancelled终止', rejectedMsg === 'Request cancelled', rejectedMsg, 'Request cancelled');
check('Agent取消', '取消后不触发plain降级/不发起新请求', svcC.aiService.chatCalls === 1 && svcC.aiService.fallbackCalls === 0, { chatCalls: svcC.aiService.chatCalls, fallbackCalls: svcC.aiService.fallbackCalls }, 'no extra calls');
check('Agent取消', '轨迹记录run failed', global.traceLines.some(l => l.indexOf('agent run failed: Request cancelled') >= 0), maskElapsed(JSON.stringify(global.traceLines)), 'cancel traced');

// ---------- Part 3: ChatViewModel.cancelRequest ----------
global.aiServiceInstances = [];
global.agentServiceInstances = [];
global.saveCalls = [];
const saveCalls = global.saveCalls;
const chatVmPrelude = `
function Observed(target) { return target; }
const Logger = { error() {}, info() {} };
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
global.MessageStatus = MessageStatus;
global.ChatMessage = ChatMessage;
const ChatIntent = { PRACTICE: 'practice', ANALYTICS: 'analytics', KNOWLEDGE: 'knowledge', CHAT: 'chat' };
class AiMessage { constructor() { this.role = ''; this.content = ''; } }
class AgentLimitError extends Error {}
class AgentTimeoutError extends Error {}
class ApiKeyMissingError extends Error {}
class AiService {
  constructor() {
    global.aiServiceInstances.push(this);
    this.cancelled = false;
    this.fallbackCalls = 0;
  }
  cancelRequest() { this.cancelled = true; }
  async chatWithFallback(messages, onChunk) {
    this.fallbackCalls += 1;
    await new Promise((resolve) => setTimeout(resolve, 250));
    if (!this.cancelled) { onChunk('部分回答'); return 4; }
    return 0;
  }
}
class AgentService {
  constructor() {
    global.agentServiceInstances.push(this);
    this.cancelled = false;
  }
  cancel() { this.cancelled = true; }
  async run(messages, onStep, onChunk) {
    await new Promise((resolve) => setTimeout(resolve, 250));
    if (!this.cancelled) { onChunk('agent回答'); }
  }
}
class SessionStore {
  loadSessions() { return []; }
  saveSessions(sessions) { global.saveCalls.push(sessions.length); }
}
class DataCollectService { collectAllData() { return { errorQuestions: [] }; } }
class ErrorAttributionService { updateErrorBookAttributions() { return 0; } }
class AdaptivePracticeService { generateSession(n) { return { questions: [] }; } }
class PracticeSessionStore { savePendingSession() {} }
class IntentRouter {
  route(text) { return text.indexOf('分析') >= 0 ? ChatIntent.ANALYTICS : ChatIntent.CHAT; }
}
class ContextCompressor { buildHistorySummary(m) { return ''; } }
class LearnerProfileStore {
  buildProfilePrompt() { return ''; }
  recordFocusTopics() {}
  recordAnalysisSummary() {}
}
class KnowledgeStore {
  static getInstance() { return new KnowledgeStore(); }
  search() { return global.knowledgeHits || []; }
  citationOf() { return '出处'; }
  buildContextBlock(hits) { return hits.length > 0 ? '【检索到的课程资料】' : ''; }
}
const AiConstants = {
  SYSTEM_PROMPT: 'sys', WELCOME_MESSAGE: 'welcome', MAX_HISTORY_MESSAGES: 20,
  KNOWLEDGE_SYSTEM_PROMPT: 'knowledge sys',
  RECOMMEND_QUESTIONS: [], AI_MODEL: '', AI_API_URL: '', API_KEY: '', REQUEST_TIMEOUT: 1000,
};
`;
const chatVmMod = loadArkTs(
  'features/aiagent/src/main/ets/viewmodel/ChatViewModel.ets',
  chatVmPrelude,
);

// --- T1: no in-flight request -> no-op ---
{
  const vm = new chatVmMod.ChatViewModel();
  vm.cancelRequest();
  const ai = global.aiServiceInstances[global.aiServiceInstances.length - 1];
  check('取消按钮', '无请求时cancel为no-op', vm.isLoading === false && ai.cancelled === false, { isLoading: vm.isLoading, cancelled: ai.cancelled }, 'no-op');
}

// --- T2: cancel during CHAT ---
{
  const vm = new chatVmMod.ChatViewModel();
  const ai = global.aiServiceInstances[global.aiServiceInstances.length - 1];
  const sendP = vm.sendMessage('什么是导数');
  await sleep(50);
  const before = vm.currentSession.messages.length;
  vm.cancelRequest();
  await sleep(50);
  check('取消按钮', 'CHAT中取消:请求被终止', ai.cancelled === true, ai.cancelled, true);
  check('取消按钮', 'CHAT中取消:isLoading/isStreaming复位', vm.isLoading === false && vm.isStreaming === false, { isLoading: vm.isLoading, isStreaming: vm.isStreaming }, 'reset');
  check('取消按钮', 'CHAT中取消:SENDING气泡被移除', vm.currentSession.messages.every(m => m.status !== MessageStatus.SENDING) &&
    vm.currentSession.messages.length === before - 1, vm.currentSession.messages.map(m => m.role + '/' + m.status), 'pending bubble dropped');
  await sendP;
  await sleep(300);
  check('取消按钮', 'CHAT中取消:残留回调不产生FAILED消息', vm.currentSession.messages.every(m => m.status !== MessageStatus.FAILED) &&
    vm.currentSession.messages.filter(m => m.content === 'AI 未返回有效回答，请稍后重试。').length === 0, vm.currentSession.messages.map(m => m.content), 'no fake error');
}

// --- T3: cancel during ANALYTICS (agent path) ---
{
  const vm = new chatVmMod.ChatViewModel();
  const ai = global.aiServiceInstances[global.aiServiceInstances.length - 1];
  const agent = global.agentServiceInstances[global.agentServiceInstances.length - 1];
  const sendP = vm.sendMessage('帮我分析学习情况');
  await sleep(50);
  vm.cancelRequest();
  await sleep(50);
  check('取消按钮', 'ANALYTICS中取消:agent与请求均被终止', agent.cancelled === true && ai.cancelled === true, { agentCancelled: agent.cancelled, aiCancelled: ai.cancelled }, 'both cancelled');
  check('取消按钮', 'ANALYTICS中取消:状态复位且无残留', vm.isLoading === false && vm.currentSession.messages.every(m => m.status !== MessageStatus.FAILED), { isLoading: vm.isLoading }, 'clean state');
  await sendP;
}

// --- T4: session management backing logic (P3-2 UI depends on it) ---
{
  const vm = new chatVmMod.ChatViewModel();
  const firstId = vm.currentSession.id;
  vm.currentSession.messages = [...vm.currentSession.messages, new ChatMessage('m_user_1', 'user', 'hi', 'success')];
  vm.newSession();
  check('会话管理', 'newSession创建第二个会话', vm.sessionList.length === 2 && vm.currentSession.id !== firstId, vm.sessionList.length, 2);
  const secondId = vm.currentSession.id;
  vm.switchSession(firstId);
  check('会话管理', 'switchSession切换回第一个', vm.currentSession.id === firstId, maskSessionId(vm.currentSession.id), maskSessionId(firstId));
  const beforeDelete = global.saveCalls.length;
  vm.deleteSession(firstId);
  check('会话管理', 'deleteSession移除并落到剩余会话', vm.sessionList.length === 1 && vm.currentSession.id === secondId, { count: vm.sessionList.length, current: maskSessionId(vm.currentSession.id) }, 'one left');
  check('会话管理', '删除后触发持久化', global.saveCalls.length === beforeDelete + 1, global.saveCalls, 'saved once');
}

report();
})();

function report() {
  fs.writeFileSync(path.join(__dirname, 'ai_agent_p3_test_result.json'), JSON.stringify(results, null, 2));
  console.log(`${results.length - failures}/${results.length} passed`);
  process.exit(failures > 0 ? 1 : 0);
}

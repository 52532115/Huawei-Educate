// Offline tests for P4: runtime API key (ApiKeyStore + ApiKeyMissingError),
// request retries with cancellation, Markdown parsing, image magic-byte MIME
// detection, and static source checks for the remaining harness items.
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

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// ---------- Part 1: ApiKeyStore ----------
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

const keyStorePrelude = `
const Logger = { error() {}, info() {} };
`;
const keyStoreMod = loadArkTs(
  'features/aiagent/src/main/ets/service/ApiKeyStore.ets',
  keyStorePrelude,
);

global.AppStorage.data.clear();
global.AppStorage.data.set('filesDir', '/tmp/p4test');
const ks = new keyStoreMod.ApiKeyStore();
check('APIKey', '初始为空', ks.getKey() === '', ks.getKey(), '');
ks.saveKey('  sk-runtime-key-123  ');
check('APIKey', '保存后取到且去空格', ks.getKey() === 'sk-runtime-key-123', ks.getKey(), 'sk-runtime-key-123');
check('APIKey', 'isConfigured为true', ks.isConfigured() === true, ks.isConfigured(), true);
global.AppStorage.data.clear(); // simulate restart: only the file remains
global.AppStorage.data.set('filesDir', '/tmp/p4test');
const ks2 = new keyStoreMod.ApiKeyStore();
check('APIKey', '重启后从文件恢复', ks2.getKey() === 'sk-runtime-key-123', ks2.getKey(), 'sk-runtime-key-123');
ks2.clearKey();
check('APIKey', 'clearKey后为空', ks2.getKey() === '' && ks2.isConfigured() === false, ks2.getKey(), '');

// ---------- Part 2: AiService — missing key + retries ----------
global.aiKeyValue = 'sk-test';
// The real AiBackend, not a stand-in: it is the only thing that decides whether
// a vendor key or the app's own session token is attached, so the routing rules
// should be exercised exactly as they ship.
global.__aiBackendModule = loadArkTs(
  'features/aiagent/src/main/ets/service/AiBackend.ets',
  `const Logger = { error() {}, info() {}, warn() {} };`,
);
const aiPrelude = `
const AiBackend = global.__aiBackendModule.AiBackend;
const util = { TextDecoder: { create() { return { decodeToString(u8) { return Buffer.from(u8).toString('utf8'); } }; } } };
const Logger = { error() {}, info() {} };
const AiConstants = { AI_API_URL: 'https://api.test/v1/chat/completions', AI_MODEL: 'm', REQUEST_TIMEOUT: 1000, MAX_RETRY_COUNT: 3 };
const http = global.httpStub;
class ApiKeyStore {
  getKey() { return global.aiKeyValue; }
  isConfigured() { return global.aiKeyValue.length > 0; }
}
class AiResponseResult { constructor() { this.content = ''; this.toolCalls = []; } }
class AiToolCall { constructor() { this.id = ''; this.type = 'function'; this.function = new AiToolCallFunction(); } }
class AiToolCallFunction { constructor() { this.name = ''; this.arguments = ''; } }
class AiApiRequest { constructor(model, messages, stream) { this.model = model; this.messages = messages; this.stream = stream; } }
class AiMessage { constructor() { this.role = ''; this.content = ''; } }
`;

// Fake http: fails `failCount` times, then succeeds.
global.httpStub = {
  failCount: 0,
  attempts: 0,
  responseCode: 200,
  lastUrl: '',
  lastHeaders: {},
  successBody: '{"choices":[{"message":{"content":"你好"}}]}',
  RequestMethod: { POST: 'POST' },
  HttpDataType: { STRING: 'string' },
  createHttp() {
    const req = {
      destroyed: false,
      destroy() { this.destroyed = true; },
      async request(url, opts) {
        global.httpStub.attempts += 1;
        global.httpStub.lastUrl = url;
        global.httpStub.lastHeaders = (opts && opts.header) ? opts.header : {};
        await Promise.resolve();
        if (global.httpStub.failCount > 0) {
          global.httpStub.failCount -= 1;
          throw new Error('network error');
        }
        return { responseCode: global.httpStub.responseCode, result: global.httpStub.successBody };
      },
    };
    return req;
  },
};

const aiMod = loadArkTs(
  'features/aiagent/src/main/ets/service/AiService.ets',
  aiPrelude,
);

(async () => {
  // --- missing key: friendly error ---
  global.aiKeyValue = '';
  const aiNoKey = new aiMod.AiService(5000, 10);
  let missingMsg = '';
  try {
    await aiNoKey.chat([{ role: 'user', content: 'hi' }]);
  } catch (e) {
    missingMsg = e.message;
  }
  check('APIKey', '缺key时chat抛友好错误', missingMsg.indexOf('尚未配置 API Key') >= 0 && missingMsg.indexOf('⚙️') >= 0, missingMsg, 'friendly hint');
  let streamMsg = '';
  try {
    await aiNoKey.chatStream([{ role: 'user', content: 'hi' }], () => {});
  } catch (e) {
    streamMsg = e.message;
  }
  check('APIKey', '缺key时chatStream同样报错', streamMsg.indexOf('尚未配置 API Key') >= 0, streamMsg, 'friendly hint');

  // --- retry: 2 failures then success, 3 attempts total ---
  global.aiKeyValue = 'sk-test';
  global.httpStub.failCount = 2;
  global.httpStub.attempts = 0;
  const aiRetry = new aiMod.AiService(5000, 10);
  const result = await aiRetry.chat([{ role: 'user', content: 'hi' }]);
  check('重试', '2次失败后第3次成功', global.httpStub.attempts === 3 && result.content === '你好', { attempts: global.httpStub.attempts, content: result.content }, '3 attempts, 你好');

  // --- retry exhausted: all attempts fail ---
  global.httpStub.failCount = 10;
  global.httpStub.attempts = 0;
  const aiFail = new aiMod.AiService(5000, 10);
  let failMsg = '';
  try {
    await aiFail.chat([{ role: 'user', content: 'hi' }]);
  } catch (e) {
    failMsg = e.message;
  }
  check('重试', '全失败时抛错且尝试次数为MAX+1', global.httpStub.attempts === 4 && failMsg === 'network error', { attempts: global.httpStub.attempts, msg: failMsg }, '4 attempts');

  // --- cancel during retry backoff: aborts immediately ---
  global.httpStub.failCount = 10;
  global.httpStub.attempts = 0;
  const aiCancel = new aiMod.AiService(5000, 200);
  let cancelMsg = '';
  const p = aiCancel.chat([{ role: 'user', content: 'hi' }]).catch((e) => { cancelMsg = e.message; });
  await sleep(50); // first attempt failed, now sleeping before retry
  const attemptsAtCancel = global.httpStub.attempts;
  aiCancel.cancelRequest();
  await p;
  await sleep(500); // if cancellation were ignored, more attempts would fire
  check('重试', '取消后中止重试', cancelMsg === 'Request cancelled' && global.httpStub.attempts === attemptsAtCancel, { msg: cancelMsg, attempts: global.httpStub.attempts, atCancel: attemptsAtCancel }, 'no further attempts');

  // ---------- Part 3: backend mode — the app carries no vendor key ----------
  const { AiBackend, AiBackendStore } = global.__aiBackendModule;

  global.aiKeyValue = 'sk-vendor-key-should-not-leave-the-device';
  global.httpStub.responseCode = 200;
  global.httpStub.failCount = 0;

  const noBackend = new AiBackend('', '');
  const withBackend = new AiBackend('https://ai.example.edu/', 'app-session-token');

  check('后端', 'AiBackend 去掉末尾斜杠并按路径拼接',
    withBackend.getBaseUrl() === 'https://ai.example.edu' &&
    withBackend.chatUrl() === 'https://ai.example.edu/v1/chat/completions' &&
    withBackend.embedUrl() === 'https://ai.example.edu/embed',
    { base: withBackend.getBaseUrl(), chat: withBackend.chatUrl(), embed: withBackend.embedUrl() },
    'normalized base + two paths');

  check('后端', '模式只由 baseUrl 决定，令牌不参与判断',
    noBackend.mode() === 'direct' && noBackend.usesBackend() === false &&
    withBackend.mode() === 'backend' && withBackend.usesBackend() === true &&
    new AiBackend('', 'orphan-token').mode() === 'direct',
    { none: noBackend.mode(), some: withBackend.mode(), orphan: new AiBackend('', 't').mode() },
    'direct / backend / direct');

  check('后端', 'authHeader 无令牌时为空串（不发一个空的 Bearer）',
    noBackend.authHeader() === '' && withBackend.authHeader() === 'Bearer app-session-token',
    { none: noBackend.authHeader(), some: withBackend.authHeader() }, 'empty / Bearer token');

  // --- direct mode must behave exactly as before ---
  const aiDirect = new aiMod.AiService(5000, 10, new AiBackend('', ''));
  await aiDirect.chat([{ role: 'user', content: 'hi' }]);
  check('后端', '直连模式：打到厂商地址，带用户填的 API Key',
    global.httpStub.lastUrl === 'https://api.test/v1/chat/completions' &&
    global.httpStub.lastHeaders['Authorization'] === 'Bearer sk-vendor-key-should-not-leave-the-device',
    { url: global.httpStub.lastUrl, auth: global.httpStub.lastHeaders['Authorization'] },
    'vendor url + vendor key');

  // --- backend mode: right endpoint, right credential, no vendor key ---
  const aiBackend = new aiMod.AiService(5000, 10, withBackend);
  await aiBackend.chat([{ role: 'user', content: 'hi' }]);
  check('后端', '后端模式：打到后端地址、只带应用令牌，绝不带厂商 Key',
    global.httpStub.lastUrl === 'https://ai.example.edu/v1/chat/completions' &&
    global.httpStub.lastHeaders['Authorization'] === 'Bearer app-session-token' &&
    JSON.stringify(global.httpStub.lastHeaders).indexOf('sk-vendor-key') < 0,
    { url: global.httpStub.lastUrl, auth: global.httpStub.lastHeaders['Authorization'] },
    'backend url + app token only');

  check('后端', 'getMode 报告当前模式', aiBackend.getMode() === 'backend' && aiDirect.getMode() === 'direct',
    { backend: aiBackend.getMode(), direct: aiDirect.getMode() }, 'backend / direct');

  // --- the point of the whole exercise: no key required in backend mode ---
  global.aiKeyValue = '';
  const aiBackendNoKey = new aiMod.AiService(5000, 10, new AiBackend('https://ai.example.edu', ''));
  let backendErr = '';
  try {
    await aiBackendNoKey.chat([{ role: 'user', content: 'hi' }]);
  } catch (e) {
    backendErr = e.message;
  }
  check('后端', '后端模式下未配 Key 也不报缺 Key（厂商密钥在服务端）',
    backendErr === '' && global.httpStub.lastUrl === 'https://ai.example.edu/v1/chat/completions',
    { err: backendErr, url: global.httpStub.lastUrl }, 'no ApiKeyMissingError');

  check('后端', '后端模式无令牌时不发 Authorization 头',
    global.httpStub.lastHeaders['Authorization'] === undefined,
    global.httpStub.lastHeaders, 'no Authorization header');

  let stillMissing = '';
  try {
    await new aiMod.AiService(5000, 10, new AiBackend('', '')).chat([{ role: 'user', content: 'hi' }]);
  } catch (e) {
    stillMissing = e.message;
  }
  check('后端', '直连模式未配 Key 仍报原友好错误（行为不变）',
    stillMissing.indexOf('尚未配置 API Key') >= 0, stillMissing, 'friendly hint');

  // --- the default constructor path reads the setting from AppStorage ---
  global.AppStorage.data.set('aiBackendUrl', 'https://from-appstorage.example/');
  global.AppStorage.data.set('aiBackendToken', 'tok-from-appstorage');
  const fromStorage = AiBackend.fromAppStorage();
  const defaultConstructed = new aiMod.AiService(5000, 10);
  check('后端', 'fromAppStorage 读到地址与令牌，AiService 默认构造即采用它',
    fromStorage.getBaseUrl() === 'https://from-appstorage.example' &&
    fromStorage.getToken() === 'tok-from-appstorage' &&
    defaultConstructed.getMode() === 'backend',
    { url: fromStorage.getBaseUrl(), mode: defaultConstructed.getMode() },
    'read from AppStorage and used by default');
  global.AppStorage.data.delete('aiBackendUrl');
  global.AppStorage.data.delete('aiBackendToken');

  // A settings change must take effect on the next request, not the next
  // session. The sheet lives on the chat page, so a change that only applied
  // after leaving and re-entering would look like it did nothing at all.
  const liveService = new aiMod.AiService(5000, 10);
  const modeBeforeSwitch = liveService.getMode();
  global.AppStorage.data.set('aiBackendUrl', 'https://switched.example');
  global.AppStorage.data.set('aiBackendToken', 'tok-switched');
  const modeAfterSwitch = liveService.getMode();
  global.aiKeyValue = 'sk-vendor-key-should-not-leave-the-device';
  global.httpStub.responseCode = 200;
  global.httpStub.failCount = 0;
  await liveService.chat([{ role: 'user', content: 'hi' }]);
  check('后端', '改设置后无需重建服务：同一实例的下一次请求即走新地址、带新令牌',
    modeBeforeSwitch === 'direct' && modeAfterSwitch === 'backend' &&
    global.httpStub.lastUrl === 'https://switched.example/v1/chat/completions' &&
    global.httpStub.lastHeaders['Authorization'] === 'Bearer tok-switched',
    { before: modeBeforeSwitch, after: modeAfterSwitch, url: global.httpStub.lastUrl,
      auth: global.httpStub.lastHeaders['Authorization'] },
    'direct → backend without reconstruction');
  global.AppStorage.data.delete('aiBackendUrl');
  global.AppStorage.data.delete('aiBackendToken');

  // ---------- Part 4: status codes are explained, not blindly retried ----------
  global.aiKeyValue = 'sk-test';

  check('错误码', 'isRetryableStatus：只有 408/429/5xx 算瞬态',
    aiMod.isRetryableStatus(408) === true && aiMod.isRetryableStatus(429) === true &&
    aiMod.isRetryableStatus(500) === true && aiMod.isRetryableStatus(503) === true &&
    aiMod.isRetryableStatus(400) === false && aiMod.isRetryableStatus(401) === false &&
    aiMod.isRetryableStatus(402) === false && aiMod.isRetryableStatus(403) === false &&
    aiMod.isRetryableStatus(404) === false && aiMod.isRetryableStatus(422) === false,
    'classification', 'only transient statuses');

  check('错误码', 'friendlyApiMessage：已知状态码都有可读文案，且不再露出裸状态码',
    (() => {
      const known = [0, 400, 401, 402, 403, 404, 408, 429, 500, 502, 503, 504];
      for (const c of known) {
        const text = aiMod.friendlyApiMessage(c);
        if (typeof text !== 'string' || text.length === 0) {
          return false;
        }
        if (c !== 0 && text.indexOf(String(c)) >= 0) {
          return false;
        }
      }
      return aiMod.friendlyApiMessage(402).indexOf('余额') >= 0 &&
        aiMod.friendlyApiMessage(429).indexOf('频繁') >= 0 &&
        aiMod.friendlyApiMessage(401).indexOf('鉴权') >= 0;
    })(), { 402: aiMod.friendlyApiMessage(402), 429: aiMod.friendlyApiMessage(429) },
    'friendly for every known code');

  // --- the regression this whole section exists for: 402 must stop at once ---
  global.httpStub.responseCode = 402;
  global.httpStub.attempts = 0;
  let code402 = -1;
  let msg402 = '';
  try {
    await new aiMod.AiService(5000, 10, new AiBackend('', '')).chat([{ role: 'user', content: 'hi' }]);
  } catch (e) {
    code402 = e.code;
    msg402 = e.message;
  }
  check('错误码', '402 立即停止：只请求 1 次（此前会空转 4 次、白等 3.6 秒）',
    global.httpStub.attempts === 1 && code402 === 402 && msg402.indexOf('余额') >= 0,
    { attempts: global.httpStub.attempts, code: code402, msg: msg402 }, '1 attempt, code 402');

  global.httpStub.responseCode = 401;
  global.httpStub.attempts = 0;
  let code401 = -1;
  try {
    await new aiMod.AiService(5000, 10, new AiBackend('', '')).chat([{ role: 'user', content: 'hi' }]);
  } catch (e) {
    code401 = e.code;
  }
  check('错误码', '401 立即停止：只请求 1 次',
    global.httpStub.attempts === 1 && code401 === 401,
    { attempts: global.httpStub.attempts, code: code401 }, '1 attempt');

  global.httpStub.responseCode = 400;
  global.httpStub.attempts = 0;
  let code400 = -1;
  try {
    await new aiMod.AiService(5000, 10, new AiBackend('', '')).chat([{ role: 'user', content: 'hi' }]);
  } catch (e) {
    code400 = e.code;
  }
  check('错误码', '400 立即停止：只请求 1 次',
    global.httpStub.attempts === 1 && code400 === 400,
    { attempts: global.httpStub.attempts, code: code400 }, '1 attempt');

  global.httpStub.responseCode = 429;
  global.httpStub.attempts = 0;
  let code429 = -1;
  try {
    await new aiMod.AiService(5000, 10, new AiBackend('', '')).chat([{ role: 'user', content: 'hi' }]);
  } catch (e) {
    code429 = e.code;
  }
  check('错误码', '429 属瞬态：仍重试到 MAX+1 次',
    global.httpStub.attempts === 4 && code429 === 429,
    { attempts: global.httpStub.attempts, code: code429 }, '4 attempts');

  global.httpStub.responseCode = 500;
  global.httpStub.attempts = 0;
  let code500 = -1;
  try {
    await new aiMod.AiService(5000, 10, new AiBackend('', '')).chat([{ role: 'user', content: 'hi' }]);
  } catch (e) {
    code500 = e.code;
  }
  check('错误码', '5xx 属瞬态：仍重试到 MAX+1 次',
    global.httpStub.attempts === 4 && code500 === 500,
    { attempts: global.httpStub.attempts, code: code500 }, '4 attempts');
  global.httpStub.responseCode = 200;

  // ---------- Part 5: backend settings persist like the key does ----------
  global.AppStorage.data.clear();
  global.AppStorage.data.set('filesDir', '/tmp/p4test');
  fileMap.clear();
  const store = new AiBackendStore();
  check('后端设置', '初始为未配置', store.isConfigured() === false, store.isConfigured(), false);

  store.save(new AiBackend('https://ai.example.edu/', 'tok-1'));
  const loadedBackend = store.load();
  check('后端设置', '保存后规范化并读回',
    loadedBackend.getBaseUrl() === 'https://ai.example.edu' && loadedBackend.getToken() === 'tok-1',
    { url: loadedBackend.getBaseUrl(), token: loadedBackend.getToken() }, 'normalized url + token');

  global.AppStorage.data.clear(); // simulate a restart: only the file remains
  global.AppStorage.data.set('filesDir', '/tmp/p4test');
  const afterRestart = new AiBackendStore().load();
  check('后端设置', '重启后从文件恢复（两行：地址 + 令牌）',
    afterRestart.getBaseUrl() === 'https://ai.example.edu' && afterRestart.getToken() === 'tok-1',
    { url: afterRestart.getBaseUrl(), token: afterRestart.getToken() }, 'restored from file');

  check('后端设置', 'parse：只有一行时令牌为空、地址完整',
    (() => {
      const only = new AiBackendStore().parse('https://a.example');
      return only.getBaseUrl() === 'https://a.example' && only.getToken() === '';
    })(), 'single line', 'url only');

  check('后端设置', 'parse：空串不产生配置',
    new AiBackendStore().parse('').isConfigured() === false, 'empty', false);

  new AiBackendStore().clear();
  check('后端设置', 'clear 后回到未配置且不抛异常',
    new AiBackendStore().isConfigured() === false, new AiBackendStore().isConfigured(), false);

  report();
})();

// ---------- Part 3: Markdown parser ----------
// The @Builder/@Component struct UI at the end of the file is not valid TS;
// strip it and test only the pure parser functions.
function stripMarkdownUi(relativePath) {
  let src = fs.readFileSync(path.join(root, relativePath), 'utf8');
  const marker = src.indexOf('/** Renders one line\'s inline spans');
  if (marker >= 0) {
    src = src.substring(0, marker);
  }
  return src.replace(/import[\s\S]*?from\s+['"][^'"]+['"];\s*/g, '');
}
function loadMarkdownParser(relativePath) {
  const src = stripMarkdownUi(relativePath);
  const compiled = ts.transpileModule(src, {
    compilerOptions: {
      module: ts.ModuleKind.CommonJS,
      target: ts.ScriptTarget.ES2020,
      esModuleInterop: true,
    },
  }).outputText;
  const module = { exports: {} };
  new Function('module', 'exports', compiled)(module, module.exports);
  return module.exports;
}

const mdMod = loadMarkdownParser('features/aiagent/src/main/ets/components/MarkdownText.ets');

{
  const blocks = mdMod.parseMarkdown('# 标题一\n\n普通段落第一行\n第二行\n\n- 项目1\n- 项目2\n\n1. 第一步\n2. 第二步\n\n\`\`\`\nconst x = 1;\n\`\`\`\n\n### 小标题');
  check('Markdown', '标题/段落/列表/代码块种类齐全', blocks.length === 6 &&
    blocks[0].kind === 1 && blocks[0].level === 1 && blocks[0].lines[0] === '标题一' &&
    blocks[1].kind === 0 && blocks[1].lines.length === 2 &&
    blocks[2].kind === 3 && blocks[2].lines.length === 2 &&
    blocks[3].kind === 4 && blocks[3].lines[0] === '第一步' &&
    blocks[4].kind === 2 && blocks[4].lines[0] === 'const x = 1;' &&
    blocks[5].kind === 1 && blocks[5].level === 3, blocks.map(b => `${b.kind}:${b.level}:${b.lines.length}`), 'typed blocks');
}

{
  const blocks = mdMod.parseMarkdown('####### 不是标题\n\n普通文字');
  check('Markdown', '7个#不算标题', blocks.length === 2 && blocks[0].kind === 0 && blocks[0].lines[0].startsWith('#######'), blocks.map(b => b.kind), 'paragraph');
}

{
  const spans = mdMod.parseInline('这是**加粗**和\`代码\`结尾');
  check('Markdown', '行内粗体与代码解析', spans.length === 5 &&
    spans[0].kind === 0 && spans[0].text === '这是' &&
    spans[1].kind === 1 && spans[1].text === '加粗' &&
    spans[3].kind === 2 && spans[3].text === '代码' &&
    spans[4].kind === 0 && spans[4].text === '结尾', spans.map(s => `${s.kind}:${s.text}`), 'text/bold/text/code/text');
}

{
  const spans = mdMod.parseInline('不闭合**加粗 和 \`代码');
  check('Markdown', '未闭合标记按原文', spans.length === 1 && spans[0].kind === 0 && spans[0].text === '不闭合**加粗 和 \`代码', spans.map(s => s.text), 'literal text');
}

{
  const empty = mdMod.parseInline('');
  check('Markdown', '空串返回一个空span', empty.length === 1 && empty[0].text === '', empty.length, 1);
}

// ---------- Part 4: image magic-byte MIME ----------
const metaMod = loadArkTs('features/aiagent/src/main/ets/utils/ImageMeta.ets');
check('图片MIME', 'PNG魔数', metaMod.detectImageMeta(new Uint8Array([0x89, 0x50, 0x4E, 0x47, 0, 0])).mime === 'image/png', metaMod.detectImageMeta(new Uint8Array([0x89, 0x50, 0x4E, 0x47, 0, 0])).mime, 'image/png');
check('图片MIME', 'JPEG魔数', metaMod.detectImageMeta(new Uint8Array([0xFF, 0xD8, 0xFF, 0xE0])).mime === 'image/jpeg', metaMod.detectImageMeta(new Uint8Array([0xFF, 0xD8, 0xFF, 0xE0])).mime, 'image/jpeg');
check('图片MIME', 'GIF87a魔数', metaMod.detectImageMeta(new Uint8Array([0x47, 0x49, 0x46, 0x38, 0x37, 0x61])).extension === 'gif', metaMod.detectImageMeta(new Uint8Array([0x47, 0x49, 0x46, 0x38, 0x37, 0x61])).extension, 'gif');
check('图片MIME', 'WEBP魔数', metaMod.detectImageMeta(new Uint8Array([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50])).mime === 'image/webp', metaMod.detectImageMeta(new Uint8Array([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50])).mime, 'image/webp');
check('图片MIME', '未知格式兜底jpeg', metaMod.detectImageMeta(new Uint8Array([1, 2, 3])).mime === 'image/jpeg', metaMod.detectImageMeta(new Uint8Array([1, 2, 3])).mime, 'image/jpeg');

// ---------- Part 5: static source checks ----------
const constantsSrc = fs.readFileSync(path.join(root, 'features/aiagent/src/main/ets/utils/AiConstants.ets'), 'utf8');
const aiServiceSrc = fs.readFileSync(path.join(root, 'features/aiagent/src/main/ets/service/AiService.ets'), 'utf8');
const photoSrc = fs.readFileSync(path.join(root, 'features/aiagent/src/main/ets/components/PhotoSearchView.ets'), 'utf8');
const chatBubbleSrc = fs.readFileSync(path.join(root, 'features/aiagent/src/main/ets/components/ChatBubble.ets'), 'utf8');

check('静态检查', '客户端源码无硬编码密钥', !/sk-[A-Za-z0-9]{10,}/.test(constantsSrc) && !/sk-[A-Za-z0-9]{10,}/.test(aiServiceSrc), 'no sk- key', 'no key in source');
check('静态检查', '图片后端使用HTTPS', /PHOTO_SEARCH_BACKEND_URL\s*=\s*['"]https:\/\//.test(photoSrc), 'https', 'HTTPS');
check('静态检查', '图片fd在closeImageFd关闭', /closeSync\(this\.imageFd\)/.test(photoSrc), 'closeSync', 'closeSync(this.imageFd)');
check('静态检查', '图片MIME按真实类型检测', photoSrc.indexOf('detectImageMeta') >= 0 && !/filename="image\.jpg"/.test(photoSrc), 'detectImageMeta', 'real MIME');
check('静态检查', 'ChatBubble使用MarkdownText渲染', /MarkdownText/.test(chatBubbleSrc), 'MarkdownText', 'MarkdownText');
check('静态检查', 'AiService有重试循环与流式构造', /MAX_RETRY_COUNT/.test(aiServiceSrc) && /for\s*\(/.test(aiServiceSrc) && /new AiApiRequest\([\s\S]*?messages,\s*true\s*,?\s*\)/.test(aiServiceSrc), 'retry + stream=true', 'retry loop + stream body');

function report() {
  fs.writeFileSync(path.join(__dirname, 'ai_agent_p4_test_result.json'), JSON.stringify(results, null, 2));
  console.log(`${results.length - failures}/${results.length} passed`);
  process.exit(failures > 0 ? 1 : 0);
}

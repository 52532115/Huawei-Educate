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
const aiPrelude = `
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
  successBody: '{"choices":[{"message":{"content":"你好"}}]}',
  RequestMethod: { POST: 'POST' },
  HttpDataType: { STRING: 'string' },
  createHttp() {
    const req = {
      destroyed: false,
      destroy() { this.destroyed = true; },
      async request(url, opts) {
        global.httpStub.attempts += 1;
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

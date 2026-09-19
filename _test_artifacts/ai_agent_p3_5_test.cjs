// Offline tests for P3.5: true streaming via requestInStream.
// Covers: tier-1 event streaming, split-SSE reassembly, watchdog fallback +
// device-memory flag, cancel mid-stream, non-200 error, empty stream.
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

// ---------- Fake http stack (must be reachable from the compiled module) ----------
const requests = [];
global.httpStub = {
  requests,
  nextResponseCode: 0,
  RequestMethod: { POST: 'POST' },
  HttpDataType: { STRING: 'string' },
  createHttp() {
    const req = {
      handlers: {},
      destroyed: false,
      responseCode: global.httpStub.nextResponseCode || 200,
      requestInStreamCalls: 0,
      requestCalls: 0,
      bufferedResult: '',
      on(evt, cb) { this.handlers[evt] = cb; },
      off(evt) { delete this.handlers[evt]; },
      destroy() { this.destroyed = true; },
      async requestInStream(url, opts) {
        this.requestInStreamCalls += 1;
        await Promise.resolve();
        return this.responseCode;
      },
      async request(url, opts) {
        this.requestCalls += 1;
        await Promise.resolve(); // let the test set bufferedResult before resolution
        return { responseCode: 200, result: this.bufferedResult };
      },
    };
    requests.push(req);
    return req;
  },
};

function toBuf(s) {
  const u8 = new TextEncoder().encode(s);
  const buf = new Uint8Array(u8.length);
  buf.set(u8);
  return buf.buffer;
}

global.__aiBackendModule = loadArkTs(
  'features/aiagent/src/main/ets/service/AiBackend.ets',
  `const fileIo = { readTextSync() { return ''; }, openSync() { return { fd: 1 }; }, writeSync() {}, closeSync() {} };`,
);

const aiPrelude = `
const AiBackend = global.__aiBackendModule.AiBackend;
const util = { TextDecoder: { create() { return { decodeToString(u8) { return Buffer.from(u8).toString('utf8'); } }; } } };
const Logger = { error() {}, info() {} };
const AiConstants = { AI_API_URL: 'https://api.test/v1/chat/completions', AI_MODEL: '', REQUEST_TIMEOUT: 1000, MAX_RETRY_COUNT: 3 };
const http = global.httpStub;
class ApiKeyStore {
  getKey() { return 'sk-test'; }
  isConfigured() { return true; }
}
class AiResponseResult { constructor() { this.content = ''; this.toolCalls = []; } }
class AiToolCall { constructor() { this.id = ''; this.type = 'function'; this.function = new AiToolCallFunction(); } }
class AiToolCallFunction { constructor() { this.name = ''; this.arguments = ''; } }
class AiApiRequest { constructor(model, messages, stream) { this.model = model; this.messages = messages; this.stream = stream; } }
class AiMessage { constructor() { this.role = ''; this.content = ''; } }
`;
const aiMod = loadArkTs(
  'features/aiagent/src/main/ets/service/AiService.ets',
  aiPrelude,
);

function makeMessages() {
  return [{ role: 'user', content: 'hi' }];
}

(async () => {
  // ---------- C1: tier-1 true streaming ----------
  requests.length = 0;
  aiMod.AiService.streamEventsBroken = false;
  const ai1 = new aiMod.AiService(200);
  let out1 = '';
  const p1 = ai1.chatStream(makeMessages(), (c) => { out1 += c; });
  await sleep(30);
  const req1 = requests[0];
  req1.handlers.dataReceive(toBuf(
    'data: {"choices":[{"delta":{"content":"你"}}]}\n\ndata: {"choices":[{"delta":{"content":"好"}}]}\n\ndata: [DONE]\n\n',
  ));
  req1.handlers.dataEnd();
  const chars1 = await p1;
  check('真流式', '使用requestInStream而非缓冲request', req1.requestInStreamCalls === 1 && req1.requestCalls === 0, { requestInStreamCalls: req1.requestInStreamCalls, requestCalls: req1.requestCalls }, 'requestInStream only');
  check('真流式', '事件驱动交付完整内容', out1 === '你好' && chars1 === 2, { out: out1, chars: chars1 }, '你好, 2 chars');

  // ---------- C2: SSE line split across two events ----------
  requests.length = 0;
  aiMod.AiService.streamEventsBroken = false;
  const ai2 = new aiMod.AiService(200);
  let out2 = '';
  const p2 = ai2.chatStream(makeMessages(), (c) => { out2 += c; });
  await sleep(30);
  const req2 = requests[0];
  req2.handlers.dataReceive(toBuf('data: {"choices":[{"delta":{"content":"前'));
  req2.handlers.dataReceive(toBuf('半"}}]}\n\ndata: [DONE]\n\n'));
  req2.handlers.dataEnd();
  const chars2 = await p2;
  check('真流式', '跨包行缓冲重组', out2 === '前半' && chars2 === 2, { out: out2, chars: chars2 }, '前半, 2 chars');

  // ---------- C3: watchdog -> device remembered -> buffered tier ----------
  requests.length = 0;
  aiMod.AiService.streamEventsBroken = false;
  const ai3 = new aiMod.AiService(80);
  let out3 = '';
  const p3 = ai3.chatStream(makeMessages(), (c) => { out3 += c; });
  const req3b = requests[0];
  const chars3 = await p3;
  check('看门狗', '无事件时触发看门狗并销毁请求', req3b.destroyed === true && aiMod.AiService.streamEventsBroken === true, { destroyed: req3b.destroyed, broken: aiMod.AiService.streamEventsBroken }, 'destroyed + broken flag');
  check('看门狗', '看门狗后返回0字符且不崩溃', chars3 === 0, chars3, 0);

  requests.length = 0;
  let out4 = '';
  const p4 = ai3.chatStream(makeMessages(), (c) => { out4 += c; });
  const req4 = requests[0];
  req4.bufferedResult = 'data: {"choices":[{"delta":{"content":"兜"}}]}\n\ndata: {"choices":[{"delta":{"content":"底"}}]}\n\ndata: [DONE]\n\n';
  const chars4 = await p4;
  check('看门狗', '后续请求跳过tier1直接走缓冲解析', req4.requestInStreamCalls === 0 && req4.requestCalls === 1, { requestInStreamCalls: req4.requestInStreamCalls, requestCalls: req4.requestCalls }, 'buffered only');
  check('看门狗', '缓冲解析交付完整内容', out4 === '兜底' && chars4 === 2, { out: out4, chars: chars4 }, '兜底, 2 chars');

  // ---------- C4: cancel mid-stream ----------
  requests.length = 0;
  aiMod.AiService.streamEventsBroken = false;
  const ai5 = new aiMod.AiService(5000);
  let out5 = '';
  const p5 = ai5.chatStream(makeMessages(), (c) => { out5 += c; });
  await sleep(30);
  const req5 = requests[0];
  req5.handlers.dataReceive(toBuf('data: {"choices":[{"delta":{"content":"你"}}]}\n\n'));
  await sleep(20);
  ai5.cancelRequest();
  const chars5 = await p5;
  check('取消', '取消后返回0且请求销毁', chars5 === 0 && req5.destroyed === true, { chars: chars5, destroyed: req5.destroyed }, '0 + destroyed');
  check('取消', '已到达的增量不丢失、取消后无新内容', out5 === '你', out5, '你');
  check('取消', '取消后不发兜底新请求', requests.length === 1, requests.length, 1);

  // ---------- C5: non-200 error ----------
  requests.length = 0;
  aiMod.AiService.streamEventsBroken = false;
  global.httpStub.nextResponseCode = 500;
  const ai6 = new aiMod.AiService(5000);
  let errMsg = '';
  let errCode = -1;
  const p6 = ai6.chatStream(makeMessages(), () => {}).catch((e) => { errMsg = e.message; errCode = e.code; });
  await p6;
  global.httpStub.nextResponseCode = 0;
  // The status now travels as a field instead of inside the text: the learner
  // gets a sentence they can act on, the log keeps the number. A bare
  // "failed with code 500" in front of a student was the actual defect.
  check('非200', '抛错带状态码且文案可读、不标记设备broken',
    errCode === 500 && errMsg.indexOf('code 500') < 0 && errMsg.indexOf('暂时不可用') >= 0 &&
    aiMod.AiService.streamEventsBroken === false,
    { errCode, errMsg, broken: aiMod.AiService.streamEventsBroken },
    'code=500, friendly text, not broken');

  // ---------- C6: empty stream (dataEnd, no data, no watchdog) ----------
  requests.length = 0;
  aiMod.AiService.streamEventsBroken = false;
  const ai7 = new aiMod.AiService(5000);
  const p7 = ai7.chatStream(makeMessages(), () => {});
  await sleep(20);
  requests[0].handlers.dataEnd();
  const chars7 = await p7;
  check('空流', 'dataEnd无数据→不标记broken', chars7 === 0 && aiMod.AiService.streamEventsBroken === false, { chars: chars7, broken: aiMod.AiService.streamEventsBroken }, '0, not broken');
  check('空流', '空流后仍走缓冲层', requests.length === 2 && requests[1].requestCalls === 1, { requests: requests.length, requestCalls: requests[1].requestCalls }, 'buffered tier ran');

  report();
})();

function report() {
  fs.writeFileSync(path.join(__dirname, 'ai_agent_p3_5_test_result.json'), JSON.stringify(results, null, 2));
  console.log(`${results.length - failures}/${results.length} passed`);
  process.exit(failures > 0 ? 1 : 0);
}

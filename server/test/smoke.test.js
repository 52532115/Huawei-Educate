/*
 * scripts/smoke.mjs 的单元测试。
 *
 * 为什么要给「一个自检脚本」写测试：它的输出会被当成「线上是好的」的依据。
 * 一个自己会误报通过的自检脚本，比没有自检更糟——它会让人放心地不去查。
 * 所以这里**每个失败分支都要被制造出来一次**，确认它真的会红。
 *
 * 桩服务用注入的 fetchImpl 实现（runSmoke 的第一个参数就允许注入），
 * 因此不需要真的起服务器，也不需要任何网络。
 */

import test from 'node:test';
import assert from 'node:assert/strict';

import {
  CHAT_PATH,
  EMBED_PATH,
  HEALTH_PATH,
  describeError,
  expectedBut,
  joinUrl,
  normalizeBase,
  parseArgs,
  redact,
  runSmoke,
  scanForHostLeak,
  scanForSecrets,
  summarize,
  tokenFingerprint,
} from '../scripts/smoke.mjs';
import { generateToken } from '../scripts/gen-token.mjs';
import { fingerprint } from '../scripts/lib/fingerprint.mjs';

const REAL_TOKEN = 'Zm9vYmFyLXRva2VuLXRoYXQtaXMtbG9uZy1lbm91Z2g';

// ---------------------------------------------------------------- 纯函数

test('normalizeBase 去掉尾部斜杠', () => {
  assert.equal(normalizeBase('https://a.example.com/'), 'https://a.example.com');
  assert.equal(normalizeBase('https://a.example.com///'), 'https://a.example.com');
  assert.equal(normalizeBase('  https://a.example.com  '), 'https://a.example.com');
  assert.equal(normalizeBase('https://a.example.com'), 'https://a.example.com');
});

test('normalizeBase 对空值与非字符串退化为空串', () => {
  assert.equal(normalizeBase(''), '');
  assert.equal(normalizeBase('   '), '');
  assert.equal(normalizeBase(undefined), '');
  assert.equal(normalizeBase(null), '');
});

test('joinUrl 不会拼出双斜杠', () => {
  assert.equal(joinUrl('https://a.example.com/', HEALTH_PATH), 'https://a.example.com/health');
  assert.equal(joinUrl('https://a.example.com', EMBED_PATH), 'https://a.example.com/embed');
});

test('redact 抹掉令牌与密钥特征', () => {
  const text = `token=${REAL_TOKEN} key=sk-abcdefghijklmnopqrstuvwx`;
  const out = redact(text, REAL_TOKEN);
  assert.ok(out.indexOf(REAL_TOKEN) < 0, '令牌必须被抹掉');
  assert.ok(out.indexOf('sk-abcdefghijklmnopqrstuvwx') < 0, '密钥必须被抹掉');
  assert.ok(out.indexOf('***') >= 0);
});

test('redact 对非字符串输入不抛异常', () => {
  assert.equal(redact(undefined, REAL_TOKEN), 'undefined');
  assert.equal(redact(null, REAL_TOKEN), 'null');
});

test('scanForSecrets 认得厂商密钥与 Bearer 凭据', () => {
  assert.equal(scanForSecrets('x sk-abcdefghijklmnopqrstuvwx y'), 'vendor key (sk-...)');
  assert.equal(scanForSecrets('Authorization: Bearer abcdefghijklmnopqrstuvwxyz0123'),
    'bearer credential');
});

test('scanForSecrets 对干净文本返回 null', () => {
  assert.equal(scanForSecrets('{"ok":true,"rateLimitPerMinute":120}'), null);
  assert.equal(scanForSecrets(''), null);
  assert.equal(scanForSecrets(undefined), null);
});

test('scanForSecrets 不把短串误判成密钥', () => {
  // sk- 后面不足 16 位的不是密钥，别把普通文本判成泄露。
  assert.equal(scanForSecrets('task-sk-short'), null);
});

test('scanForHostLeak 认得上游主机名', () => {
  assert.equal(scanForHostLeak('https://api.deepseek.com/v1'), 'api.deepseek.com');
  assert.equal(scanForHostLeak('dashscope.aliyuncs.com'), 'dashscope.aliyuncs.com');
  assert.equal(scanForHostLeak('{"ok":true,"chat":{"model":"deepseek-flash"}}'), null);
});

test('tokenFingerprint 只给长度与指纹，不含令牌本体', () => {
  const fp = tokenFingerprint(REAL_TOKEN);
  assert.ok(fp.indexOf(REAL_TOKEN) < 0, '指纹里不能出现令牌');
  assert.ok(fp.indexOf(`len=${REAL_TOKEN.length}`) >= 0);
  assert.equal(tokenFingerprint(''), '(none)');
});

test('同一令牌的指纹稳定，不同令牌的指纹不同', () => {
  assert.equal(tokenFingerprint(REAL_TOKEN), tokenFingerprint(REAL_TOKEN));
  assert.notEqual(tokenFingerprint(REAL_TOKEN), tokenFingerprint('another-token-value'));
});

test('指纹算法被锁死，两个脚本必须算出同一个值', () => {
  // 回归背景：check-upstream 与 smoke 曾各写一份算法，同一个 APP_TOKEN 在两边
  // 显示成 4605a041 与 fc1dc316，指纹反而成了「令牌被换了」的假证据。
  // 现在实现只有一份，这条用固定向量把算法钉住：换算法 = 历史指纹全部作废，
  // 必须是显式决定，不能顺带发生。
  assert.equal(fingerprint('abc'), 'ba7816bf', 'SHA-256("abc") 的前 8 位十六进制');
  assert.equal(tokenFingerprint('abc'), 'len=3 fp=ba7816bf');
  assert.equal(fingerprint(''), '-');
  assert.equal(fingerprint(undefined), '-');
});

test('generateToken 每次不同且可安全放进 URL/头部', () => {
  const a = generateToken();
  const b = generateToken();
  assert.notEqual(a, b);
  assert.equal(a.length, 43, '32 字节 base64url 无填充 = 43 字符');
  assert.match(a, /^[A-Za-z0-9_-]+$/, 'base64url 不应含 + / =');
});

// ---------------------------------------------------------------- 参数解析

/**
 * 在受控的环境变量视图里跑一段断言，跑完原样恢复（值为 undefined 表示删除）。
 *
 * 为什么需要它：`parseArgs` 会从 `process.env` 兜底，而 README 教的操作顺序是
 * `set -a && . ./.env && set +a && npm start` —— 照着做的人若在同一个 shell 里跑测试，
 * 真实的 APP_TOKEN 就漏进测试进程，把「默认值」用例弄红（实测三轮稳定复现）。
 * 测试必须自己掌控这层环境，而不是假设外面是干净的。
 */
function withEnv(vars, fn) {
  const saved = new Map();
  for (const [name, value] of Object.entries(vars)) {
    saved.set(name, process.env[name]);
    if (value === undefined) {
      delete process.env[name];
    } else {
      process.env[name] = value;
    }
  }
  try {
    return fn();
  } finally {
    for (const [name, value] of saved) {
      if (value === undefined) {
        delete process.env[name];
      } else {
        process.env[name] = value;
      }
    }
  }
}

test('parseArgs 默认值', () => {
  // 显式清空，否则外面 source 过 .env 时这里会读到真实令牌。
  withEnv({ SMOKE_BASE_URL: undefined, APP_TOKEN: undefined }, () => {
    const options = parseArgs([]);
    assert.equal(options.base, '');
    assert.equal(options.token, '');
    assert.equal(options.runChat, true);
    assert.equal(options.runEmbed, true);
    assert.equal(options.json, false);
    assert.equal(options.help, false);
  });
});

test('parseArgs 读取 --base 与 --token', () => {
  const options = parseArgs(['--base', 'https://api.example.com/', '--token', 'abc']);
  assert.equal(options.base, 'https://api.example.com', '应顺手规范化');
  assert.equal(options.token, 'abc');
});

test('parseArgs 支持短选项', () => {
  const options = parseArgs(['-b', 'https://x.example.com', '-t', 'abc']);
  assert.equal(options.base, 'https://x.example.com');
  assert.equal(options.token, 'abc');
});

test('parseArgs 的 --no-chat / --no-embed 关掉对应检查', () => {
  const options = parseArgs(['--no-chat', '--no-embed']);
  assert.equal(options.runChat, false);
  assert.equal(options.runEmbed, false);
});

test('parseArgs 的 --timeout 以秒计并转成毫秒', () => {
  assert.equal(parseArgs(['--timeout', '5']).timeoutMs, 5000);
});

test('parseArgs 忽略非法的 --timeout', () => {
  assert.equal(parseArgs(['--timeout', '0']).timeoutMs, 30000);
  assert.equal(parseArgs(['--timeout', 'abc']).timeoutMs, 30000);
  assert.equal(parseArgs(['--timeout']).timeoutMs, 30000);
});

test('parseArgs 从环境变量兜底', () => {
  withEnv({ SMOKE_BASE_URL: 'https://env.example.com/', APP_TOKEN: 'env-token' }, () => {
    const options = parseArgs([]);
    assert.equal(options.base, 'https://env.example.com');
    assert.equal(options.token, 'env-token');
  });
});

test('summarize 按状态计数', () => {
  const counts = summarize([
    { status: 'PASS' }, { status: 'PASS' }, { status: 'FAIL' },
    { status: 'WARN' }, { status: 'SKIP' },
  ]);
  assert.deepEqual(counts, { PASS: 2, FAIL: 1, WARN: 1, SKIP: 1 });
});

// ---------------------------------------------------------------- 报错可读性

test('describeError 能从 cause 里挖出真正的连接错误码', () => {
  // fetch 的连接失败抛的是 TypeError，真正的原因挂在 cause 上。
  // 只打印 error.name 会得到「TypeError」——等于没说。
  const refused = new TypeError('fetch failed');
  refused.cause = { code: 'ECONNREFUSED' };
  assert.equal(describeError(refused), 'ECONNREFUSED');

  const dns = new TypeError('fetch failed');
  dns.cause = { code: 'ENOTFOUND' };
  assert.equal(describeError(dns), 'ENOTFOUND');
});

test('describeError 认得顶层错误码与超时', () => {
  const direct = new Error('boom');
  direct.code = 'EAI_AGAIN';
  assert.equal(describeError(direct), 'EAI_AGAIN');

  const timeout = new Error('The operation was aborted due to timeout');
  timeout.name = 'TimeoutError';
  assert.ok(describeError(timeout).indexOf('超时') >= 0);
});

test('describeError 对空值不抛异常', () => {
  assert.equal(describeError(null), 'unknown');
  assert.equal(describeError(undefined), 'unknown');
  assert.equal(describeError(new Error('没有码也没有 cause')), 'Error');
});

test('describeError 退化到 cause 的消息', () => {
  const wrapped = new Error('fetch failed');
  wrapped.cause = new Error('socket hang up');
  assert.equal(describeError(wrapped), 'socket hang up');
});

test('expectedBut 对 401 直说是令牌问题而不是「期望 405」', () => {
  const text = expectedBut(401, 405, 'GET /embed');
  assert.ok(text.indexOf('401') >= 0);
  assert.ok(text.indexOf('令牌被拒') >= 0, text);
  assert.ok(text.indexOf('期望 405') < 0, '401 时不该把人往路由方向带');
});

test('expectedBut 其他状态码照实报期望值', () => {
  assert.equal(expectedBut(500, 405, 'GET /embed'), 'GET /embed → 500，期望 405');
  assert.equal(expectedBut(200, 404, 'POST /x'), 'POST /x → 200，期望 404');
});

// ---------------------------------------------------------------- 桩部署

function json(status, payload) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

/**
 * 一个符合真实契约的桩后端。每个开关对应一种「线上可能真的长这样」的坏法，
 * 让自检脚本的每条失败分支都能被真实触发一次。
 */
function stubDeployment(overrides = {}) {
  const state = {
    token: overrides.token || REAL_TOKEN,
    authRequired: overrides.authRequired !== false,
    chatConfigured: overrides.chatConfigured !== false,
    embeddingConfigured: overrides.embeddingConfigured !== false,
    dimension: overrides.dimension === undefined ? 3 : overrides.dimension,
    vectorWidth: overrides.vectorWidth,
    vectorCount: overrides.vectorCount,
    unknownRouteStatus: overrides.unknownRouteStatus || 404,
    getEmbedStatus: overrides.getEmbedStatus || 405,
    // 坏法：错令牌也放行
    acceptAnyToken: overrides.acceptAnyToken === true,
    // 坏法：响应体里回显了密钥
    leakSecret: overrides.leakSecret === true,
    // 坏法：/health 里泄露了上游主机
    leakHost: overrides.leakHost === true,
    // 坏法：流式一个 data 分片都没有
    streamDataLines: overrides.streamDataLines === undefined ? 3 : overrides.streamDataLines,
    // 坏法：聊天 200 但内容为空
    emptyChatContent: overrides.emptyChatContent === true,
    chatStatus: overrides.chatStatus,
    embedStatus: overrides.embedStatus,
  };

  const fetchImpl = async (url, init = {}) => {
    const path = new URL(url).pathname;
    const method = init.method || 'POST';
    const headers = init.headers || {};
    const raw = headers.Authorization || headers.authorization || '';
    const presented = raw.startsWith('Bearer ') ? raw.substring(7) : '';
    const authorized = state.acceptAnyToken || presented === state.token;

    const healthPayload = {
      ok: true,
      authRequired: state.authRequired,
      chat: { configured: state.chatConfigured, model: 'deepseek-flash' },
      embedding: {
        configured: state.embeddingConfigured,
        model: 'text-embedding-v3',
        dimension: state.dimension,
        batchSize: 10,
      },
      rateLimitPerMinute: 120,
    };
    if (state.leakHost) {
      healthPayload.upstream = 'https://api.deepseek.com/v1';
    }
    if (state.leakSecret) {
      healthPayload.debug = 'sk-abcdefghijklmnopqrstuvwx';
    }

    if (path === HEALTH_PATH) {
      if (method !== 'GET') {
        return json(405, { error: { code: 'method_not_allowed' } });
      }
      return json(200, healthPayload);
    }

    if (state.authRequired && !authorized) {
      const payload = { error: { code: 'unauthorized', message: '应用令牌无效或缺失' } };
      if (state.leakSecret) {
        payload.error.leaked = 'sk-abcdefghijklmnopqrstuvwx';
      }
      return json(401, payload);
    }

    if (method !== 'POST') {
      if (path === EMBED_PATH) {
        return json(state.getEmbedStatus, { error: { code: 'method_not_allowed' } });
      }
      return json(405, { error: { code: 'method_not_allowed' } });
    }

    if (path === EMBED_PATH) {
      if (state.embedStatus && state.embedStatus !== 200) {
        return json(state.embedStatus, { error: { code: 'upstream_error' } });
      }
      const count = state.vectorCount === undefined ? 2 : state.vectorCount;
      const width = state.vectorWidth === undefined ? (state.dimension || 3) : state.vectorWidth;
      const vectors = [];
      for (let i = 0; i < count; i++) {
        const row = [];
        for (let j = 0; j < width; j++) {
          row.push(0.1 * (i + 1) + j);
        }
        vectors.push(row);
      }
      return json(200, { model: 'text-embedding-v3', dimension: width, vectors });
    }

    if (path === CHAT_PATH) {
      if (state.chatStatus && state.chatStatus !== 200) {
        return json(state.chatStatus, { error: { code: 'upstream_error' } });
      }
      let stream = false;
      try {
        stream = JSON.parse(init.body || '{}').stream === true;
      } catch (e) {
        stream = false;
      }
      if (!stream) {
        const content = state.emptyChatContent ? '' : '收到';
        return json(200, {
          id: 'chatcmpl-stub',
          choices: [{ index: 0, message: { role: 'assistant', content } }],
        });
      }
      let text = '';
      for (let i = 0; i < state.streamDataLines; i++) {
        text += `data: ${JSON.stringify({ choices: [{ delta: { content: 'x' } }] })}\n\n`;
      }
      text += 'data: [DONE]\n\n';
      return new Response(text, {
        status: 200,
        headers: { 'content-type': 'text/event-stream' },
      });
    }

    return json(state.unknownRouteStatus,
      state.unknownRouteStatus === 404
        ? { error: { code: 'not_found' } }
        : { error: { code: 'unexpected' } });
  };

  return { fetchImpl, state };
}

const BASE = 'https://api.example.com';

function baseOptions(extra = {}) {
  return Object.assign({
    base: BASE,
    token: REAL_TOKEN,
    runChat: true,
    runEmbed: true,
    timeoutMs: 5000,
  }, extra);
}

function statusOf(report, name) {
  const found = report.results.find((r) => r.name === name);
  return found ? found.status : '(missing)';
}

function detailOf(report, name) {
  const found = report.results.find((r) => r.name === name);
  return found ? found.detail : '';
}

// ---------------------------------------------------------------- runSmoke 正例

test('全部正常时没有任何 FAIL', async () => {
  const { fetchImpl } = stubDeployment();
  const report = await runSmoke(baseOptions(), fetchImpl);
  const counts = summarize(report.results);
  assert.equal(counts.FAIL, 0, JSON.stringify(report.results));
  assert.equal(counts.WARN, 0, '正常部署不该有警告');
  assert.equal(counts.SKIP, 0, '一切可查，不该有跳过');
  assert.equal(report.authRequired, true);
});

test('正常路径逐项都是 PASS', async () => {
  const { fetchImpl } = stubDeployment();
  const report = await runSmoke(baseOptions(), fetchImpl);
  for (const name of ['健康检查', '匿名访问被拒', '错误令牌被拒', '方法校验', '未知路由',
    '嵌入返回一致', '聊天非流式', '聊天流式', '响应体无密钥', '响应体无上游地址']) {
    assert.equal(statusOf(report, name), 'PASS', `${name} 应为 PASS`);
  }
});

test('嵌入检查认出向量条数与宽度', async () => {
  const { fetchImpl } = stubDeployment({ dimension: 8 });
  const report = await runSmoke(baseOptions(), fetchImpl);
  assert.equal(statusOf(report, '嵌入返回一致'), 'PASS');
  assert.ok(detailOf(report, '嵌入返回一致').indexOf('宽度 8') >= 0,
    detailOf(report, '嵌入返回一致'));
});

test('报告里绝不出现令牌本体', async () => {
  const { fetchImpl } = stubDeployment();
  const report = await runSmoke(baseOptions(), fetchImpl);
  const serialized = JSON.stringify(report.results);
  assert.ok(serialized.indexOf(REAL_TOKEN) < 0, '结果里不能带令牌');
});

// ---------------------------------------------------------------- runSmoke 反例

test('鉴权被关闭时报 WARN 而不是 PASS', async () => {
  const { fetchImpl } = stubDeployment({ authRequired: false });
  const report = await runSmoke(baseOptions(), fetchImpl);
  assert.equal(statusOf(report, '匿名访问被拒'), 'WARN');
  assert.equal(statusOf(report, '错误令牌被拒'), 'SKIP');
  assert.ok(detailOf(report, '匿名访问被拒').indexOf('危险的') >= 0);
});

test('鉴权关闭时即使没有令牌也照跑功能检查', async () => {
  // 这是最容易漏的一条：鉴权关掉之后根本不需要令牌，
  // 若因为「没令牌」就把所有功能检查跳过，「没配鉴权 + 聊天坏掉」会报成全绿。
  const { fetchImpl } = stubDeployment({ authRequired: false, chatStatus: 503 });
  const report = await runSmoke(baseOptions({ token: '' }), fetchImpl);
  assert.equal(statusOf(report, '聊天非流式'), 'FAIL',
    '鉴权关闭时聊天坏掉必须报 FAIL，不能被跳过');
  assert.equal(statusOf(report, '聊天流式'), 'FAIL');
  assert.equal(statusOf(report, '方法校验'), 'PASS');
  assert.equal(statusOf(report, '未知路由'), 'PASS');
});

test('鉴权关闭且功能正常时全绿', async () => {
  const { fetchImpl } = stubDeployment({ authRequired: false });
  const report = await runSmoke(baseOptions({ token: '' }), fetchImpl);
  const counts = summarize(report.results);
  assert.equal(counts.FAIL, 0, JSON.stringify(report.results));
  assert.equal(counts.WARN, 1, '只应有一条「鉴权已关闭」的警告');
  assert.equal(statusOf(report, '聊天非流式'), 'PASS');
  assert.equal(statusOf(report, '嵌入返回一致'), 'PASS');
});

test('错令牌也被放行时判 FAIL', async () => {
  const { fetchImpl } = stubDeployment({ acceptAnyToken: true });
  const report = await runSmoke(baseOptions(), fetchImpl);
  assert.equal(statusOf(report, '错误令牌被拒'), 'FAIL');
  assert.equal(summarize(report.results).FAIL > 0, true);
});

test('令牌不对时，路由检查的失败文案指向令牌而不是路由', async () => {
  const { fetchImpl } = stubDeployment();
  const report = await runSmoke(baseOptions({ token: 'a-wrong-token' }), fetchImpl);
  assert.equal(statusOf(report, '方法校验'), 'FAIL');
  const detail = detailOf(report, '方法校验');
  assert.ok(detail.indexOf('令牌被拒') >= 0, detail);
  assert.ok(detail.indexOf('期望 405') < 0, '不该把人往路由方向带');
});

test('响应体回显密钥时判 FAIL', async () => {
  const { fetchImpl } = stubDeployment({ leakSecret: true });
  const report = await runSmoke(baseOptions(), fetchImpl);
  assert.equal(statusOf(report, '响应体无密钥'), 'FAIL');
  assert.ok(detailOf(report, '响应体无密钥').indexOf('vendor key') >= 0);
});

test('/health 泄露上游主机名时判 FAIL', async () => {
  const { fetchImpl } = stubDeployment({ leakHost: true });
  const report = await runSmoke(baseOptions(), fetchImpl);
  assert.equal(statusOf(report, '响应体无上游地址'), 'FAIL');
  assert.ok(detailOf(report, '响应体无上游地址').indexOf('api.deepseek.com') >= 0);
});

test('向量条数不匹配时判 FAIL', async () => {
  const { fetchImpl } = stubDeployment({ vectorCount: 1 });
  const report = await runSmoke(baseOptions(), fetchImpl);
  assert.equal(statusOf(report, '嵌入返回一致'), 'FAIL');
  assert.ok(detailOf(report, '嵌入返回一致').indexOf('期望 2 条') >= 0);
});

test('向量宽度与 /health 声明不符时判 FAIL', async () => {
  const { fetchImpl } = stubDeployment({ dimension: 3, vectorWidth: 5 });
  const report = await runSmoke(baseOptions(), fetchImpl);
  assert.equal(statusOf(report, '嵌入返回一致'), 'FAIL');
  assert.ok(detailOf(report, '嵌入返回一致').indexOf('声明 3') >= 0);
});

test('聊天 200 但内容为空时判 FAIL', async () => {
  const { fetchImpl } = stubDeployment({ emptyChatContent: true });
  const report = await runSmoke(baseOptions(), fetchImpl);
  assert.equal(statusOf(report, '聊天非流式'), 'FAIL');
});

test('聊天非 200 时判 FAIL', async () => {
  const { fetchImpl } = stubDeployment({ chatStatus: 503 });
  const report = await runSmoke(baseOptions(), fetchImpl);
  assert.equal(statusOf(report, '聊天非流式'), 'FAIL');
  assert.equal(statusOf(report, '聊天流式'), 'FAIL');
});

test('流式没有任何内容分片时判 FAIL（终结符不算内容）', async () => {
  const { fetchImpl } = stubDeployment({ streamDataLines: 0 });
  const report = await runSmoke(baseOptions(), fetchImpl);
  assert.equal(statusOf(report, '聊天流式'), 'FAIL',
    '只有 data: [DONE] 而没有内容，必须判失败——空转的流不是能用的流');
  assert.ok(detailOf(report, '聊天流式').indexOf('没有任何内容分片') >= 0,
    detailOf(report, '聊天流式'));
});

test('流式有内容分片时判 PASS 并给出分片数与耗时', async () => {
  const { fetchImpl } = stubDeployment({ streamDataLines: 4 });
  const report = await runSmoke(baseOptions(), fetchImpl);
  assert.equal(statusOf(report, '聊天流式'), 'PASS');
  const detail = detailOf(report, '聊天流式');
  assert.ok(detail.indexOf('SSE 4 片') >= 0, detail);
  assert.ok(detail.indexOf('首字节') >= 0, detail);
});

test('未知路由不是 404 时判 FAIL', async () => {
  const { fetchImpl } = stubDeployment({ unknownRouteStatus: 200 });
  const report = await runSmoke(baseOptions(), fetchImpl);
  assert.equal(statusOf(report, '未知路由'), 'FAIL');
});

test('GET /embed 不是 405 时判 FAIL', async () => {
  const { fetchImpl } = stubDeployment({ getEmbedStatus: 200 });
  const report = await runSmoke(baseOptions(), fetchImpl);
  assert.equal(statusOf(report, '方法校验'), 'FAIL');
});

test('聊天未配置时报 WARN 并跳过聊天检查', async () => {
  const { fetchImpl } = stubDeployment({ chatConfigured: false });
  const report = await runSmoke(baseOptions(), fetchImpl);
  assert.equal(statusOf(report, '聊天已配置'), 'WARN');
  assert.equal(statusOf(report, '聊天非流式'), 'SKIP');
  assert.equal(statusOf(report, '聊天流式'), 'SKIP');
  assert.equal(summarize(report.results).FAIL, 0, '未配置不是错误');
});

test('嵌入未配置时报 WARN 并跳过嵌入检查', async () => {
  const { fetchImpl } = stubDeployment({ embeddingConfigured: false });
  const report = await runSmoke(baseOptions(), fetchImpl);
  assert.equal(statusOf(report, '嵌入已配置'), 'WARN');
  assert.equal(statusOf(report, '嵌入返回一致'), 'SKIP');
});

test('--no-chat / --no-embed 会跳过对应检查且不产生 FAIL', async () => {
  const { fetchImpl } = stubDeployment();
  const report = await runSmoke(baseOptions({ runChat: false, runEmbed: false }), fetchImpl);
  assert.equal(statusOf(report, '聊天非流式'), 'SKIP');
  assert.equal(statusOf(report, '嵌入返回一致'), 'SKIP');
  assert.equal(summarize(report.results).FAIL, 0);
});

test('没有令牌时只验鉴权，其余跳过', async () => {
  const { fetchImpl } = stubDeployment();
  const report = await runSmoke(baseOptions({ token: '' }), fetchImpl);
  assert.equal(statusOf(report, '匿名访问被拒'), 'PASS', '无需令牌也能验这一条');
  assert.equal(statusOf(report, '错误令牌被拒'), 'PASS');
  assert.equal(statusOf(report, '嵌入返回一致'), 'SKIP');
  assert.equal(statusOf(report, '聊天非流式'), 'SKIP');
  assert.equal(summarize(report.results).FAIL, 0);
});

test('后端不可达时立即给出连通性 FAIL 并停止后续检查', async () => {
  const refusing = async () => {
    const error = new Error('connect ECONNREFUSED');
    error.code = 'ECONNREFUSED';
    throw error;
  };
  const report = await runSmoke(baseOptions(), refusing);
  assert.equal(report.results.length, 2, '连不上就没有必要再往下问');
  assert.equal(statusOf(report, '连通性'), 'FAIL');
  assert.equal(statusOf(report, '健康检查'), 'SKIP');
  assert.ok(detailOf(report, '连通性').indexOf('ECONNREFUSED') >= 0);
  assert.equal(report.authRequired, null);
});

test('超时的报错文案是可读的', async () => {
  const timingOut = async () => {
    const error = new Error('The operation was aborted due to timeout');
    error.name = 'TimeoutError';
    throw error;
  };
  const report = await runSmoke(baseOptions(), timingOut);
  assert.equal(statusOf(report, '连通性'), 'FAIL');
  assert.ok(detailOf(report, '连通性').indexOf('超时') >= 0);
});

test('base 带尾斜杠时也不会拼出双斜杠', async () => {
  const seen = [];
  const { fetchImpl } = stubDeployment();
  const recording = async (url, init) => {
    seen.push(String(url));
    return fetchImpl(url, init);
  };
  await runSmoke(baseOptions({ base: 'https://api.example.com/' }), recording);
  assert.ok(seen.length > 0);
  for (const url of seen) {
    assert.ok(url.indexOf('example.com//') < 0, `双斜杠：${url}`);
  }
});

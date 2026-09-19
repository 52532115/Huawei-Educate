#!/usr/bin/env node
/*
 * 部署前的凭据体检。
 *
 * `smoke.mjs` 体检的是「已经起好的服务」——它打 /health、验 app token，但它默认
 * 上游是可用的。而上游凭据恰恰是最容易填错的一环，错了之后的表现是后台日志里一串
 * 401、用户只看到「AI 没反应」。这个脚本把那一环单独拎出来，在部署前跑：
 *
 *   1. 静态核对：键名有没有写错、有没有漏填、值看起来像不像该家的格式；
 *   2. 在线探测：两把厂商密钥各打一次真实请求，顺带确认模型名在上游真的存在。
 *
 * 之所以要真打一次，是因为「填了」和「能用」之间隔着三种失败：密钥被复制少了尾巴、
 * 密钥是另一个产品的、模型名打错了。这三种在本地静态检查里都看不出来，只会在
 * 用户第一次提问时才暴露。
 *
 * 用法：
 *   node scripts/check-upstream.mjs                    # 读 ./.env，然后在线探测
 *   node scripts/check-upstream.mjs --offline          # 只做静态核对，不发任何请求
 *   node scripts/check-upstream.mjs --no-chat-ping     # 在线探测，但不真发对话
 *   node scripts/check-upstream.mjs --env-file /etc/safeta-ai-backend.env
 *
 * 在线探测会真发三类请求：两个 `GET /models`，一次嵌入，以及一条 `max_tokens=64`
 * 的对话（除非 `--no-chat-ping`）。最后一条同时验两件只有真调用才知道的事：
 * 余额够不够（402），以及模型的思考有没有被真的关掉 —— 后者要读 `usage` 里的
 * 推理 token 才算数。成本可以忽略；`--offline` 则一个请求都不发。
 *
 * 密钥永远只以掩码 + 指纹出现，这里的输出可以直接贴进聊天窗口。
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { loadConfig } from '../src/config.js';
// 指纹实现只有一份（lib/fingerprint.mjs），否则同一个令牌在两个脚本里会算出两个值。
import { fingerprint } from './lib/fingerprint.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const SERVER_DIR = path.resolve(HERE, '..');

const PROBE_TIMEOUT_MS = 20000;

/** 与脚本自己有关的、不该被当成上游配置的键。 */
const NON_UPSTREAM_KEYS = ['API_DOMAIN', 'ACME_EMAIL'];

// ---------------------------------------------------------------------------
// 输出
// ---------------------------------------------------------------------------

const results = [];

function record(level, title, detail = '') {
  results.push({ level, title, detail });
  const tag = level === 'ok' ? '[ok]  ' : level === 'warn' ? '[warn]' : level === 'fail' ? '[fail]' : '[--]  ';
  console.log(`${tag} ${title}${detail.length > 0 ? `\n        ${detail}` : ''}`);
}

const ok = (t, d) => record('ok', t, d);
const warn = (t, d) => record('warn', t, d);
const fail = (t, d) => record('fail', t, d);
const info = (t, d) => record('info', t, d);

// ---------------------------------------------------------------------------
// .env 解析
// ---------------------------------------------------------------------------

/**
 * 解析一个 KEY=VALUE 文件。
 *
 * 只实现这份项目真正用到的语法（# 注释、可选引号），不引入 dotenv —— 这个脚本和
 * 整个 server 一样零依赖。行尾的 `# 注释` 不处理：.env.example 里没有这种写法，
 * 而半吊子地实现它会悄悄截断一个含 `#` 的合法密钥。
 */
export function parseEnvFile(text) {
  const out = {};
  for (const line of text.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (trimmed.length === 0 || trimmed.charAt(0) === '#') {
      continue;
    }
    const eq = trimmed.indexOf('=');
    if (eq < 0) {
      continue;
    }
    const key = trimmed.substring(0, eq).trim();
    let value = trimmed.substring(eq + 1).trim();
    const first = value.charAt(0);
    if (value.length >= 2 && (first === '"' || first === "'") && value.charAt(value.length - 1) === first) {
      value = value.substring(1, value.length - 1);
    }
    out[key] = value;
  }
  return out;
}

function readEnvFile(file) {
  try {
    return { text: fs.readFileSync(file, 'utf8'), error: '' };
  } catch (error) {
    return { text: '', error: error && error.code ? error.code : String(error) };
  }
}

// ---------------------------------------------------------------------------
// 掩码
// ---------------------------------------------------------------------------

/** 只给肉眼看的形状：头尾几个字符 + 长度。中段永远不出现。 */
function mask(value) {
  if (value.length === 0) {
    return '(空)';
  }
  if (value.length <= 12) {
    return `${value.charAt(0)}${'*'.repeat(value.length - 2)}${value.charAt(value.length - 1)} (len=${value.length})`;
  }
  return `${value.substring(0, 6)}…${value.substring(value.length - 4)} (len=${value.length})`;
}

// ---------------------------------------------------------------------------
// 静态核查
// ---------------------------------------------------------------------------

/**
 * 各家凭据的常见形状。
 *
 * 这张表只用来把「你填的到底是哪家的东西」说清楚，**绝不用作通过与否的判据**：
 * 厂商会改格式，形状表永远滞后。真实的例子就摆在眼前——百炼现在也发 `sk-ws-`
 * 前缀的长密钥（116 字符，中段夹着 base64 编码的签名，一眼像别的产品），凭形状
 * 会被误判；它实际完全可用。所以形状不认识时只提示，结论一律交给在线探测。
 */
const KEY_SHAPES = [
  {
    name: 'DashScope / 百炼（经典）',
    test: (v) => /^sk-[0-9a-zA-Z]{32}$/.test(v),
    note: 'sk- 后跟 32 位字母数字',
  },
  {
    name: 'DashScope / 百炼（新版）',
    test: (v) => /^sk-ws-[0-9A-Za-z._-]{40,}$/.test(v),
    note: 'sk-ws- 前缀的长密钥',
  },
  {
    name: 'DeepSeek',
    test: (v) => /^sk-[0-9a-f]{32}$/.test(v),
    note: 'sk- 后跟 32 位小写十六进制',
  },
];

function describeKeyShape(label, value) {
  if (value.length === 0) {
    warn(`${label} 未填写`);
    return;
  }
  const matched = KEY_SHAPES.filter((shape) => shape.test(value));
  if (matched.length > 0) {
    ok(`${label} 形状正常（像 ${matched.map((m) => m.name).join(' / ')}）`, mask(value));
    return;
  }
  // 形状不认识不等于不能用（智谱、硅基流动、火山各有各的样子，百炼自己就换过
  // 一次）。所以这里只报 info：判定权在线探测那里，形状表的职责仅仅是解释
  // 「你这串东西看起来出自哪一家」。
  info(
    `${label} 形状不在已知列表里（不代表不能用）`,
    `${mask(value)}\n        已知形状：${KEY_SHAPES.map((s) => `${s.name} = ${s.note}`).join('；')}\n        以在线探测的结果为准。`,
  );
}

/*
 * 这里曾经有一条"含 `MEUCIQ` 就是 base64 签名、多半是复制错了"的启发式规则，
 * 已删除。删除的理由值得留在这里：百炼新版密钥的合法内容里就带这一段，规则对
 * 一把完全可用的密钥报了红。凭"看起来可疑"去否决现场事实，比不检查更糟——
 * 它会让人去换掉好密钥，也会让真正的红失去分量。
 */

function looksLikeUrl(value) {
  return /^https?:\/\//i.test(value);
}

// ---------------------------------------------------------------------------
// 在线探测
// ---------------------------------------------------------------------------

async function fetchWithTimeout(url, options) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), PROBE_TIMEOUT_MS);
  try {
    return await fetch(url, { ...options, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

/** 把上游的错误体压成一行，用于诊断。上游回的错误里不含我们的密钥。 */
function excerpt(text, limit = 240) {
  const flat = String(text || '').replace(/\s+/g, ' ').trim();
  return flat.length > limit ? `${flat.substring(0, limit)}…` : flat;
}

/**
 * 聊天侧探测：GET /models。
 *
 * 选它而不是发一条真消息，是因为它同时回答两个问题（密钥有效吗、模型名存在吗）
 * 且不产生费用、不消耗额度。DeepSeek 与 DashScope 兼容模式都实现了这个端点。
 */
async function probeChatModels(config) {
  const url = `${config.chatBaseUrl}/models`;
  let response;
  try {
    response = await fetchWithTimeout(url, {
      method: 'GET',
      headers: { Authorization: `Bearer ${config.chatApiKey}` },
    });
  } catch (error) {
    const detail = error && error.name === 'AbortError' ? `超过 ${PROBE_TIMEOUT_MS} ms 未响应` : String(error && error.message);
    fail('聊天上游连不上', `${url}\n        ${detail}`);
    return null;
  }

  const text = await response.text();
  if (response.status === 401 || response.status === 403) {
    fail('聊天上游拒绝了这把密钥', `HTTP ${response.status}　${excerpt(text)}`);
    return null;
  }
  if (response.status < 200 || response.status >= 300) {
    warn(`聊天上游 /models 返回 HTTP ${response.status}`, `${url}\n        ${excerpt(text)}`);
    return null;
  }

  let json = null;
  try {
    json = JSON.parse(text);
  } catch (e) {
    json = null;
  }
  const ids = [];
  if (json && Array.isArray(json.data)) {
    for (const item of json.data) {
      if (item && typeof item.id === 'string') {
        ids.push(item.id);
      }
    }
  }

  ok('聊天上游密钥有效', `HTTP 200　${mask(config.chatApiKey)}　指纹 ${fingerprint(config.chatApiKey)}`);

  if (ids.length === 0) {
    warn('聊天上游 /models 没有返回模型列表，无法核对模型名', '跳过模型名检查。');
    return ids;
  }

  if (ids.indexOf(config.chatModel) >= 0) {
    ok(`模型名 "${config.chatModel}" 在上游存在`);
  } else {
    fail(
      `模型名 "${config.chatModel}" 不在上游的模型列表里`,
      `可用：${ids.join('、')}\n        改 CHAT_MODEL 为其中之一，否则每次对话都会 404/400。`,
    );
  }
  return ids;
}

/**
 * 聊天侧探测之二：真发一条最短的消息。
 *
 * 光有 `/models` 证明不了「能用」。它连着漏掉两个真实故障：账户余额为 0（密钥
 * 和模型名全对，一问就 402），以及**模型默认开思考**（同样全对，但每次回答都在
 * 按输出价烧一长串用户看不见、App 也不显示的推理）。
 *
 * 前者要真发一次才知道；后者要读 `usage` 才知道 —— 只看正文是看不出来的，因为
 * 开着思考最终也能给出正确正文，只是贵几十倍、慢几秒。所以这里既发请求，也解析
 * `completion_tokens_details.reasoning_tokens`，那是唯一能证明「开关真的生效了」
 * 的证据。
 *
 * 请求体与线上一致（含服务端注入的两种思考写法），顺带验证这家不会因为不认识
 * 其中一种就拒收 —— 实测两家都是静默忽略。
 */
async function probeChatCompletion(config) {
  const url = `${config.chatBaseUrl}/chat/completions`;
  const body = {
    model: config.chatModel,
    messages: [{ role: 'user', content: 'ping' }],
    // 64 而不是 8。8 个 token 会被一段很短的思考直接吃光，于是探测**自己**
    // 制造出「正文为空」，把上游的问题和探测方法的毛病搅在一起 —— 实测踩过。
    max_tokens: 64,
    stream: false,
  };
  const thinkingFields = config.chatThinkingFields ? config.chatThinkingFields() : {};
  for (const field of Object.keys(thinkingFields)) {
    body[field] = thinkingFields[field];
  }

  let response;
  try {
    response = await fetchWithTimeout(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${config.chatApiKey}`,
      },
      body: JSON.stringify(body),
    });
  } catch (error) {
    const detail = error && error.name === 'AbortError' ? `超过 ${PROBE_TIMEOUT_MS} ms 未响应` : String(error && error.message);
    fail('聊天上游连不上', `${url}\n        ${detail}`);
    return;
  }

  const text = await response.text();
  if (response.status === 402) {
    fail(
      '聊天上游说账户余额不足，密钥本身没问题',
      `HTTP 402　${excerpt(text)}\n        密钥有效、模型名也对，但账户里没有可用额度：对话一定会失败。\n        充值，或者把 CHAT_* 整组换到另一家上游。`,
    );
    return;
  }
  if (response.status === 401 || response.status === 403) {
    fail('聊天上游拒绝了这把密钥', `HTTP ${response.status}　${excerpt(text)}`);
    return;
  }
  if (response.status === 429) {
    warn('聊天上游限流（HTTP 429）', `密钥与余额大概率正常，只是此刻太频繁。${excerpt(text, 120)}`);
    return;
  }
  if (response.status < 200 || response.status >= 300) {
    fail(
      '聊天上游拒绝了请求',
      `HTTP ${response.status}　${excerpt(text)}\n        若为 400，重点看模型名，以及服务端注入的思考字段是否被这家接受。`,
    );
    return;
  }

  let json = null;
  try {
    json = JSON.parse(text);
  } catch (e) {
    json = null;
  }
  const model = json && json.model ? json.model : config.chatModel;
  const choice = json && Array.isArray(json.choices) && json.choices.length > 0 ? json.choices[0] : null;
  const content = choice && choice.message && typeof choice.message.content === 'string'
    ? choice.message.content
    : '';
  const usage = (json && json.usage) || {};
  const details = usage.completion_tokens_details || {};
  const reasoning = typeof details.reasoning_tokens === 'number' ? details.reasoning_tokens : null;

  if (reasoning !== null && reasoning > 0) {
    warn(
      `这个模型在思考，而当前配置没有关掉它（本次 ${reasoning} 个 token 花在推理上）`,
      `模型 ${model}　总输出 ${usage.completion_tokens} token　finish_reason=${choice ? choice.finish_reason : '?'}\n`
        + '        影响：推理按输出价计费；App 只显示正文，所以推理期间用户看到的是一个不动的空白气泡；\n'
        + '        推理长到吃掉 max_tokens 时，用户收到的是一条正文为空的回复。\n'
        + (config.chatThinking === 'off'
          ? '        CHAT_ENABLE_THINKING 已经是 false 了 —— 说明这家上游用的写法不在这两种之内，需要补一种。'
          : '        修法：在 .env 里设 CHAT_ENABLE_THINKING=false。服务端会同时按两种厂商写法发送，实测两家都有效。'),
    );
    return;
  }

  if (content.trim().length === 0) {
    // 走到这里说明没有推理 token，那么正文为空就不是「思考吃掉预算」那一类，
    // 而是别的问题，别把责任推给思考。
    warn(
      '聊天上游回了 200，但正文是空的',
      `模型 ${model}　finish_reason=${choice ? choice.finish_reason : '?'}\n`
        + '        没有观察到推理 token，所以不是「思考吃掉预算」那一类。',
    );
    return;
  }

  // `reasoning_tokens` 缺席是个弱证据，但对未知厂商只能这么说：它是"没有思考"
  // 的常见形态，不是"没思考"的证明。开着思考时 DeepSeek 会带上这个字段（实测 38），
  // 关掉后整个字段消失 —— 所以出现 >0 一定有问题，缺席则大概率是好事。
  const reasoningLabel = reasoning === null
    ? '推理 未上报（此响应没有 reasoning_tokens 字段）'
    : `推理 ${reasoning} token`;
  ok(
    '聊天上游真的能出话（含余额）',
    `HTTP 200　模型 ${model}　回复 "${excerpt(content, 40)}"　${reasoningLabel}`,
  );
}

/**
 * 嵌入侧探测：POST /embeddings，一条最小输入。
 *
 * 带 dimensions 与否跟随真实配置（EMBEDDING_DIMENSION > 0 时才发），否则这里测通了、
 * 线上仍会被上游拒绝——不支持 Matryoshka 的模型会因为多出来的字段报错。
 */
async function probeEmbedding(config) {
  const url = `${config.embeddingBaseUrl}/embeddings`;
  const body = { model: config.embeddingModel, input: ['连通性检查'] };
  if (config.embeddingDimension > 0) {
    body.dimensions = config.embeddingDimension;
  }

  let response;
  try {
    response = await fetchWithTimeout(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${config.embeddingApiKey}`,
      },
      body: JSON.stringify(body),
    });
  } catch (error) {
    const detail = error && error.name === 'AbortError' ? `超过 ${PROBE_TIMEOUT_MS} ms 未响应` : String(error && error.message);
    fail('嵌入上游连不上', `${url}\n        ${detail}`);
    return;
  }

  const text = await response.text();
  if (response.status === 401 || response.status === 403) {
    fail(
      '嵌入上游拒绝了这把密钥',
      `HTTP ${response.status}　${excerpt(text)}\n        URL、密钥、模型名三者对不上时最容易出这一条。`,
    );
    return;
  }
  if (response.status < 200 || response.status >= 300) {
    fail(
      '嵌入上游拒绝了请求',
      `HTTP ${response.status}　${excerpt(text)}\n        常见原因：模型名不存在，或该模型不支持 dimensions 参数。`,
    );
    return;
  }

  let json = null;
  try {
    json = JSON.parse(text);
  } catch (e) {
    json = null;
  }
  const row = json && Array.isArray(json.data) && json.data.length > 0 ? json.data[0].embedding : null;
  if (!Array.isArray(row) || row.length === 0) {
    warn('嵌入上游返回了 200，但响应里没有向量', `${excerpt(text, 160)}`);
    return;
  }

  ok(
    '嵌入上游密钥有效且模型可用',
    `HTTP 200　维度 ${row.length}　${mask(config.embeddingApiKey)}　指纹 ${fingerprint(config.embeddingApiKey)}`,
  );

  if (config.embeddingDimension > 0 && row.length !== config.embeddingDimension) {
    fail(
      `返回维度与 EMBEDDING_DIMENSION 不一致`,
      `配置 ${config.embeddingDimension}，实际 ${row.length}。线上会被判定为上游数据不完整而返回 502。`,
    );
  }
}

// ---------------------------------------------------------------------------
// 主流程
// ---------------------------------------------------------------------------

function parseArgs(argv) {
  let offline = false;
  let chatPing = true;
  let envFile = path.join(SERVER_DIR, '.env');
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--offline') {
      offline = true;
    } else if (arg === '--no-chat-ping') {
      chatPing = false;
    } else if (arg === '--env-file') {
      i += 1;
      envFile = path.resolve(argv[i] || '');
    } else if (arg.indexOf('--env-file=') === 0) {
      envFile = path.resolve(arg.substring('--env-file='.length));
    }
  }
  return { offline, envFile, chatPing };
}

async function main() {
  const { offline, envFile, chatPing } = parseArgs(process.argv.slice(2));

  console.log('SafeTAcademy AI 后端 — 凭据体检');
  console.log('');

  // --- 文件 ---------------------------------------------------------------
  const loaded = readEnvFile(envFile);
  const fileEnv = loaded.error ? {} : parseEnvFile(loaded.text);
  if (loaded.error) {
    warn(`读不到 ${envFile}（${loaded.error}）`, '改用当前进程的环境变量。');
  } else {
    ok(`已读取 ${envFile}`, `${Object.keys(fileEnv).length} 个键。`);
  }

  // 与 compose / systemd 的优先级一致：环境里已有的覆盖文件里的。
  const env = { ...fileEnv, ...withoutUndefined(process.env) };

  // --- 键名核对 -----------------------------------------------------------
  if (!loaded.error) {
    const example = parseEnvFile(readEnvFile(path.join(SERVER_DIR, '.env.example')).text);
    const known = Object.keys(example);
    const present = Object.keys(fileEnv);

    const missing = known.filter((k) => present.indexOf(k) < 0);
    const unknown = present.filter((k) => known.indexOf(k) < 0);

    if (missing.length > 0) {
      info(`.env 里没有的键：${missing.join('、')}`, '用默认值即可，除非你要改它。');
    }
    if (unknown.length > 0) {
      fail(
        `.env 里有 ${unknown.length} 个服务端不认识的键（多半是拼写错误）`,
        `${unknown.join('、')}\n        服务端只会读 .env.example 里列出的那些名字，写错的键会被静默忽略。`,
      );
    } else {
      ok('没有拼错的键');
    }
    if (unknown.length === 0 && missing.length === 0) {
      ok('键名与 .env.example 完全一致');
    }
  }

  const config = loadConfig(env);

  // --- 能力开关 -----------------------------------------------------------
  console.log('');
  if (config.authRequired()) {
    ok('APP_TOKEN 已设置（鉴权开启）', `指纹 ${fingerprint(config.appToken)}`);
    if (config.appToken.toLowerCase().indexOf('changeme') >= 0) {
      fail('APP_TOKEN 看起来还是占位值', '把 gen-token.mjs 的输出填进去。');
    }
  } else {
    fail('APP_TOKEN 为空 → 鉴权关闭', '任何能连上 8787 端口的人都能白用你的额度。');
  }

  // --- 聊天侧 -------------------------------------------------------------
  console.log('');
  info(
    '聊天侧',
    `上游 ${config.chatBaseUrl}　模型 ${config.chatModel}　思考 ${config.chatThinking}`
      + (config.chatThinking === 'default' ? '（未干预 —— 两家上游都默认开启思考）' : ''),
  );

  if (!config.chatConfigured()) {
    fail('聊天侧未配置', 'CHAT_API_KEY 为空，/chat/completions 会一直回 503。');
  } else {
    describeKeyShape('CHAT_API_KEY', config.chatApiKey);
    if (looksLikeUrl(config.chatApiKey)) {
      fail('CHAT_API_KEY 填成了一个 URL', '这里要的是密钥本身。');
    }
  }

  // --- 嵌入侧 -------------------------------------------------------------
  console.log('');
  info('嵌入侧', `上游 ${config.embeddingBaseUrl}　模型 ${config.embeddingModel}　维度 ${config.embeddingDimension}　批 ${config.embeddingBatchSize}`);

  if (!config.embeddingConfigured()) {
    warn('嵌入侧未配置', 'EMBEDDING_API_KEY 为空：/embed 回 503，客户端退化为纯词法检索，功能不中断。');
  } else {
    describeKeyShape('EMBEDDING_API_KEY', config.embeddingApiKey);
    if (looksLikeUrl(config.embeddingApiKey)) {
      fail('EMBEDDING_API_KEY 填成了一个 URL', '这里要的是密钥本身。');
    }
  }

  // 同一把密钥开两把锁是允许的（DashScope 的聊天与嵌入共用一个 base URL）。
  if (config.chatApiKey.length > 0 && config.chatApiKey === config.embeddingApiKey) {
    info('CHAT_API_KEY 与 EMBEDDING_API_KEY 是同一把', '只有两家上游同属一家时才成立（例如都用百炼）。');
  }

  // --- 在线探测 -----------------------------------------------------------
  if (offline) {
    console.log('');
    info('已跳过在线探测（--offline）', '静态核对到这里就结束了，凭据是否真能用仍未知。');
  } else {
    console.log('');
    console.log('开始在线探测（两家上游各一次真实请求；聊天侧再发一条极短的消息，验证余额与思考开关）…');
    console.log('');
    if (config.chatConfigured()) {
      const models = await probeChatModels(config);
      if (chatPing && (models === null || models.indexOf(config.chatModel) >= 0)) {
        await probeChatCompletion(config);
      }
    }
    if (config.embeddingConfigured()) {
      await probeEmbedding(config);
    }
  }

  // --- 汇总 ---------------------------------------------------------------
  const failures = results.filter((r) => r.level === 'fail');
  const warnings = results.filter((r) => r.level === 'warn');
  console.log('');
  console.log(`体检结束：${failures.length} 项失败，${warnings.length} 项提醒。`);

  if (failures.length > 0) {
    console.log('');
    console.log('需要处理：');
    for (const item of failures) {
      console.log(`  · ${item.title}`);
    }
    process.exitCode = 1;
  } else if (warnings.length === 0) {
    if (offline) {
      console.log('静态核对通过（--offline：凭据是否真能用仍未知）。');
    } else if (chatPing) {
      console.log('两把密钥都通过了真实请求验证，可以起服务了。');
    } else {
      console.log('静态核对与密钥有效性都通过了（跳过了对话探测，余额仍未验证）。');
    }
  }

  // 别忘了：服务端自己不读 .env，环境变量得有人喂进去。
  console.log('');
  console.log('提醒：服务端进程不读 .env 文件本身，起服务前要把这些变量送进环境：');
  console.log('  set -a && . ./.env && set +a && npm start      # 本机');
  console.log('  docker compose up -d                            # 容器（compose 自己读 .env）');
}

function withoutUndefined(source) {
  const out = {};
  for (const key of Object.keys(source)) {
    if (typeof source[key] === 'string') {
      out[key] = source[key];
    }
  }
  return out;
}

const isMain = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  main().catch((error) => {
    console.error('体检脚本自身出错：', error);
    process.exitCode = 1;
  });
}

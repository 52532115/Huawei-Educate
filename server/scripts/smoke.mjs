/*
 * 部署后自检（smoke test）。
 *
 * 存在的理由：`node --test` 跑的是本地桩上游，证明不了「线上这一份到底通不通」。
 * 部署完最需要回答的是三个问题，这个脚本把三件事都变成一条命令：
 *
 *   1. 正常路径  —— /health 能答、聊天能回、嵌入维度对
 *   2. 令牌语义  —— 匿名 401、错令牌 401、对令牌 200
 *   3. 泄露检查  —— 响应体里不得出现厂商密钥特征、不得出现上游主机名
 *
 * 刻意不打印任何密钥：令牌只以长度和指纹形式出现，响应体里的密钥特征会被打码。
 * 厂商密钥根本不会出现在这个进程里——它只存在于服务端环境变量。
 *
 * 用法：
 *   node scripts/smoke.mjs --base https://api.example.com --token <APP_TOKEN>
 *   # 或走环境变量
 *   SMOKE_BASE_URL=... APP_TOKEN=... node scripts/smoke.mjs
 *
 * 退出码：0 = 全部通过（WARN 不算失败），1 = 有 FAIL，2 = 用法错误。
 */

import { pathToFileURL } from 'node:url';

// 指纹实现只有一份（lib/fingerprint.mjs），否则同一个令牌在两个脚本里会算出两个值。
import { tokenFingerprint } from './lib/fingerprint.mjs';

export { tokenFingerprint };

export const HEALTH_PATH = '/health';
export const EMBED_PATH = '/embed';
export const CHAT_PATH = '/v1/chat/completions';
export const DEFAULT_TIMEOUT_MS = 30000;

/**
 * 响应体里**绝不允许**出现的厂商标识。上游主机名出现在 /health 或任何错误体里，
 * 都等于免费告诉未认证的调用者「背后是哪家、该去哪儿撞」。
 */
export const HOST_LEAK_PATTERN = /(api\.deepseek\.com|dashscope\.aliyuncs\.com|aliyuncs\.com|openai\.com)/i;

/** 密钥特征。真实厂商密钥、或任何被原样回显的凭据，都会命中这里。 */
export const SECRET_PATTERNS = [
  { label: 'vendor key (sk-...)', re: /sk-[A-Za-z0-9_-]{16,}/ },
  { label: 'bearer credential', re: /Bearer\s+[A-Za-z0-9._-]{20,}/ },
];

/** 去掉尾部斜杠，避免 `base + '/health'` 变成 `//health`。 */
export function normalizeBase(url) {
  if (typeof url !== 'string') {
    return '';
  }
  let out = url.trim();
  while (out.length > 0 && out.charAt(out.length - 1) === '/') {
    out = out.substring(0, out.length - 1);
  }
  return out;
}

export function joinUrl(base, path) {
  return normalizeBase(base) + path;
}

/**
 * 抹掉文本里的凭据。脚本本身不打印密钥，但错误信息可能把整段 URL 或响应体带出来，
 * 所以经由这个函数再输出一次才安全。
 */
export function redact(text, token = '') {
  if (typeof text !== 'string') {
    return String(text);
  }
  let out = text;
  if (typeof token === 'string' && token.length > 0) {
    while (out.indexOf(token) >= 0) {
      out = out.replace(token, '***');
    }
  }
  for (const { re } of SECRET_PATTERNS) {
    out = out.replace(new RegExp(re.source, 'gi'), '***');
  }
  return out;
}

/** 返回命中的密钥特征标签；干净则返回 null。 */
export function scanForSecrets(text) {
  if (typeof text !== 'string') {
    return null;
  }
  for (const { label, re } of SECRET_PATTERNS) {
    if (re.test(text)) {
      return label;
    }
  }
  return null;
}

/** 返回命中的上游主机名；干净则返回 null。 */
export function scanForHostLeak(text) {
  if (typeof text !== 'string') {
    return null;
  }
  const match = text.match(HOST_LEAK_PATTERN);
  return match ? match[0] : null;
}

export function parseArgs(argv) {
  const options = {
    base: process.env.SMOKE_BASE_URL || '',
    token: process.env.APP_TOKEN || '',
    runChat: true,
    runEmbed: true,
    json: false,
    help: false,
    timeoutMs: DEFAULT_TIMEOUT_MS,
  };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--base' || arg === '-b') {
      options.base = argv[++i] || '';
    } else if (arg === '--token' || arg === '-t') {
      options.token = argv[++i] || '';
    } else if (arg === '--timeout') {
      const seconds = Number.parseInt(argv[++i] || '', 10);
      if (Number.isFinite(seconds) && seconds > 0) {
        options.timeoutMs = seconds * 1000;
      }
    } else if (arg === '--no-chat') {
      options.runChat = false;
    } else if (arg === '--no-embed') {
      options.runEmbed = false;
    } else if (arg === '--json') {
      options.json = true;
    } else if (arg === '--help' || arg === '-h') {
      options.help = true;
    }
  }
  options.base = normalizeBase(options.base);
  return options;
}

/**
 * 把 fetch 抛出的异常翻成一句能拿去排查的话。
 *
 * 坑在这里：`fetch` 的连接失败抛的是 `TypeError: fetch failed`，
 * 真正的 `ECONNREFUSED` / `ENOTFOUND` 藏在 `error.cause` 上。
 * 只看 `error.name` 就只会打印「TypeError」，等于没说。
 */
export function describeError(error) {
  if (!error) {
    return 'unknown';
  }
  if (error.name === 'TimeoutError' || error.name === 'AbortError') {
    return `超时（服务在超时内没有响应）`;
  }
  const causeCode = error.cause && (error.cause.code || error.cause.errno);
  const code = causeCode || error.code;
  if (code) {
    return String(code);
  }
  const causeMessage = error.cause && error.cause.message;
  if (typeof causeMessage === 'string' && causeMessage.length > 0) {
    return causeMessage;
  }
  return error.name || error.message || 'unknown';
}

export const USAGE = [
  '部署后自检 —— 验证线上这一份是否真的可用。',
  '',
  '  node scripts/smoke.mjs --base <URL> [--token <APP_TOKEN>] [选项]',
  '',
  '  -b, --base <URL>    后端基地址，如 https://api.example.com',
  '  -t, --token <TOKEN> 应用令牌（留空则只跑无需鉴权的检查）',
  '      --timeout <秒>  单请求超时，默认 30',
  '      --no-chat       跳过聊天检查（省一次模型调用）',
  '      --no-embed      跳过嵌入检查',
  '      --json          以 JSON 输出',
  '  -h, --help          显示本帮助',
  '',
  '也可以走环境变量 SMOKE_BASE_URL / APP_TOKEN。',
].join('\n');

/**
 * 读响应体，顺带给出「首字节耗时」与「分块数」——这两个数放在一起，
 * 就是流式到底有没有真的流起来的证据（首字节远早于总耗时 = 真的在流）。
 */
async function readBody(res, wantsTiming) {
  const startedAt = Date.now();
  const stream = res.body;
  if (wantsTiming && stream && typeof stream.getReader === 'function') {
    const reader = stream.getReader();
    const decoder = new TextDecoder();
    let firstChunkMs = -1;
    let chunks = 0;
    let text = '';
    for (;;) {
      const { done, value } = await reader.read();
      if (done) {
        break;
      }
      if (value && value.length > 0) {
        if (firstChunkMs < 0) {
          firstChunkMs = Date.now() - startedAt;
        }
        chunks++;
        text += decoder.decode(value, { stream: true });
      }
    }
    text += decoder.decode();
    return { text, firstChunkMs, chunks, totalMs: Date.now() - startedAt };
  }
  const text = await res.text();
  return { text, firstChunkMs: -1, chunks: 1, totalMs: Date.now() - startedAt };
}

function parseJson(text) {
  try {
    return JSON.parse(text);
  } catch (e) {
    return null;
  }
}

/**
 * 路由检查的失败文案。
 *
 * 令牌不对时会先吃 401——这时若照本宣科说「期望 405」，就把人往「路由写错了」
 * 这个方向带偏。真机上「令牌填错 / 首尾多了个空格」远比路由写错常见，
 * 所以 401 要单独认出来并直说。
 */
export function expectedBut(status, expected, what) {
  if (status === 401) {
    return `${what} → 401（令牌被拒；请核对 App ⚙️ 里填的令牌与服务端环境变量 APP_TOKEN 是否逐字相同，注意首尾空格）`;
  }
  return `${what} → ${status}，期望 ${expected}`;
}

/**
 * 跑完整套自检。`fetchImpl` 可注入，所以这个函数本身能被离线单测——
 * 包括那些真实服务器很难制造的失败（例如响应体里回显了密钥）。
 */
export async function runSmoke(options, fetchImpl = globalThis.fetch) {
  const base = normalizeBase(options.base);
  const token = typeof options.token === 'string' ? options.token : '';
  const timeoutMs = options.timeoutMs || DEFAULT_TIMEOUT_MS;
  const results = [];
  const bodies = [];

  const add = (name, status, detail) => {
    results.push({ name, status, detail: typeof detail === 'string' ? detail : '' });
  };

  const call = async (path, init = {}) => {
    const headers = Object.assign({ 'Content-Type': 'application/json' }, init.headers || {});
    const signal = AbortSignal.timeout(timeoutMs);
    const res = await fetchImpl(joinUrl(base, path), {
      method: init.method || 'POST',
      headers,
      body: init.body,
      signal,
    });
    const wantsTiming = init.timing === true;
    return { res, body: await readBody(res, wantsTiming) };
  };

  const authHeader = (value) => (value.length > 0 ? { Authorization: `Bearer ${value}` } : {});

  // ---- 1. 连通性与健康 ----
  let health = null;
  try {
    const { res, body } = await call(HEALTH_PATH, {
      method: 'GET',
      timing: false,
    });
    bodies.push({ path: HEALTH_PATH, text: body.text });
    health = parseJson(body.text);
    if (res.status === 200 && health && health.ok === true) {
      add('健康检查', 'PASS', `GET /health → 200`);
    } else {
      add('健康检查', 'FAIL', `GET /health → ${res.status}，期望 200 且 ok=true`);
    }
  } catch (error) {
    add('连通性', 'FAIL',
      `请求 ${base}${HEALTH_PATH} 失败：${describeError(error)}`);
    add('健康检查', 'SKIP', '连不上，后续检查无意义');
    return { base, token, authRequired: null, results, bodies };
  }

  const authRequired = health ? health.authRequired === true : null;
  /**
   * 能不能发一个「服务端会接受的」请求。
   *
   * 注意 `authRequired === false` 这一支：鉴权关掉时**不需要任何令牌**，
   * 功能检查照样能跑。早先这里只判「有没有令牌」，结果是「关掉鉴权 + 聊天坏掉」
   * 会被报成清一色 SKIP、零 FAIL —— 恰好是最该报警的组合被静默放过。
   */
  const canAuthenticate = authRequired === false || token.length > 0;
  if (health && health.chat && health.chat.configured === false) {
    add('聊天已配置', 'WARN', '/health 报 chat.configured=false，聊天路径会返回 503');
  }
  if (health && health.embedding && health.embedding.configured === false) {
    add('嵌入已配置', 'WARN', '/health 报 embedding.configured=false，嵌入路径会返回 503');
  }

  // ---- 2. 鉴权语义（三种情形里的后两种）----
  const probeBody = JSON.stringify({ inputs: ['ping'] });
  const anonymous = await call(EMBED_PATH, { body: probeBody });
  bodies.push({ path: `${EMBED_PATH} (anonymous)`, text: anonymous.body.text });

  if (authRequired === false) {
    add('匿名访问被拒', 'WARN',
      'APP_TOKEN 未设置：鉴权已关闭。这对公网部署是危险的——等于把模型额度对外开放。');
  } else if (anonymous.res.status === 401) {
    add('匿名访问被拒', 'PASS', '匿名 POST /embed → 401');
  } else {
    add('匿名访问被拒', 'FAIL', `匿名 POST /embed → ${anonymous.res.status}，期望 401`);
  }

  if (authRequired !== false) {
    const wrong = await call(EMBED_PATH, {
      body: probeBody,
      headers: { Authorization: 'Bearer definitely-not-the-token' },
    });
    bodies.push({ path: `${EMBED_PATH} (wrong token)`, text: wrong.body.text });
    if (wrong.res.status === 401) {
      add('错误令牌被拒', 'PASS', '错误令牌 POST /embed → 401');
    } else {
      add('错误令牌被拒', 'FAIL', `错误令牌 POST /embed → ${wrong.res.status}，期望 401`);
    }
  } else {
    add('错误令牌被拒', 'SKIP', '鉴权已关闭，无令牌可比');
  }

  // ---- 3. 路由语义 ----
  if (canAuthenticate) {
    const getEmbed = await call(EMBED_PATH, { method: 'GET', headers: authHeader(token) });
    bodies.push({ path: `${EMBED_PATH} (GET)`, text: getEmbed.body.text });
    if (getEmbed.res.status === 405) {
      add('方法校验', 'PASS', 'GET /embed → 405');
    } else {
      add('方法校验', 'FAIL', expectedBut(getEmbed.res.status, 405, 'GET /embed'));
    }

    const notFound = await call('/definitely-not-a-route', {
      method: 'POST',
      headers: authHeader(token),
      body: '{}',
    });
    bodies.push({ path: '/definitely-not-a-route', text: notFound.body.text });
    if (notFound.res.status === 404) {
      add('未知路由', 'PASS', 'POST /definitely-not-a-route → 404');
    } else {
      add('未知路由', 'FAIL',
        expectedBut(notFound.res.status, 404, 'POST /definitely-not-a-route'));
    }
  } else {
    add('方法校验', 'SKIP', '鉴权开启但未提供令牌');
    add('未知路由', 'SKIP', '鉴权开启但未提供令牌');
  }

  // ---- 4. 嵌入路径 ----
  const embedWanted = options.runEmbed === true
    && canAuthenticate
    && health && health.embedding && health.embedding.configured === true;
  if (!embedWanted) {
    add('嵌入返回一致', 'SKIP',
      !canAuthenticate ? '鉴权开启但未提供令牌'
        : (options.runEmbed !== true ? '已用 --no-embed 跳过'
          : '嵌入未配置（EMBEDDING_API_KEY 缺失）'));
  } else {
    try {
      const { res, body } = await call(EMBED_PATH, {
        headers: authHeader(token),
        body: JSON.stringify({ inputs: ['三次握手', '进程和线程的区别'] }),
      });
      bodies.push({ path: `${EMBED_PATH} (authorized)`, text: body.text.slice(0, 2000) });
      const payload = parseJson(body.text);
      const vectors = payload && Array.isArray(payload.vectors) ? payload.vectors : null;
      if (res.status !== 200) {
        add('嵌入返回一致', 'FAIL', `POST /embed → ${res.status}`);
      } else if (!vectors || vectors.length !== 2) {
        add('嵌入返回一致', 'FAIL',
          `返回 ${vectors ? vectors.length : '非数组'} 条向量，期望 2 条（与 inputs 一一对应）`);
      } else if (!Array.isArray(vectors[0]) || vectors[0].length === 0
        || vectors[0].length !== vectors[1].length) {
        add('嵌入返回一致', 'FAIL', '两条向量宽度不一致或为空');
      } else if (health.embedding.dimension > 0
        && vectors[0].length !== health.embedding.dimension) {
        add('嵌入返回一致', 'FAIL',
          `向量宽度 ${vectors[0].length}，/health 声明 ${health.embedding.dimension}`);
      } else {
        add('嵌入返回一致', 'PASS', `2 条向量，宽度 ${vectors[0].length}，顺序与输入一致`);
      }
    } catch (error) {
      add('嵌入返回一致', 'FAIL', `请求抛出：${error && error.name}`);
    }
  }

  // ---- 5. 聊天路径（非流式 + 流式）----
  const chatWanted = options.runChat === true
    && canAuthenticate
    && health && health.chat && health.chat.configured === true;
  if (!chatWanted) {
    add('聊天非流式', 'SKIP',
      !canAuthenticate ? '鉴权开启但未提供令牌'
        : (options.runChat !== true ? '已用 --no-chat 跳过'
          : '聊天未配置（CHAT_API_KEY 缺失）'));
    add('聊天流式', 'SKIP', '同上');
  } else {
    const messages = [{ role: 'user', content: '只回复两个字：收到' }];
    try {
      const { res, body } = await call(CHAT_PATH, {
        headers: authHeader(token),
        body: JSON.stringify({ messages, stream: false }),
      });
      bodies.push({ path: `${CHAT_PATH} (buffered)`, text: body.text.slice(0, 2000) });
      const payload = parseJson(body.text);
      const choices = payload && Array.isArray(payload.choices) ? payload.choices : null;
      const content = choices && choices[0] && choices[0].message
        ? choices[0].message.content : null;
      if (res.status !== 200) {
        add('聊天非流式', 'FAIL', `POST ${CHAT_PATH} → ${res.status}`);
      } else if (typeof content !== 'string' || content.trim().length === 0) {
        add('聊天非流式', 'FAIL', '200 但 choices[0].message.content 为空');
      } else {
        add('聊天非流式', 'PASS', `200，返回 ${content.trim().length} 字`);
      }
    } catch (error) {
      add('聊天非流式', 'FAIL', `请求抛出：${error && error.name}`);
    }

    try {
      const { res, body } = await call(CHAT_PATH, {
        headers: authHeader(token),
        body: JSON.stringify({ messages, stream: true }),
        timing: true,
      });
      bodies.push({ path: `${CHAT_PATH} (stream)`, text: body.text.slice(0, 2000) });
      // 只数**内容**分片：`data: [DONE]` 是终结符，一个健康但空转的流也会有它。
      // 若把终结符算进去，「只有 [DONE]、没有任何内容」就会误判为通过。
      const dataLines = (body.text.match(/^data:(?!\s*\[DONE\])/gm) || []).length;
      if (res.status !== 200) {
        add('聊天流式', 'FAIL', `POST ${CHAT_PATH} (stream) → ${res.status}`);
      } else if (dataLines === 0) {
        add('聊天流式', 'FAIL', '200 但没有任何内容分片（只有终结符或空流）');
      } else {
        // 首字节远早于总耗时，才说明是边生成边发；两者接近则说明被整段缓冲了。
        const looksBuffered = body.chunks === 1 && body.totalMs > 1000;
        const detail = `SSE ${dataLines} 片，首字节 ${body.firstChunkMs}ms / 总计 ${body.totalMs}ms`;
        if (looksBuffered) {
          add('聊天流式', 'WARN', `${detail} —— 只收到 1 个分片，可能被反向代理缓冲了`);
        } else {
          add('聊天流式', 'PASS', detail);
        }
      }
    } catch (error) {
      add('聊天流式', 'FAIL', `请求抛出：${error && error.name}`);
    }
  }

  // ---- 6. 泄露检查 ----
  let leak = null;
  let hostLeak = null;
  for (const entry of bodies) {
    const secret = scanForSecrets(entry.text);
    if (secret && !leak) {
      leak = `${entry.path} 出现 ${secret}`;
    }
    // 上游主机名只在「本该公开形状」的响应里查：/health 与错误体。
    const isErrorish = entry.path === HEALTH_PATH || entry.text.indexOf('"error"') >= 0;
    if (isErrorish) {
      const host = scanForHostLeak(entry.text);
      if (host && !hostLeak) {
        hostLeak = `${entry.path} 泄露上游主机 ${host}`;
      }
    }
  }
  if (leak) {
    add('响应体无密钥', 'FAIL', leak);
  } else {
    add('响应体无密钥', 'PASS', `已检查 ${bodies.length} 个响应体，无密钥特征`);
  }
  if (hostLeak) {
    add('响应体无上游地址', 'FAIL', hostLeak);
  } else {
    add('响应体无上游地址', 'PASS', '未发现上游主机名');
  }

  return { base, token, authRequired, results, bodies };
}

export function summarize(results) {
  const counts = { PASS: 0, FAIL: 0, WARN: 0, SKIP: 0 };
  for (const r of results) {
    counts[r.status] = (counts[r.status] || 0) + 1;
  }
  return counts;
}

function printReport(report, token) {
  const width = report.results.reduce((max, r) => Math.max(max, r.name.length), 0);
  console.log(`目标 ${report.base}`);
  console.log(`令牌 ${tokenFingerprint(token)}（不打印内容）`);
  console.log('');
  for (const r of report.results) {
    const name = r.name.padEnd(width);
    const detail = r.detail ? `  ${redact(r.detail, token)}` : '';
    console.log(`${r.status.padEnd(4)} ${name}${detail}`);
  }
  const counts = summarize(report.results);
  console.log('');
  console.log(`合计 通过 ${counts.PASS} · 失败 ${counts.FAIL} · 警告 ${counts.WARN} · 跳过 ${counts.SKIP}`);
  if (counts.FAIL > 0) {
    console.log('');
    console.log('有失败项。按顺序排查：');
    console.log('  1. 进程在跑吗        docker compose ps / systemctl status safeta-ai-backend');
    console.log('  2. 反代转发对吗      curl -v https://<域名>/health');
    console.log('  3. 密钥配了吗        /health 里 chat.configured / embedding.configured 是否为 true');
    console.log('  4. 令牌一致吗        App ⚙️ 里的令牌与 APP_TOKEN 逐字相同（注意首尾空格）');
  } else if (counts.WARN > 0) {
    console.log('');
    console.log('没有失败项，但有警告——上表中 WARN 的说明请读一遍，多半是安全相关。');
  } else {
    console.log('');
    console.log('全部通过。可以把 Base URL 和令牌填进 App 的 ⚙️ 面板了。');
  }
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    console.log(USAGE);
    process.exitCode = 0;
    return;
  }
  if (options.base.length === 0) {
    console.error('缺少 --base（或环境变量 SMOKE_BASE_URL）。\n');
    console.error(USAGE);
    process.exitCode = 2;
    return;
  }

  const report = await runSmoke(options);

  if (options.json) {
    // JSON 里同样只有指纹，没有令牌本体。
    const safe = {
      base: report.base,
      authRequired: report.authRequired,
      tokenFingerprint: tokenFingerprint(report.token),
      results: report.results.map((r) => ({
        name: r.name,
        status: r.status,
        detail: redact(r.detail, report.token),
      })),
      counts: summarize(report.results),
    };
    console.log(JSON.stringify(safe, null, 2));
  } else {
    printReport(report, report.token);
  }

  const counts = summarize(report.results);
  process.exitCode = counts.FAIL > 0 ? 1 : 0;
}

const invokedDirectly = process.argv[1]
  && import.meta.url === pathToFileURL(process.argv[1]).href;
if (invokedDirectly) {
  main().catch((error) => {
    console.error(`自检脚本自身出错：${error && error.message}`);
    process.exitCode = 2;
  });
}

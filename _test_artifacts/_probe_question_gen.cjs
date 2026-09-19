/*
 * 一次性探针：向后端真发一次「出题」请求，看模型实际返回什么形状。
 *
 * 目的只有一个——**解析契约不能靠猜**。项目里已经有两次教训（loader 漏注入符号、
 * 变异测试抓不到恒真断言），格式假设同理：与其假设模型会规规矩矩回一个 JSON 数组、
 * correctIndex 从 0 开始，不如真发一次，把原文打出来。
 *
 * 用法：node _test_artifacts/_probe_question_gen.cjs
 * 输出：_test_artifacts/_probe_question_gen.log（原文 + 结构分析）
 */
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const LOG_PATH = path.join(__dirname, '_probe_question_gen.log');
const captured = [];
const rawLog = console.log.bind(console);
console.log = (...args) => {
  captured.push(args.map((a) => (typeof a === 'string' ? a : JSON.stringify(a))).join(' '));
  rawLog(...args);
};
process.on('exit', () => {
  try {
    fs.writeFileSync(LOG_PATH, captured.join('\n') + '\n');
  } catch (e) { /* 留证失败不该改退出码 */ }
});

function readEnvFile(envPath) {
  const env = {};
  if (!fs.existsSync(envPath)) {
    return env;
  }
  const text = fs.readFileSync(envPath, 'utf8').replace(/^\uFEFF/, '');
  for (const line of text.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (trimmed.length === 0 || trimmed.startsWith('#')) {
      continue;
    }
    const eq = trimmed.indexOf('=');
    if (eq < 0) {
      continue;
    }
    env[trimmed.slice(0, eq).trim()] = trimmed.slice(eq + 1).trim();
  }
  return env;
}

const env = readEnvFile(path.join(ROOT, 'server', '.env'));
const TOKEN = env.APP_TOKEN || '';
const PORT = env.PORT || '8787';
const BASE = (process.argv.indexOf('--base') >= 0
  ? process.argv[process.argv.indexOf('--base') + 1] : `http://127.0.0.1:${PORT}`);

// ---------- 讲义片段（真实语料里的一段，直接从讲义文件抽出来） ----------
const PASSAGES = [
  {
    citation: '数据结构 › 树 › 二叉搜索树',
    text: '二叉搜索树的性质是：对任意结点，其左子树上所有结点的值都小于它，右子树上所有结点的值都大于它。'
      + '因此查找时每次比较都能排除一半子树，平均时间复杂度为 O(log n)。当插入序列已经有序时，'
      + '树会退化成一条链，此时查找退化为 O(n)，这也是平衡树（AVL、红黑树）存在的理由。',
  },
  {
    citation: '计算机网络 › 传输层 › TCP 三次握手',
    text: 'TCP 建立连接需要三次握手：客户端发送 SYN，服务端回复 SYN+ACK，客户端再发送 ACK。'
      + '第三次握手不是为了确认服务端的接收能力，而是为了让服务端确认客户端确实收到了自己的 SYN+ACK，'
      + '避免历史失效连接请求造成服务端资源浪费。',
  },
  {
    citation: '操作系统 › 进程与线程 › 进程与线程的区别',
    text: '进程是资源分配的基本单位，拥有独立的地址空间；线程是处理器调度的基本单位，同一进程内的线程共享地址空间。'
      + '因此线程间通信开销小但需要同步，一个线程崩溃会导致整个进程终止。',
  },
];

const SYSTEM = `你是一位出题老师，负责根据给定的讲义片段出单选题。

出题规则：
1. 只能依据【讲义片段】出题，不得引入片段之外的知识；片段没讲到的内容不许出现。
2. 每题恰好 4 个选项，有且只有一个正确答案，其余 3 个是常见误解或概念混淆。
3. 考察理解与应用，不要出"片段第几句写了什么"这类背诵题。
4. 只返回一个 JSON 数组，不要任何解释文字，不要 Markdown 代码块，不要注释。

数组里每个元素的字段：
- "title": 字符串，题干，一个完整的中文问句
- "options": 恰好 4 个字符串的数组，选项文字里不要带 A/B/C/D 前缀
- "correctIndex": 整数，正确选项在 options 里的下标，从 0 开始（0 表示第一个选项）
- "explanation": 字符串，2~3 句，说明为什么这个选项对、其他选项错在哪
- "recommendation": 字符串，一句话的练习建议`;

function buildUser(tag, difficulty, passages, count) {
  const lines = [`知识点：${tag}`, `难度：${difficulty}`, '', '【讲义片段】'];
  for (let i = 0; i < passages.length; i++) {
    lines.push(`片段 ${i}（${passages[i].citation}）`);
    lines.push(passages[i].text);
    lines.push('');
  }
  lines.push(`请出 ${count} 道单选题。`);
  return lines.join('\n');
}

function analyze(content) {
  const report = {};
  report.length = content.length;
  report.hasFence = content.indexOf('```') >= 0;
  report.firstBracket = content.indexOf('[');
  report.lastBracket = content.lastIndexOf(']');
  report.startsWithBracket = content.trim().startsWith('[');

  let parsed = null;
  let extracted = content.trim();
  if (report.hasFence) {
    const start = extracted.indexOf('```');
    let body = extracted.slice(start + 3);
    if (body.startsWith('json')) {
      body = body.slice(4);
    }
    const end = body.indexOf('```');
    extracted = end >= 0 ? body.slice(0, end) : body;
  }
  const lb = extracted.indexOf('[');
  const rb = extracted.lastIndexOf(']');
  if (lb >= 0 && rb > lb) {
    extracted = extracted.slice(lb, rb + 1);
  }
  try {
    parsed = JSON.parse(extracted);
  } catch (e) {
    report.parseError = e.message;
  }
  report.extractedOk = parsed !== null && Array.isArray(parsed);
  if (report.extractedOk) {
    report.itemCount = parsed.length;
    report.itemKeys = parsed.map((o) => Object.keys(o).join(','));
    report.optionCounts = parsed.map((o) => (Array.isArray(o.options) ? o.options.length : -1));
    report.correctIndexTypes = parsed.map((o) => typeof o.correctIndex);
    report.correctIndexValues = parsed.map((o) => o.correctIndex);
    report.sourceIndexTypes = parsed.map((o) => typeof o.sourceIndex);
    report.sourceIndexValues = parsed.map((o) => o.sourceIndex);
    report.hasPrefixInOptions = parsed.map((o) => (Array.isArray(o.options)
      ? o.options.some((s) => /^[A-D][.、)．]\s*/.test(String(s))) : null));
    report.hasRecommendation = parsed.map((o) => typeof o.recommendation === 'string' && o.recommendation.length > 0);
    report.titleLengths = parsed.map((o) => (typeof o.title === 'string' ? o.title.length : -1));
    report.explanationLengths = parsed.map((o) => (typeof o.explanation === 'string' ? o.explanation.length : -1));
  }
  return report;
}

(async () => {
  console.log(`后端  ${BASE}`);
  console.log(`令牌  长度 ${TOKEN.length}`);
  const body = {
    model: env.CHAT_MODEL || 'deepseek-flash',
    messages: [
      { role: 'system', content: SYSTEM },
      { role: 'user', content: buildUser('二叉搜索树', '基础', PASSAGES, 3) },
    ],
    stream: false,
    max_tokens: 2048,
  };

  const started = Date.now();
  let response;
  try {
    response = await fetch(`${BASE}/chat/completions`, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        ...(TOKEN.length > 0 ? { authorization: `Bearer ${TOKEN}` } : {}),
      },
      body: JSON.stringify(body),
    });
  } catch (e) {
    console.log(`请求失败：${e.message}`);
    return;
  }
  const elapsed = Date.now() - started;
  const text = await response.text();
  console.log(`HTTP ${response.status}  用时 ${elapsed} ms`);
  if (response.status !== 200) {
    console.log(text.slice(0, 800));
    return;
  }
  const json = JSON.parse(text);
  const choice = json.choices && json.choices[0];
  const content = (choice && choice.message && choice.message.content) || '';
  console.log(`finish_reason ${choice ? choice.finish_reason : '?'}`);
  console.log(`usage ${JSON.stringify(json.usage)}`);
  console.log('---------- 原文 ----------');
  console.log(content);
  console.log('---------- 结构分析 ----------');
  console.log(JSON.stringify(analyze(content), null, 2));
})();

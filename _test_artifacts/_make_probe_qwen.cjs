/*
 * 生成「聊天侧改走百炼」的探测用 env 文件。
 *
 * 背景：DeepSeek 账户余额不足（402），但百炼账户是好的（嵌入刚跑通）。这份文件
 * 用来验证「同一个百炼 key 能不能把聊天也顶起来」，不改动 server/.env 本身。
 *
 * 用完即弃，不参与任何正式测试套件。
 */
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const raw = fs.readFileSync(path.join(ROOT, 'server', '.env'), 'utf8');

function getLine(src, key) {
  for (const line of src.split(/\r?\n/)) {
    const eq = line.indexOf('=');
    if (eq >= 0 && line.slice(0, eq).trim() === key) {
      return line.slice(eq + 1);
    }
  }
  return '';
}

function setLine(src, key, value) {
  const lines = src.split(/\r?\n/);
  let found = false;
  const out = lines.map((line) => {
    const eq = line.indexOf('=');
    if (eq < 0 || line.slice(0, eq).trim() !== key) {
      return line;
    }
    found = true;
    return key + '=' + value;
  });
  if (!found) {
    out.push(key + '=' + value);
  }
  return out.join('\n');
}

const dashscopeKey = getLine(raw, 'EMBEDDING_API_KEY');
if (dashscopeKey.length === 0) {
  console.error('没有 EMBEDDING_API_KEY，无法构造探测样本');
  process.exit(1);
}

const model = process.argv[2] || 'qwen3.7-flash';

let out = setLine(raw, 'CHAT_BASE_URL', 'https://dashscope.aliyuncs.com/compatible-mode/v1');
out = setLine(out, 'CHAT_API_KEY', dashscopeKey);
out = setLine(out, 'CHAT_MODEL', model);
out = setLine(out, 'CHAT_ENABLE_THINKING', 'false');

const target = path.join(__dirname, '_probe-qwen.env');
fs.writeFileSync(target, out);
console.log('written', target, '模型 =', model);

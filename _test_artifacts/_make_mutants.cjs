/*
 * 生成 check-upstream.mjs 的变异样本：把 .env 各改坏一处，用来确认体检脚本
 * 真的会变红，而不是恒绿的摆设。
 *
 * 用完即弃，不参与任何正式测试套件。
 */
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const raw = fs.readFileSync(path.join(ROOT, 'server', '.env'), 'utf8');
const out = __dirname;

function edit(src, key, fn) {
  return src
    .split(/\r?\n/)
    .map((line) => {
      const eq = line.indexOf('=');
      if (eq < 0) {
        return line;
      }
      if (line.slice(0, eq).trim() !== key) {
        return line;
      }
      return key + '=' + fn(line.slice(eq + 1));
    })
    .join('\n');
}

const mutants = {
  // 密钥最末一位被改掉：真实世界里最常见的"复制少了一个字符"。
  '_mutant-chat-key.env': edit(raw, 'CHAT_API_KEY', (v) => v.slice(0, -1) + '8'),
  // 模型名不存在：代码全对，只有名字打错。
  '_mutant-chat-model.env': edit(raw, 'CHAT_MODEL', () => 'deepseek-flash-turbo'),
  // 嵌入密钥被改坏。
  '_mutant-embed-key.env': edit(raw, 'EMBEDDING_API_KEY', (v) => v.slice(0, -1) + 'X'),
};

for (const name of Object.keys(mutants)) {
  fs.writeFileSync(path.join(out, name), mutants[name]);
  console.log('written', name);
}

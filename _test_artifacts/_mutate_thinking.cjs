/*
 * 变异验证：确认「思考开关两种方言一起发」的断言真的会红。
 *
 * 要证伪的是最危险的那种回归——**退回只发 enable_thinking**。它在 DeepSeek 上是
 * 静默空操作：代码跑得好好的、日志和 /health 都显示 off，只有模型还在思考。
 * 如果测试对这种回归是绿的，那这些断言就只是装饰。
 *
 * 用完即弃。跑完会把文件还原并校验哈希。
 */
const fs = require('fs');
const path = require('path');
const cp = require('child_process');
const crypto = require('crypto');

const ROOT = path.resolve(__dirname, '..');
const SERVER = path.join(ROOT, 'server');
const TARGET = path.join(SERVER, 'src', 'config.js');

const original = fs.readFileSync(TARGET, 'utf8');
const hashOf = (text) => crypto.createHash('sha256').update(text).digest('hex').slice(0, 12);

const MUTANTS = [
  {
    name: '删掉 DeepSeek 写法（只留 enable_thinking，= 退回旧行为）',
    find: "      thinking: { type: enabled ? 'enabled' : 'disabled' },\n",
    repl: '',
  },
  {
    name: "把 disabled 写成 enabled（字段在、值是反的）",
    find: "{ type: enabled ? 'enabled' : 'disabled' }",
    repl: "{ type: enabled ? 'enabled' : 'enabled' }",
  },
];

function runTests() {
  const result = cp.spawnSync(process.execPath, ['--test'], { cwd: SERVER, encoding: 'utf8' });
  return (result.stdout || '') + (result.stderr || '');
}

function failCount(text) {
  const match = /# fail (\d+)/.exec(text);
  return match ? Number(match[1]) : -1;
}

let allGood = true;

for (const mutant of MUTANTS) {
  if (original.indexOf(mutant.find) < 0) {
    console.log(`[skip] ${mutant.name} —— 找不到锚点，变异脚本自身需要更新`);
    allGood = false;
    continue;
  }
  fs.writeFileSync(TARGET, original.replace(mutant.find, mutant.repl));
  const fails = failCount(runTests());
  const went = fails > 0;
  console.log(`${went ? '[ok]  ' : '[FAIL]'} ${mutant.name} → 失败用例 ${fails < 0 ? '解析不到' : fails} 条`);
  if (!went) {
    allGood = false;
  }
}

// 还原并确认，避免把坏文件留在工作区。
fs.writeFileSync(TARGET, original);
const restored = fs.readFileSync(TARGET, 'utf8') === original;
console.log(`\n还原：${restored ? '[ok]  与原文件逐字节一致' : '[FAIL] 还原失败，请手动检查 config.js'}`);
if (!restored) {
  allGood = false;
}

const baseline = failCount(runTests());
console.log(`还原后基线：失败 ${baseline < 0 ? '解析不到' : baseline} 条（应为 0）  哈希 ${hashOf(original)}`);
process.exitCode = allGood && baseline === 0 ? 0 : 1;

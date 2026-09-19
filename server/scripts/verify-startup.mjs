/*
 * Startup verification — the companion to verify-guards.mjs.
 *
 * `node --test` covers everything reachable through createApp(), but not
 * `src/index.js`: that file only exists to boot a real process, and the two
 * things it does (shout about an unconfigured capability, echo the effective
 * chat settings) can only be observed by booting one.
 *
 * This matters because an unrecognized CHAT_ENABLE_THINKING collapses to
 * "send nothing", which on a Qwen model means thinking is ON — a typo would
 * quietly produce exactly the behaviour the operator was trying to avoid. So
 * the warning is worth an assertion, not just a line of code.
 *
 * Usage: node scripts/verify-startup.mjs
 * Ports 18787-18789 must be free.
 */
import { spawn } from 'node:child_process';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const serverDir = resolve(here, '..');

async function boot({ port, thinking }) {
  const env = { ...process.env, PORT: String(port), APP_TOKEN: 'probe-token' };
  if (thinking === null) {
    delete env.CHAT_ENABLE_THINKING;
  } else {
    env.CHAT_ENABLE_THINKING = thinking;
  }
  const child = spawn(process.execPath, ['src/index.js'], { cwd: serverDir, env });
  let log = '';
  child.stdout.on('data', (chunk) => { log += chunk.toString(); });
  child.stderr.on('data', (chunk) => { log += chunk.toString(); });

  const deadline = Date.now() + 8000;
  while (Date.now() < deadline && log.indexOf('listening') < 0) {
    await new Promise((r) => setTimeout(r, 40));
  }
  if (log.indexOf('listening') < 0) {
    child.kill();
    throw new Error(`服务未在 8s 内启动（端口 ${port} 是否被占用？）：\n${log}`);
  }

  let health = null;
  try {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 3000);
    const response = await fetch(`http://127.0.0.1:${port}/health`, { signal: controller.signal });
    health = await response.json();
    clearTimeout(timer);
  } catch (error) {
    health = { error: String(error && error.message) };
  }
  child.kill();
  await new Promise((r) => { child.on('exit', r); setTimeout(r, 1500); });
  return { log, health };
}

const fails = [];
function check(name, ok, detail) {
  console.log(`${ok ? 'OK  ' : 'FAIL'}  ${name}${ok ? '' : `  -> ${detail}`}`);
  if (!ok) {
    fails.push(name);
  }
}

// --- 拼错的值必须被喊出来，而不是悄悄按「不发送」处理 ---
const typo = await boot({ port: 18787, thinking: 'ture' });
check('启动时对无法识别的 CHAT_ENABLE_THINKING 发出警告',
  typo.log.indexOf('not understood') >= 0, typo.log.slice(0, 400));
check('拼错时回落到「不发送」，而不是猜一个布尔值',
  typo.health.chat && typo.health.chat.thinking === 'default',
  JSON.stringify(typo.health.chat));

// --- 明确关闭：这是接 Qwen 时的正确姿势 ---
const off = await boot({ port: 18788, thinking: 'false' });
check('启动日志回显 chatModel / chatThinking',
  off.log.indexOf('"chatThinking":"off"') >= 0, off.log.slice(0, 400));
check('/health 如实回答 thinking=off',
  off.health.chat && off.health.chat.thinking === 'off',
  JSON.stringify(off.health.chat));
check('/health 不泄露密钥或上游地址',
  JSON.stringify(off.health).indexOf('sk-') < 0
  && JSON.stringify(off.health).indexOf('dashscope') < 0
  && JSON.stringify(off.health).indexOf('api.deepseek.com') < 0,
  JSON.stringify(off.health));

// --- 完全不设该变量：DeepSeek 的用法，必须保持沉默 ---
const unset = await boot({ port: 18789, thinking: null });
check('不设置时保持 default，且不产生拼写警告',
  unset.health.chat.thinking === 'default' && unset.log.indexOf('not understood') < 0,
  JSON.stringify(unset.health.chat));

console.log(fails.length === 0
  ? '\n启动行为全部通过'
  : `\n失败：${fails.join(' | ')}`);
process.exit(fails.length === 0 ? 0 : 1);

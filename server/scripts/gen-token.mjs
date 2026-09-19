/*
 * 生成一个 APP_TOKEN。
 *
 * 只打印，不写文件——刻意如此。令牌一旦落到磁盘上就有被误提交的风险，
 * 而这个脚本最常见的用法是「在服务器上生成、粘进 .env、然后忘掉它」。
 *
 * 32 字节随机数（256 位）经 base64url 编码，无填充、无特殊字符，
 * 可以直接塞进 .env、HTTP 头和 App 的输入框，不用考虑转义。
 *
 * 用法：
 *   node scripts/gen-token.mjs          # 生成一个
 *   node scripts/gen-token.mjs --quiet  # 只输出令牌本身，便于管道赋值
 */

import { randomBytes } from 'node:crypto';
import { pathToFileURL } from 'node:url';

export function generateToken(bytes = 32) {
  return randomBytes(bytes).toString('base64url');
}

function main() {
  const quiet = process.argv.includes('--quiet');
  const token = generateToken();
  if (quiet) {
    console.log(token);
    return;
  }
  console.log('新的 APP_TOKEN（只显示这一次，本脚本不写任何文件）：');
  console.log('');
  console.log(`APP_TOKEN=${token}`);
  console.log('');
  console.log('粘进 server/.env（或 systemd 的 EnvironmentFile）之后：');
  console.log('  · .env 权限设为 600，且确认从未被 git 跟踪（.gitignore 已忽略 server/.env）');
  console.log('  · 重启服务：docker compose up -d  /  systemctl restart safeta-ai-backend');
  console.log('  · 跑一次自检：node scripts/smoke.mjs --base <URL> --token <同一把>');
  console.log('');
  console.log('轮换纪律：这把令牌只放进服务端环境变量和 App 的 ⚙️ 面板，不要发给任何人、');
  console.log('不要贴进聊天记录或工单。泄露时重新生成一把换上即可——旧客户端立刻失效，不需要发版。');
}

const invokedDirectly = process.argv[1]
  && import.meta.url === pathToFileURL(process.argv[1]).href;
if (invokedDirectly) {
  main();
}

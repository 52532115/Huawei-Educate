/*
 * 部署护栏的变异验证。
 *
 * 为什么需要：`test/deploy.test.js` 里的断言全是静态检查——它们平时永远是绿的，
 * 只有在**有人真的改坏**时才有价值。没验证过「改坏会不会红」的静态断言，
 * 很可能写成了恒真条件，等于没有。
 *
 * 这个脚本把每条护栏对应的加固项**故意删掉**，跑一次 deploy.test.js，确认它变红，
 * 然后原样还原并用哈希校验还原成功。任何一步失败都会立刻退出并报明原因。
 *
 * 什么时候跑：改完 Dockerfile / compose / 反代配置 / systemd unit 之后，
 * 或者新增了一条护栏断言之后。不是每次都跑——它会写真实文件。
 *
 *   node scripts/verify-guards.mjs
 *
 * 注意：本脚本必须放在 scripts/ 而不是 test/ —— Node 的测试发现规则会把
 * `test/**\/*.js` 全部当成测试文件，放进去就会在 `node --test` 时被执行。
 */

import fs from 'node:fs';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';

const SERVER_DIR = fileURLToPath(new URL('..', import.meta.url));
const TEST_FILE = 'test/deploy.test.js';

/**
 * 每条都是一处「删掉之后本地照样能跑、到线上才发作」的加固项。
 * `from` 必须精确匹配现有文件内容——匹配不到会报错，而不是静默跳过，
 * 这样文件改名/重排后这个脚本会立刻提醒自己过期了。
 */
const MUTATIONS = [
  {
    name: '去掉 api 的 cap_drop',
    file: 'docker-compose.yml',
    from: '    cap_drop:\n      - ALL\n',
    to: '    cap_drop: []\n',
  },
  {
    name: '把 api 端口暴露到公网',
    file: 'docker-compose.yml',
    from: '      - "127.0.0.1:8787:8787"',
    to: '      - "8787:8787"',
  },
  {
    name: '去掉 api 的 read_only',
    file: 'docker-compose.yml',
    from: '    read_only: true\n',
    to: '    read_only: false\n',
  },
  {
    name: 'Dockerfile 里加上 npm install',
    file: 'Dockerfile',
    from: 'WORKDIR /app',
    to: 'WORKDIR /app\nRUN npm install --omit=dev',
  },
  {
    name: 'Caddyfile 去掉 SSE 的 flush_interval',
    file: 'deploy/Caddyfile',
    from: '\t\tflush_interval -1\n',
    to: '',
  },
  {
    name: 'nginx 去掉 proxy_buffering off',
    file: 'deploy/nginx.conf.example',
    from: '        proxy_buffering off;\n',
    to: '',
  },
  {
    name: 'systemd unit 去掉 NoNewPrivileges',
    file: 'deploy/safeta-ai-backend.service',
    from: 'NoNewPrivileges=true\n',
    to: '',
  },
  {
    name: '.dockerignore 放行 .env',
    file: '.dockerignore',
    from: '.env\n.env.*\n',
    to: '',
  },
];

function digest(text) {
  return createHash('sha256').update(text).digest('hex').slice(0, 16);
}

console.log(`部署护栏变异验证（共 ${MUTATIONS.length} 条）\n`);

let effective = 0;
let problems = 0;

for (const mutation of MUTATIONS) {
  const path = `${SERVER_DIR}${mutation.file}`;
  const original = fs.readFileSync(path, 'utf8');
  const originalDigest = digest(original);

  if (original.indexOf(mutation.from) < 0) {
    console.log(`失效  ${mutation.name}`);
    console.log(`        找不到要替换的片段——${mutation.file} 已改动，请更新本脚本`);
    problems++;
    continue;
  }

  let wentRed = false;
  try {
    fs.writeFileSync(path, original.replace(mutation.from, mutation.to), 'utf8');
    const result = spawnSync(process.execPath, ['--test', TEST_FILE], {
      cwd: SERVER_DIR,
      encoding: 'utf8',
    });
    wentRed = result.status !== 0;
  } finally {
    fs.writeFileSync(path, original, 'utf8');
  }

  if (digest(fs.readFileSync(path, 'utf8')) !== originalDigest) {
    console.log(`严重  ${mutation.file} 没能还原，请检查 git diff 后手动恢复`);
    process.exit(1);
  }

  if (wentRed) {
    console.log(`有效  ${mutation.name}  → 改坏后 deploy.test.js 变红`);
    effective++;
  } else {
    console.log(`无效  ${mutation.name}  → 改坏后测试仍然全绿，这条护栏是假的`);
    problems++;
  }
}

console.log(`\n${effective}/${MUTATIONS.length} 条护栏经得起变异验证`);
if (problems > 0) {
  console.log(`${problems} 条有问题——护栏不可信，请修 deploy.test.js 或更新上面的替换片段。`);
  process.exit(1);
}

/*
 * 部署产物的结构护栏。
 *
 * 为什么需要它：Dockerfile / compose / 反代配置 / systemd unit **一行都不会被单元测试碰到**，
 * 但它们恰恰是最容易被「顺手改坏」的东西——删掉 `cap_drop`、去掉 `flush_interval -1`、
 * 把 `read_only` 改成 false，本地跑起来一切正常，问题要到线上才发作。
 * 这里给它们加上断言，改动时至少会红一次。
 *
 * 为什么自带一个 YAML 解析器：本项目**零 npm 依赖**（持有凭据的组件不进供应链），
 * 所以不能引 yaml 包。改用只覆盖本文件所需子集的解析器，并给它配自测——
 * 自测的意义在于：解析器自己写错时会先红，不会给出「看起来全绿」的假结论。
 * （实际开发中它确实抓到过一次递归层级 bug。）
 *
 * docker / caddy / nginx 不在开发机上，所以这里验的是**结构与关键指令存在**，
 * 不是「能否真的构建」。真机构建仍需在目标机器上跑一次。
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';

function read(relativePath) {
  return fs.readFileSync(fileURLToPath(new URL(`../${relativePath}`, import.meta.url)), 'utf8');
}

// ---------------------------------------------------------------- YAML 子集解析器

function stripTrailingComment(line) {
  let quote = null;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (quote) {
      if (ch === '\\' && quote === '"') {
        i++;
        continue;
      }
      if (ch === quote) {
        quote = null;
      }
      continue;
    }
    if (ch === '"' || ch === "'") {
      quote = ch;
      continue;
    }
    if (ch === '#' && i > 0 && /\s/.test(line[i - 1])) {
      return line.slice(0, i).trimEnd();
    }
  }
  return line;
}

function unquote(value) {
  if (value.length >= 2) {
    const first = value[0];
    if (first === value[value.length - 1] && (first === '"' || first === "'")) {
      const inner = value.slice(1, -1);
      return first === '"' ? inner.replace(/\\"/g, '"').replace(/\\\\/g, '\\') : inner;
    }
  }
  return value;
}

function coerce(value) {
  if (value === 'true') {
    return true;
  }
  if (value === 'false') {
    return false;
  }
  return value === '' ? '' : unquote(value);
}

/** 键里不含冒号；分隔符只认 `: ` 与行尾的 `:`。 */
function splitKey(content) {
  if (content.endsWith(':')) {
    return { key: content.slice(0, -1).trim(), value: null };
  }
  const at = content.indexOf(': ');
  if (at >= 0) {
    return { key: content.slice(0, at).trim(), value: content.slice(at + 2).trim() };
  }
  return null;
}

export function parseYamlSubset(text, label = 'input') {
  const root = {};
  // 每个栈项代表一个容器；indent = **该容器里键所在**的层级（不是子的层级）。
  // 若把子的层级记在这里，同级兄弟键会被错误弹出——这个坑踩过一次。
  const stack = [{ indent: 0, container: root, isArray: false, pendingKey: null }];

  text.split(/\r?\n/).forEach((raw, index) => {
    const lineNo = index + 1;
    if (/^\s*$/.test(raw)) {
      return;
    }
    const trimmed = raw.trimStart();
    if (trimmed.startsWith('#')) {
      return;
    }

    const indentPart = raw.slice(0, raw.length - trimmed.length);
    assert.ok(!indentPart.includes('\t'), `${label}:${lineNo} 缩进用了 Tab，YAML 不允许`);
    assert.equal(indentPart.length % 2, 0, `${label}:${lineNo} 缩进不是 2 的倍数`);

    const indent = indentPart.length;
    const content = stripTrailingComment(trimmed);
    if (content.length === 0) {
      return;
    }

    while (stack.length > 1 && stack[stack.length - 1].indent > indent) {
      stack.pop();
    }
    let top = stack[stack.length - 1];

    if (indent > top.indent) {
      assert.notEqual(top.pendingKey, null, `${label}:${lineNo} 意外缩进`);
      const isSeq = content.startsWith('- ');
      const child = isSeq ? [] : {};
      top.container[top.pendingKey] = child;
      top.pendingKey = null;
      stack.push({ indent, container: child, isArray: isSeq, pendingKey: null });
      top = stack[stack.length - 1];
    } else if (top.pendingKey !== null) {
      // 同级新键到来，说明上一个键是空值
      top.container[top.pendingKey] = null;
      top.pendingKey = null;
    }

    if (content.startsWith('- ')) {
      assert.ok(top.isArray, `${label}:${lineNo} 序列项出现在非序列层级`);
      top.container.push(coerce(content.slice(2).trim()));
      return;
    }

    const pair = splitKey(content);
    assert.ok(pair, `${label}:${lineNo} 不是合法的「键: 值」：${content}`);
    if (pair.value === null) {
      top.pendingKey = pair.key;
      return;
    }
    top.container[pair.key] = coerce(pair.value);
  });

  for (const entry of stack) {
    if (entry.pendingKey !== null) {
      entry.container[entry.pendingKey] = null;
    }
  }
  return root;
}

function has(object, key) {
  return Object.prototype.hasOwnProperty.call(object, key);
}

// ---------------------------------------------------------------- 解析器自测

test('YAML 子集解析器自测（解析器自身错了，下面的结论就不可信）', () => {
  const cases = [
    {
      name: '嵌套映射与序列',
      text: 'a:\n  b: 1\n  c:\n    - x\n    - y\nd: true\n',
      check: (r) => r.a.b === '1' && r.a.c.length === 2 && r.a.c[1] === 'y' && r.d === true,
    },
    {
      name: '同级兄弟键归到同一容器（曾经的递归 bug）',
      text: 'a:\n  b: 1\n  c:\n    - x\n  d: 2\n',
      check: (r) => r.a.b === '1' && r.a.c[0] === 'x' && r.a.d === '2',
    },
    {
      name: '空值键记为 null',
      text: 'volumes:\n  one:\n  two:\n',
      check: (r) => has(r.volumes, 'one') && r.volumes.one === null && r.volumes.two === null,
    },
    {
      name: '文件末尾的空值键也记为 null',
      text: 'a: 1\nb:\n',
      check: (r) => r.a === '1' && r.b === null,
    },
    {
      name: '行尾注释不污染值',
      text: 'a: 1 # 注释\nb:\n  - x # 另一个\n',
      check: (r) => r.a === '1' && r.b[0] === 'x',
    },
    {
      name: '引号包住的冒号不当分隔符',
      text: 'ports:\n  - "127.0.0.1:8787:8787"\n',
      check: (r) => r.ports[0] === '127.0.0.1:8787:8787',
    },
    {
      name: '冒号后无空格的值原样保留',
      text: 'cmd: no-new-privileges:true\n',
      check: (r) => r.cmd === 'no-new-privileges:true',
    },
  ];

  for (const item of cases) {
    const parsed = parseYamlSubset(item.text, '自测');
    assert.ok(item.check(parsed), `${item.name} 结构不符：${JSON.stringify(parsed)}`);
  }

  // 该抛的一定要抛，否则"能拒绝坏输入"这件事就没人验
  const rejected = [
    { name: 'Tab 缩进', text: 'a:\n\tb: 1\n' },
    { name: '奇数缩进', text: 'a:\n   b: 1\n' },
    { name: '缺冒号', text: 'a:\n  b 1\n' },
    { name: '无来由的缩进', text: 'a: 1\n  b: 2\n' },
  ];
  for (const item of rejected) {
    assert.throws(() => parseYamlSubset(item.text, '自测'), undefined, `${item.name} 本该被拒绝`);
  }
});

// ---------------------------------------------------------------- compose

test('docker-compose 结构正确且安全默认值都在', () => {
  const doc = parseYamlSubset(read('docker-compose.yml'), 'docker-compose.yml');
  const api = doc.services.api;
  const caddy = doc.services.caddy;

  assert.ok(api, '缺少 api 服务');
  assert.ok(caddy, '缺少 caddy 服务');
  assert.equal(api.build, '.');
  assert.equal(api.restart, 'unless-stopped');
  assert.ok(Array.isArray(api.env_file) && api.env_file[0] === '.env',
    'api 必须从 .env 读环境变量');
  assert.equal(api.environment.PORT, '8787');
});

test('compose 不允许把 API 直接暴露到公网', () => {
  const doc = parseYamlSubset(read('docker-compose.yml'), 'docker-compose.yml');
  const ports = doc.services.api.ports;
  assert.deepEqual(ports, ['127.0.0.1:8787:8787'],
    'api 端口必须只绑回环，对外一律走反代');
});

test('compose 保留了容器加固项', () => {
  const doc = parseYamlSubset(read('docker-compose.yml'), 'docker-compose.yml');
  const api = doc.services.api;
  assert.equal(api.read_only, true, '进程不写文件，根文件系统应只读');
  assert.deepEqual(api.tmpfs, ['/tmp']);
  assert.deepEqual(api.cap_drop, ['ALL']);
  assert.deepEqual(api.security_opt, ['no-new-privileges:true']);
  assert.equal(api.init, true, '需要 PID 1 转发信号，配合优雅关闭');
  assert.equal(api.stop_grace_period, '20s', '要给在途的流式回答留收尾时间');
});

test('compose 给日志加了轮转上限', () => {
  const doc = parseYamlSubset(read('docker-compose.yml'), 'docker-compose.yml');
  const logging = doc.services.api.logging;
  assert.equal(logging.driver, 'json-file');
  assert.equal(logging.options['max-size'], '10m');
  assert.ok(has(logging.options, 'max-file'));
});

test('compose 里 api 有健康检查且打的是 /health', () => {
  const doc = parseYamlSubset(read('docker-compose.yml'), 'docker-compose.yml');
  const healthcheck = doc.services.api.healthcheck;
  assert.ok(Array.isArray(healthcheck.test));
  assert.ok(healthcheck.test.join(' ').indexOf('/health') >= 0);
});

test('caddy 服务挂对了配置并持久化证书', () => {
  const doc = parseYamlSubset(read('docker-compose.yml'), 'docker-compose.yml');
  const caddy = doc.services.caddy;
  assert.deepEqual(caddy.profiles, ['tls'], 'caddy 应是可选 profile');
  assert.ok(caddy.ports.indexOf('80:80') >= 0);
  assert.ok(caddy.ports.indexOf('443:443') >= 0);
  assert.equal(caddy.depends_on.api.condition, 'service_healthy');
  assert.equal(caddy.volumes[0], './deploy/Caddyfile:/etc/caddy/Caddyfile:ro');
  assert.equal(caddy.volumes[1], 'caddy_data:/data',
    '证书状态必须持久化，否则每次重建都重新申请，会撞频率限制');
  assert.ok(has(doc.volumes, 'caddy_data'));
  assert.ok(has(doc.volumes, 'caddy_config'));
});

// ---------------------------------------------------------------- Dockerfile

test('Dockerfile 不引入任何依赖安装步骤（零依赖是刻意的）', () => {
  const dockerfile = read('Dockerfile');
  assert.equal((dockerfile.match(/^FROM\s+(\S+)/m) || [])[1], 'node:22-alpine');
  // 只扫**代码行**：注释里写着「这里没有 npm install」，
  // 拿整份文件去匹配就会命中注释里的散文（本项目踩过同一个坑，见 MEMORY.md）。
  const code = dockerfile.split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0 && !line.startsWith('#'))
    .join('\n');
  assert.equal(code.split(/\r?\n/).some((line) => /^RUN\b/i.test(line)), false,
    '一旦出现 RUN npm install，零依赖这条底线就破了');
  assert.equal(/npm\s+(install|ci)/i.test(code), false,
    '代码里不该出现 npm install');
});

test('Dockerfile 以非 root 运行且能被探活', () => {
  const dockerfile = read('Dockerfile');
  const instructions = dockerfile.split(/\r?\n/)
    .map((line) => line.trim().toUpperCase())
    .filter((line) => line.length > 0 && !line.startsWith('#'));
  assert.ok(instructions.includes('USER NODE'), '必须以 node 用户运行');
  assert.ok(instructions.includes('EXPOSE 8787'));
  assert.ok(instructions.some((line) => line.startsWith('HEALTHCHECK')));
  assert.ok(dockerfile.indexOf('/health') >= 0, '健康检查要打 /health');
  assert.ok(instructions.some((line) => line.startsWith('ENTRYPOINT')),
    '直接以 node 起进程，少一层 shell 才能收到 SIGTERM');
});

test('.dockerignore 把密钥与测试挡在构建上下文之外', () => {
  const lines = read('.dockerignore')
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0 && !line.startsWith('#'));
  assert.ok(lines.includes('.env'), '密钥绝不能进镜像层');
  assert.ok(lines.includes('.env.*'));
  assert.ok(lines.includes('!.env.example'));
  assert.ok(lines.includes('node_modules'));
  assert.ok(lines.includes('test'));
});

// ---------------------------------------------------------------- 反向代理

test('Caddyfile 反代到 api 服务并关掉响应缓冲', () => {
  const caddyfile = read('deploy/Caddyfile');
  assert.ok(caddyfile.indexOf('reverse_proxy api:8787') >= 0);
  assert.ok(caddyfile.indexOf('flush_interval -1') >= 0,
    '少了这一行，SSE 会被攒着整段发，流式体验全毁');
});

test('nginx 示例保留了流式必需的三行与 body 上限', () => {
  const nginx = read('deploy/nginx.conf.example');
  assert.ok(nginx.indexOf('proxy_pass http://127.0.0.1:8787') >= 0);
  assert.ok(nginx.indexOf('proxy_buffering off;') >= 0);
  assert.ok(nginx.indexOf('X-Accel-Buffering no') >= 0);
  assert.ok(nginx.indexOf('proxy_cache off;') >= 0);
  assert.ok(nginx.indexOf('client_max_body_size 1m;') >= 0,
    '要和后端 MAX_BODY_BYTES（1 MiB）对齐');
  assert.ok(nginx.indexOf('return 301 https://') >= 0, '明文一律跳 HTTPS');
});

// ---------------------------------------------------------------- systemd

test('systemd unit 用 root 属主的 EnvironmentFile 注入密钥', () => {
  const unit = read('deploy/safeta-ai-backend.service');
  assert.ok(unit.indexOf('EnvironmentFile=/etc/safeta-ai-backend.env') >= 0);
  assert.ok(unit.indexOf('User=safeta') >= 0, '不能以 root 跑');
  assert.ok(unit.indexOf('KillSignal=SIGTERM') >= 0);
  assert.ok(unit.indexOf('TimeoutStopSec=20s') >= 0);
});

test('systemd unit 保留了沙箱加固项', () => {
  const unit = read('deploy/safeta-ai-backend.service');
  for (const directive of [
    'NoNewPrivileges=true',
    'ProtectSystem=strict',
    'ProtectHome=true',
    'PrivateTmp=true',
    'PrivateDevices=true',
    'RestrictAddressFamilies=AF_INET AF_INET6',
    'SystemCallFilter=@system-service',
    'RestrictSUIDSGID=true',
  ]) {
    assert.ok(unit.indexOf(directive) >= 0, `缺少加固项 ${directive}`);
  }
  assert.ok(/^CapabilityBoundingSet=\s*$/m.test(unit), 'capability 应被清空');
  assert.ok(/^AmbientCapabilities=\s*$/m.test(unit));
});

// ---------------------------------------------------------------- Windows 自启

function scriptPath(relativePath) {
  return fileURLToPath(new URL(`../${relativePath}`, import.meta.url));
}

/**
 * 只留 PowerShell 的**代码行**。
 *
 * 两份脚本的头部注释里都在讲「托管 node 在带版本号的目录里」，含 `22.22.2-3` 这种字样。
 * 拿整份文件去断言「不许出现版本号」会命中注释里的散文——项目里踩过同一个坑
 * （见 Dockerfile 那条测试的注释）。
 */
function psCode(text) {
  return text
    .replace(/<#[\s\S]*?#>/g, '')
    .split(/\r?\n/)
    .map((line) => line.replace(/\s*#.*$/, ''))
    .filter((line) => line.trim().length > 0)
    .join('\n');
}

test('PowerShell 脚本必须带 UTF-8 BOM', () => {
  // Windows PowerShell 5.1 读无 BOM 的文件时按系统 ANSI 代码页解码，
  // 脚本里的中文会全部变成乱码——而且**只在运行时才看得出来**，
  // 编辑器里一切正常。BOM 是隐形的，谁用别的编辑器另存一次就可能丢。
  for (const name of ['scripts/serve.ps1', 'scripts/manage-autostart.ps1']) {
    const bytes = fs.readFileSync(scriptPath(name));
    assert.deepEqual(
      [bytes[0], bytes[1], bytes[2]],
      [0xef, 0xbb, 0xbf],
      `${name} 缺少 UTF-8 BOM，PS 5.1 下中文会乱码`,
    );
  }
});

test('自启任务的三个关键设置不能丢', () => {
  const code = psCode(read('scripts/manage-autostart.ps1'));

  assert.ok(code.indexOf('-AtLogOn') >= 0, '应当是登录触发');
  assert.ok(code.indexOf("$trigger.Delay = 'PT30S'") >= 0,
    '登录后要延迟 30 秒：服务一起来就要出网连厂商，太早可能还没网');
  assert.ok(code.indexOf('-MultipleInstances IgnoreNew') >= 0,
    '重复登录 / RDP 重连不该起第二份');
  assert.ok(code.indexOf('-RunLevel Limited') >= 0,
    '这个服务不需要管理员权限');
  assert.ok(
    code.indexOf('-ExecutionTimeLimit (New-TimeSpan -Seconds 0)') >= 0,
    'ExecutionTimeLimit 必须是不限时：任务计划默认 3 天，服务会在第 4 天静默死掉',
  );
});

test('自启任务调用的运行器真实存在', () => {
  const code = psCode(read('scripts/manage-autostart.ps1'));
  assert.ok(code.indexOf("'serve.ps1'") >= 0, '任务要指向 serve.ps1');
  assert.ok(fs.existsSync(scriptPath('scripts/serve.ps1')),
    'manage-autostart.ps1 引用的 serve.ps1 不存在，任务会装上一个跑不起来的东西');
});

test('运行器不把密钥值写进日志', () => {
  const lines = read('scripts/serve.ps1').split(/\r?\n/);
  const leaking = lines.filter((line) =>
    line.indexOf('Write-Log') >= 0
    && /(CHAT_API_KEY|EMBEDDING_API_KEY|APP_TOKEN)/.test(line)
    // 唯一允许提到 APP_TOKEN 的地方：报「它为空、鉴权已关闭」这个状态。
    && line.indexOf('APP_TOKEN is empty') < 0);
  assert.deepEqual(leaking, [],
    '日志会长期留存在磁盘上，绝不能出现密钥的值（只允许报它是否为空）');
});

test('运行器不写死 node 的版本目录', () => {
  const code = psCode(read('scripts/serve.ps1'));
  assert.equal(/\d+\.\d+\.\d+/.test(code), false,
    '托管 node 在带版本号的目录里，写死路径会在下次升级后静默失效，应当自动探测');
  assert.ok(code.indexOf('SAFETA_NODE') >= 0, '要留一个显式覆盖的口子');
});

test('运行器：端口被占时不重复启动，并自己滚动日志', () => {
  const code = psCode(read('scripts/serve.ps1'));
  assert.ok(code.indexOf('Get-NetTCPConnection') >= 0 && code.indexOf('already listening') >= 0,
    '端口已在监听时应当直接退出，而不是让 node 抛 EADDRINUSE');
  assert.ok(code.indexOf('Rotate-Log') >= 0 && code.indexOf('MaxLogBytes') >= 0,
    '日志要长期追加，必须自带滚动上限');
  assert.ok(code.indexOf('cmd.exe /c') >= 0,
    '重定向必须交给 cmd.exe：PowerShell 自己重定向会重新编码，把 UTF-8 日志变成乱码');
});

test('.gitignore 挡掉自启的运行日志目录', () => {
  const lines = read('../.gitignore')
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0 && !line.startsWith('#'));
  assert.ok(lines.includes('server/logs/'),
    'server/logs/ 是运行时产物且会无限增长，不该进仓库');
});

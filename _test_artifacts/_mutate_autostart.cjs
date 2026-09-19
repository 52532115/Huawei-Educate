/*
 * 对 Windows 自启的护栏断言做变异验证。
 *
 * 静态检查（"文件里有没有这行字"）极易写成恒真断言：写错了、匹配错了、
 * 或者被断言的东西早就不在了，它照样全绿。唯一能证明它有效的方法是
 * **故意改坏源码**，看它是否真的变红。
 *
 * 每个变异都按字节备份、按字节还原，跑完必须与原始内容逐字节一致。
 */

const fs = require('node:fs');
const { execFileSync } = require('node:child_process');

const NODE = 'C:/Users/Messi/.workbuddy/binaries/node/versions/22.22.2-3/node.exe';
const SERVER = 'D:/Education_Framework_Code_V1/server';

const mutants = [
  {
    name: 'ExecutionTimeLimit 改成 3 天（默认值，服务会在第 4 天静默死掉）',
    file: 'D:/Education_Framework_Code_V1/server/scripts/manage-autostart.ps1',
    from: '-ExecutionTimeLimit (New-TimeSpan -Seconds 0)',
    to: '-ExecutionTimeLimit (New-TimeSpan -Days 3)',
  },
  {
    name: '触发方式改成开机（没有密码/SYSTEM 时任务根本不会跑）',
    file: 'D:/Education_Framework_Code_V1/server/scripts/manage-autostart.ps1',
    from: '-AtLogOn',
    to: '-AtStartup',
  },
  {
    name: 'MultipleInstances 改成 Parallel（重复登录会起第二份）',
    file: 'D:/Education_Framework_Code_V1/server/scripts/manage-autostart.ps1',
    from: '-MultipleInstances IgnoreNew',
    to: '-MultipleInstances Parallel',
  },
  {
    name: '去掉 serve.ps1 的 UTF-8 BOM（PS 5.1 下中文全乱码）',
    file: 'D:/Education_Framework_Code_V1/server/scripts/serve.ps1',
    stripBom: true,
  },
  {
    name: '把密钥值写进日志',
    file: 'D:/Education_Framework_Code_V1/server/scripts/serve.ps1',
    from: 'Write-Log "port     : $port"',
    to: 'Write-Log "key      : $env:CHAT_API_KEY"',
  },
  {
    name: '重定向改回 PowerShell 原生（日志被重新编码成乱码）',
    file: 'D:/Education_Framework_Code_V1/server/scripts/serve.ps1',
    from: '& cmd.exe /c $commandLine',
    to: '& $node $Entry >> $LogFile 2>&1',
  },
  {
    name: '.gitignore 不再忽略 logs 目录',
    file: 'D:/Education_Framework_Code_V1/.gitignore',
    from: 'server/logs/',
    to: 'server/logs-are-fine/',
  },
  {
    // 2026-09-19 真实事故：服务被中断后停在 Ready，端口无人监听，-RestartCount 没救回来。
    name: '注册时漏掉看门狗触发器（服务一死就永久停在 Ready，要等下次登录）',
    file: 'D:/Education_Framework_Code_V1/server/scripts/manage-autostart.ps1',
    from: '-Trigger @($logonTrigger, $watchdogTrigger)',
    to: '-Trigger @($logonTrigger)',
  },
  {
    // 实测踩到的那个：挂得上去、读得回来、永不触发。
    name: '把重复挂到登录触发器上（装得像成功，但在已登录的会话里永不触发）',
    file: 'D:/Education_Framework_Code_V1/server/scripts/manage-autostart.ps1',
    from: "    $logonTrigger.Delay = 'PT30S'",
    to: "    $logonTrigger.Delay = 'PT30S'\n    $logonTrigger.Repetition = $watchdogTrigger.Repetition",
  },
  {
    name: '给重复加上有限时长（看门狗 30 天后静默停止，与 ExecutionTimeLimit 同类坑）',
    file: 'D:/Education_Framework_Code_V1/server/scripts/manage-autostart.ps1',
    from: '-RepetitionInterval (New-TimeSpan -Minutes $WatchdogMinutes)',
    to: '-RepetitionInterval (New-TimeSpan -Minutes $WatchdogMinutes) -RepetitionDuration (New-TimeSpan -Days 30)',
  },
  {
    name: '看门狗间隔默认值改成 0（不重复 / 被拒）',
    file: 'D:/Education_Framework_Code_V1/server/scripts/manage-autostart.ps1',
    from: '[int]$WatchdogMinutes = 5',
    to: '[int]$WatchdogMinutes = 0',
  },
  {
    name: '删掉 serve.ps1 的端口守卫（看门狗的幂等前提没了，每个周期会再起一份）',
    file: 'D:/Education_Framework_Code_V1/server/scripts/serve.ps1',
    from: 'nothing to do.',
    to: 'still starting anyway.',
  },
  {
    // 实测踩到：Register-ScheduledTask 失败是非终止错误，脚本继续往下跑并打印"已安装"。
    name: '去掉安装后的回读确认（注册失败也会报"已安装"）',
    file: 'D:/Education_Framework_Code_V1/server/scripts/manage-autostart.ps1',
    from: '    if (-not (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)) {',
    to: '    if ($false) {',
  },
];

function runDeployTests() {
  let out = '';
  try {
    out = execFileSync(NODE, ['--test', 'test/deploy.test.js'], {
      cwd: SERVER,
      encoding: 'utf8',
      timeout: 120000,
    });
  } catch (error) {
    out = (error.stdout || '') + (error.stderr || '');
  }
  const clean = out.replace(/\u001b\[[0-9;]*m/g, '');
  const lines = clean.split(/\r?\n/);
  const failed = lines.filter((l) => /^not ok /.test(l)).map((l) => l.replace(/^not ok \d+ - /, ''));
  return { failed };
}

let pass = 0;
let fail = 0;

for (const mutant of mutants) {
  const original = fs.readFileSync(mutant.file);
  try {
    if (mutant.stripBom) {
      if (!(original[0] === 0xef && original[1] === 0xbb && original[2] === 0xbf)) {
        console.log(`  !! ${mutant.name}: 文件本来就没有 BOM，变异无意义`);
        fail++;
        continue;
      }
      fs.writeFileSync(mutant.file, original.subarray(3));
    } else {
      const text = original.toString('utf8');
      if (text.indexOf(mutant.from) < 0) {
        console.log(`  !! ${mutant.name}: 找不到待替换片段，变异无意义`);
        fail++;
        continue;
      }
      fs.writeFileSync(mutant.file, text.replace(mutant.from, mutant.to), 'utf8');
    }

    const { failed } = runDeployTests();
    if (failed.length > 0) {
      console.log(`  OK  ${mutant.name}`);
      console.log(`        -> 变红 ${failed.length} 条: ${failed.join(' / ')}`);
      pass++;
    } else {
      console.log(`  XX  ${mutant.name}  <-- 改坏了却全绿，这条断言是恒真的`);
      fail++;
    }
  } finally {
    fs.writeFileSync(mutant.file, original);
    const restored = fs.readFileSync(mutant.file);
    if (!restored.equals(original)) {
      console.log(`  !! 还原失败: ${mutant.file}`);
      process.exitCode = 1;
    }
  }
}

console.log('');
console.log(`变异验证: ${pass}/${mutants.length} 按预期变红，${fail} 条失效`);
if (fail > 0) {
  process.exitCode = 1;
}

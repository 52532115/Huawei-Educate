/*
 * 对「后端配置重启后丢失」的修复做变异验证。
 *
 * 这条修复的全部价值在于"接线"：配置本来就被写进文件，只是从来没人读回来。
 * 而原先的测试断言的是 AiBackendStore().load()（App 从不调用的方法），
 * 所以它一直是绿的 —— 典型的"测了零件，没测接线"。
 *
 * 因此这里要证明新断言**能**抓住接线断掉：把 current() 退回"只读内存"、
 * 把 load() 的"回写 AppStorage"去掉，各自必须让对应的那条断言变红。
 *
 * 每个变异按字节备份、按字节还原，跑完必须与原始内容逐字节一致。
 */

const fs = require('node:fs');
const { execFileSync } = require('node:child_process');

const NODE = 'C:/Users/Messi/.workbuddy/binaries/node/versions/22.22.2-3/node.exe';
const ROOT = 'D:/Education_Framework_Code_V1';
const RESULT_JSON = ROOT + '/_test_artifacts/ai_agent_p4_test_result.json';

const mutants = [
  {
    name: 'current() 退回旧行为：只读 AppStorage（内存态），不读持久化文件',
    file: ROOT + '/features/aiagent/src/main/ets/service/AiBackend.ets',
    from: '    return new AiBackendStore().load();',
    to: '    let url = \'\';\n'
      + '    let token = \'\';\n'
      + '    try {\n'
      + '      url = AppStorage.get(\'aiBackendUrl\') || \'\';\n'
      + '      token = AppStorage.get(\'aiBackendToken\') || \'\';\n'
      + '    } catch (e) {\n'
      + '      url = \'\';\n'
      + '      token = \'\';\n'
      + '    }\n'
      + '    return new AiBackend(url, token);',
    expect: '重启后 current()',
  },
  {
    name: 'load() 从文件恢复后不回写 AppStorage（配置生效但设置面板显示空）',
    file: ROOT + '/features/aiagent/src/main/ets/service/AiBackend.ets',
    from: '    const persisted = this.readFile();\n'
      + '    this.writeSetting(BACKEND_URL_KEY, persisted.getBaseUrl());\n'
      + '    this.writeSetting(BACKEND_TOKEN_KEY, persisted.getToken());\n'
      + '    return persisted;',
    to: '    return this.readFile();',
    expect: '恢复后回写 AppStorage',
  },
];

function runP4() {
  try {
    execFileSync(NODE, ['_test_artifacts/ai_agent_p4_test.cjs'], {
      cwd: ROOT,
      encoding: 'utf8',
      timeout: 180000,
    });
  } catch (error) {
    // 有断言失败时脚本会以非 0 退出，结果照旧写在 JSON 里。
  }
  const results = JSON.parse(fs.readFileSync(RESULT_JSON, 'utf8'));
  return results.filter((r) => r.status === 'FAIL').map((r) => r.name);
}

let pass = 0;
let fail = 0;

for (const mutant of mutants) {
  const original = fs.readFileSync(mutant.file);
  try {
    const text = original.toString('utf8');
    if (text.indexOf(mutant.from) < 0) {
      console.log(`  !! ${mutant.name}: 找不到待替换片段，变异无意义`);
      fail++;
      continue;
    }
    fs.writeFileSync(mutant.file, text.replace(mutant.from, mutant.to), 'utf8');

    const failed = runP4();
    const hit = failed.filter((n) => n.indexOf(mutant.expect) >= 0);
    if (hit.length > 0) {
      console.log(`  OK  ${mutant.name}`);
      console.log(`        -> 变红 ${failed.length} 条，命中目标: ${hit.join(' / ')}`);
      pass++;
    } else {
      console.log(`  XX  ${mutant.name}  <-- 改坏了却没让目标断言变红，这条断言抓不住它`);
      console.log(`        失败用例: ${failed.length ? failed.join(' / ') : '(全绿)'}`);
      fail++;
    }
  } finally {
    fs.writeFileSync(mutant.file, original);
    if (!fs.readFileSync(mutant.file).equals(original)) {
      console.log(`  !! 还原失败: ${mutant.file}`);
      process.exitCode = 1;
    }
  }
}

console.log('');
console.log(`变异验证: ${pass}/${mutants.length} 按预期变红，${fail} 条失效`);
console.log('（跑完的还原是逐字节比对过的）');
if (fail > 0) {
  process.exitCode = 1;
}

/*
 * 对「换一组轮换 + 确定性错题 id」这一轮改动的变异验证。
 *
 * 这轮修的两件事都属于**静默失效型**：
 *   1. "换一组"原本只有错题本层看跳过列表，画像层与题库层每次从头扫 ——
 *      没有错题时点多少次都得到同一组六道。它**不报错、不崩、日志干净**，
 *      只有"按钮看起来没用"这一个症状，所以必须有断言盯着。
 *   2. 错题记录 id 原本带 Math.random() 后缀 —— 违反"service 层不用随机数"，
 *      代价是这条写入路径**永远断言不了**（每次跑都是新 id）。
 *
 * 变异要盯住三类容易写成恒真的地方：
 *   - 「传入已出的 id 会得到不同的一组」：如果只改一层，另一层就把重复题端回来，
 *     所以画像层与题库层各要一条变异（第 1、2 条）；
 *   - 「还有真题时不出提示卡」：提示卡只要抢在题库层前面，断言就会变绿得莫名其妙，
 *     但学习者看到的是一张假题（第 3 条）；
 *   - 「跳过列表会重置」：只增不减时服务端的兜底仍会返回满 6 题，
 *     前三轮看不出任何差别，只有第四轮才暴露（第 9 条）。
 *
 * 每个变异按字节备份、按字节还原，跑完逐字节比对。
 */

const fs = require('node:fs');
const { execFileSync } = require('node:child_process');

const NODE = 'C:/Users/Messi/.workbuddy/binaries/node/versions/22.22.2-3/node.exe';
const ROOT = 'D:/Education_Framework_Code_V1';
const SERVICE = ROOT + '/features/aiagent/src/main/ets/service/AdaptivePracticeService.ets';
const VIEWMODEL = ROOT + '/features/aiagent/src/main/ets/viewmodel/AdaptivePracticeViewModel.ets';

const mutants = [
  {
    name: '题库层不再跳过已出的题（题库有 12 道，第二组会把第一组原样端回来）',
    file: SERVICE,
    suite: 'p6',
    from: '      if (excludeIds.indexOf(bank[i].id) < 0 && draft.usedIds.indexOf(bank[i].id) < 0 &&\n'
      + '        !this.containsTitle(draft.usedTitles, bank[i].title)) {',
    to: '      if (draft.usedIds.indexOf(bank[i].id) < 0 &&\n'
      + '        !this.containsTitle(draft.usedTitles, bank[i].title)) {',
    expect: '传入这一组的 6 个 id 后返回另一组 6 题',
  },
  {
    name: '画像层不再跳过已出的题（冷启动三个默认画像各只有一道题，必然重现）',
    file: SERVICE,
    suite: 'p6',
    from: '      if (usedIds.indexOf(bank[i].id) < 0 && excludeIds.indexOf(bank[i].id) < 0 &&\n'
      + '        bank[i].knowledgeTag === profile.tag) {',
    to: '      if (usedIds.indexOf(bank[i].id) < 0 &&\n'
      + '        bank[i].knowledgeTag === profile.tag) {',
    expect: '传入这一组的 6 个 id 后返回另一组 6 题',
  },
  {
    name: '提示卡抢在题库层前面（本知识点的题这轮用过了，也照样发一张假题）',
    file: SERVICE,
    suite: 'p6',
    from: '    if (this.bankCoversTag(bank, profile.tag)) {\n      return null;\n    }\n',
    to: '    if (false) {\n      return null;\n    }\n',
    expect: '还有真题可出时不出复习提示卡',
  },
  {
    name: '提示卡 id 每调用一次都变（于是永远排除不掉，同一张卡反复出现）',
    file: SERVICE,
    suite: 'p6',
    from: 'const placeholderId = `q_custom_${profile.tag}`;',
    to: 'const placeholderId = `q_custom_${profile.tag}_${Math.random()}`;',
    expect: '题库覆盖不到的知识点仍出提示卡',
  },
  {
    name: '提示卡不看跳过列表（只有 usedIds 生效，换个会话就复活）',
    file: SERVICE,
    suite: 'p6',
    from: '    if (usedIds.indexOf(placeholderId) >= 0 || excludeIds.indexOf(placeholderId) >= 0) {\n'
      + '      return null;\n    }\n',
    to: '    if (usedIds.indexOf(placeholderId) >= 0) {\n      return null;\n    }\n',
    expect: '提示卡同样参与排除',
  },
  {
    name: '去掉 top-up 兜底（题目取尽后给出空组，练习页永远停在"暂无练习题"）',
    file: SERVICE,
    suite: 'p6',
    from: '    if (draft.questions.length < questionCount) {\n'
      + '      this.fillLayers(snapshot, profiles, questionCount, now, [], draft);\n    }\n',
    to: '',
    expect: '题库取尽后回到第一组',
  },
  {
    name: '错题记录 id 用回随机后缀（写入路径重新变成不可断言的）',
    file: SERVICE,
    suite: 'p6',
    from: 'const recordId = `adaptive_${now}_${stableTextHash(titleKey.length > 0 ? titleKey : question.id)}`;',
    to: 'const recordId = `adaptive_${now}_${Math.random().toString(36).substring(2, 8)}`;',
    expect: '追加的错题记录 id 可复现',
  },
  {
    name: 'ViewModel 不把已出的题传下去（回到"只有错题本参与轮换"的旧行为）',
    file: VIEWMODEL,
    suite: 'p5',
    from: 'const next = this.practiceService.generateSession(6, Date.now(), seen);',
    to: 'const next = this.practiceService.generateSession(6, Date.now(), []);',
    expect: '无错题时换一组也给出不同的一组',
  },
  {
    name: '跳过列表只增不减（前三轮看不出差别，从第四轮起永远停在第一组）',
    file: VIEWMODEL,
    suite: 'p5',
    from: 'this.seenQuestionIds = reused ? allIds : seen.concat(fresh);',
    to: 'this.seenQuestionIds = seen.concat(fresh);',
    expect: '跳过列表会随轮换重置',
  },
];

const SUITES = {
  p5: { script: '_test_artifacts/ai_agent_p5_test.cjs', json: ROOT + '/_test_artifacts/ai_agent_p5_test_result.json' },
  p6: { script: '_test_artifacts/ai_agent_p6_test.cjs', json: ROOT + '/_test_artifacts/ai_agent_p6_test_result.json' },
};

function runSuite(suite) {
  const target = SUITES[suite];
  try {
    execFileSync(NODE, [target.script], { cwd: ROOT, encoding: 'utf8', timeout: 300000 });
  } catch (error) {
    // 有断言失败时脚本以非 0 退出，结果照旧写进 JSON。
  }
  const results = JSON.parse(fs.readFileSync(target.json, 'utf8'));
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

    const failed = runSuite(mutant.suite);
    const hit = failed.filter((n) => n.indexOf(mutant.expect) >= 0);
    if (hit.length > 0) {
      console.log(`  OK  [${mutant.suite}] ${mutant.name}`);
      console.log(`        -> 变红 ${failed.length} 条，命中目标: ${hit.join(' / ')}`);
      pass++;
    } else {
      console.log(`  XX  [${mutant.suite}] ${mutant.name}  <-- 改坏了却没让目标断言变红，这条断言抓不住它`);
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

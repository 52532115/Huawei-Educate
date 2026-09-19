/*
 * 对「RAG + LLM 出题」这一轮的变异验证。
 *
 * 这轮的特点决定了变异比平时更要紧：整条链路**失败是静默的**。
 * 出题失败只会让池里没有新题，练习页照常工作 —— 没有报错、没有空态、
 * 日志干净，学习者看到的是"和以前一样的题库题"。所以"改坏了测试仍然是绿的"
 * 在这里极难靠肉眼发现，只能靠把源码改坏、看断言是否真的红。
 *
 * 变异按四类选：
 *   A. 校验被摘掉（选项乱码、答案越界、材料不足、文件版本）——
 *      摘掉后功能"看起来更能出题了"，实际是把错题端给学习者；
 *   B. 确定性与去重的来源被换掉（id 用时钟、池不去重）——
 *      症状是缓存越滚越大、同题反复出现，一期之内根本看不出来；
 *   C. 计数与阈值被放宽（每 tag 上限、覆盖阈值、批量上限）——
 *      代价是钱（每轮都重新生成）或体验（生成题挤掉题库）；
 *   D. 顺序与依赖被挪动（生成层移到画像层之后、指纹读取挪回同步路径）——
 *      前者让新题永远排不上，后者让首帧去解析语料索引。
 *
 * 每个变异按字节备份、按字节还原，跑完逐字节比对。
 */

const fs = require('node:fs');
const { execFileSync } = require('node:child_process');

const NODE = 'C:/Users/Messi/.workbuddy/binaries/node/versions/22.22.2-3/node.exe';
const ROOT = 'D:/Education_Framework_Code_V1';
const SERVICE_DIR = ROOT + '/features/aiagent/src/main/ets/service';
const SYNTH = SERVICE_DIR + '/PracticeQuestionSynthesizer.ets';
const POOL = SERVICE_DIR + '/GeneratedQuestionPool.ets';
const SERVICE = SERVICE_DIR + '/AdaptivePracticeService.ets';
const SCRIPT = ROOT + '/_test_artifacts/ai_agent_p8_test.cjs';

const mutants = [
  // ---------- A. 校验被摘掉 ----------
  {
    name: '乱码选项改为"跳过"而不是整题作废（后续选项下标全体前移，答案会指错）',
    file: SYNTH,
    from: '      if (option.length === 0 || isCorruptedText(option)) {\n        return [];\n      }',
    to: '      if (option.length === 0 || isCorruptedText(option)) {\n        continue;\n      }',
    expect: '选项或解析出现乱码时丢弃该题',
  },
  {
    name: '去掉非对象元素的判空（回复里混一个 null 就崩）',
    file: SYNTH,
    from: '    if (item === null || typeof item !== \'object\' || Array.isArray(item)) {\n      return null;\n    }',
    to: '    if (false) {\n      return null;\n    }',
    expect: null, // 崩溃即算命中
  },
  {
    name: '材料不足的闸门被拆（语料没讲过也照出题，等于让模型编）',
    file: SYNTH,
    from: '    return this.usablePassageChars(passages) >= MIN_MATERIAL_CHARS;',
    to: '    return true;',
    expect: '合计正文不足 80 字时判定材料不足',
  },
  {
    name: '接受数字字符串作为答案下标（0-based 与 1-based 分不清，会把对的判成错的）',
    file: SYNTH,
    from: '        } else if (code >= 97 && code <= 122) {\n          index = code - 97;\n        }',
    to: '        } else if (code >= 97 && code <= 122) {\n          index = code - 97;\n        } else if (code >= 48 && code <= 57) {\n          index = code - 48;\n        }',
    expect: '数字字符串（"1"）被拒绝',
  },
  {
    name: '选项数下限放到 2（两个选项的题也采纳，选择题失去区分度）',
    file: SYNTH,
    from: 'const MIN_OPTION_COUNT = 3;',
    to: 'const MIN_OPTION_COUNT = 2;',
    expect: '选项少于 3 个的题被丢弃',
  },
  {
    name: '出处不再去重不再设上限（把检索到的整批文档都挂到每道题上）',
    file: SYNTH,
    from: '    for (let i = 0; i < passages.length && parts.length < MAX_CITATIONS; i++) {\n      const citation = this.textOf(passages[i].citation);\n      if (citation.length > 0 && !isCorruptedText(citation) && parts.indexOf(citation) < 0) {',
    to: '    for (let i = 0; i < passages.length; i++) {\n      const citation = this.textOf(passages[i].citation);\n      if (citation.length > 0 && !isCorruptedText(citation)) {',
    expect: '出处最多两段且去重',
  },
  {
    name: '文件里的契约版本不校验（旧契约写下的题被当成新契约读取）',
    file: POOL,
    from: '  if (parsed.version !== SYNTHESIS_CONTRACT_VERSION) {\n    return null;\n  }',
    to: '  if (false) {\n    return null;\n  }',
    expect: '文件里的契约版本不匹配时整份丢弃',
  },
  {
    name: '缓存记录不校验题干（空题干的坏记录被当成可用题目取出）',
    file: POOL,
    from: '    if (id.length === 0 || title.length === 0 || options.length < 2) {',
    to: '    if (id.length === 0 || options.length < 2) {',
    expect: '文件损坏或字段缺失时逐项丢弃',
  },

  // ---------- B. 确定性与去重 ----------
  {
    name: '题目 id 改用时钟（同一道题重复生成会不断堆积，缓存永远去不掉重）',
    file: SYNTH,
    from: '      `q_gen_${stableTextHash(`${tag}|${normalizeQuestionTitle(title)}`)}`,',
    to: '      `q_gen_${Date.now()}`,',
    expect: 'id 由知识点与题干派生',
  },
  {
    name: '入池不再按 id 去重（同一批题每轮都能再插一遍）',
    file: POOL,
    from: '      if (question.id.length === 0 || this.hasQuestion(record, question.id)) {\n        continue;\n      }',
    to: '      if (question.id.length === 0) {\n        continue;\n      }',
    expect: '重复入池同一 id 不增加',
  },
  {
    name: '取题直接返回池内对象（会话里的选中/提交状态回写进缓存）',
    file: POOL,
    from: '      const question = this.fromRecord(record.questions[i]);',
    to: '      const question = record.questions[i];',
    expect: '取出的题是副本',
  },

  // ---------- C. 计数与阈值 ----------
  {
    name: '每知识点上限放宽到 100（文件无界增长）',
    file: POOL,
    from: 'export const MAX_QUESTIONS_PER_TAG = 8;',
    to: 'export const MAX_QUESTIONS_PER_TAG = 100;',
    expect: '每个知识点上限',
  },
  {
    name: '知识点数量上限放宽到 1000（任意 tag 都能把池撑大）',
    file: POOL,
    from: 'export const MAX_TAGS = 24;',
    to: 'export const MAX_TAGS = 1000;',
    expect: '知识点数量上限',
  },
  {
    name: '空指纹当成"语料变了"（每次冷启动首帧都清空缓存，等于每轮都重新付费生成）',
    file: POOL,
    from: '    if (fingerprint.length === 0) {\n      return;\n    }',
    to: '    if (false) {\n      return;\n    }',
    expect: '空指纹视为未知',
  },
  {
    name: '覆盖阈值归零（池里已有的知识点每轮都重新生成一遍）',
    file: SERVICE,
    from: 'const COVERED_QUESTION_COUNT = SYNTHESIS_QUESTION_COUNT;',
    to: 'const COVERED_QUESTION_COUNT = 0;',
    expect: '已覆盖的知识点不再请求',
  },
  {
    name: '每知识点取题上限改成 99（生成题挤掉题库的讲解材料）',
    file: SERVICE,
    from: '      const fromPool = this.questionPool.getForTag(profiles[i].tag, skip, 1);',
    to: '      const fromPool = this.questionPool.getForTag(profiles[i].tag, skip, 99);',
    expect: '每个知识点最多贡献一道生成题',
  },
  {
    name: '失败不设锁（没配 Key 或后端不可达时，每轮都重打一次请求）',
    file: SERVICE,
    from: '        this.synthesisBlockedKey = blockKey;\n        this.synthesisLastError = e instanceof Error ? e.message : \'unknown error\';',
    to: '        this.synthesisLastError = e instanceof Error ? e.message : \'unknown error\';',
    expect: '调用失败只试一次',
  },
  {
    name: '去掉材料充足的判定（检索返回什么就拿什么去出题）',
    file: SERVICE,
    from: '    if (!this.synthesizer.isMaterialSufficient(passages)) {\n      return 0;\n    }',
    to: '    if (false) {\n      return 0;\n    }',
    expect: '材料不足时不发请求',
  },

  // ---------- D. 顺序与依赖 ----------
  {
    name: '生成层挪到画像层之后（生成题仍会进会话，但永远排不上，等于白生成）',
    file: SERVICE,
    from: '    this.fillFromPool(profiles, questionCount, excludeIds, draft);\n'
      + '\n'
      + '    for (let i = 0; i < profiles.length && draft.questions.length < questionCount; i++) {\n'
      + '      const question = this.pickQuestionForProfile(profiles[i], draft.usedIds, excludeIds);\n'
      + '      if (question === null || this.containsTitle(draft.usedTitles, question.title)) {\n'
      + '        continue;\n'
      + '      }\n'
      + '      draft.questions.push(question);\n'
      + '      draft.usedIds.push(question.id);\n'
      + '      draft.usedTitles.push(normalizeQuestionTitle(question.title));\n'
      + '    }',
    to: '    for (let i = 0; i < profiles.length && draft.questions.length < questionCount; i++) {\n'
      + '      const question = this.pickQuestionForProfile(profiles[i], draft.usedIds, excludeIds);\n'
      + '      if (question === null || this.containsTitle(draft.usedTitles, question.title)) {\n'
      + '        continue;\n'
      + '      }\n'
      + '      draft.questions.push(question);\n'
      + '      draft.usedIds.push(question.id);\n'
      + '      draft.usedTitles.push(normalizeQuestionTitle(question.title));\n'
      + '    }\n'
      + '\n'
      + '    this.fillFromPool(profiles, questionCount, excludeIds, draft);',
    expect: '池里有题时生成题进入会话',
  },
  {
    name: '指纹读取挪回同步出题路径（首帧就去解析语料索引）',
    file: SERVICE,
    from: '    for (let i = 0; i < profiles.length && draft.questions.length < questionCount; i++) {\n      const skip = excludeIds.concat(draft.usedIds);',
    to: '    this.questionPool.setCorpusFingerprint(this.corpusFingerprint());\n'
      + '    for (let i = 0; i < profiles.length && draft.questions.length < questionCount; i++) {\n      const skip = excludeIds.concat(draft.usedIds);',
    expect: '同步出题路径不解析检索单例',
  },
];

/** Runs p8 and returns { failed: string[], crashed: boolean }. */
function runSuite() {
  let out = '';
  let ok = true;
  try {
    out = execFileSync(NODE, [SCRIPT], { cwd: ROOT, encoding: 'utf8', timeout: 300000 });
  } catch (error) {
    ok = false;
    out = String(error.stdout || '') + String(error.stderr || '');
  }
  const failed = [];
  for (const line of out.split(/\r?\n/)) {
    const match = /^FAIL \[(.+?)\] (.+)$/.exec(line.trim());
    if (match) {
      failed.push(match[2]);
    }
  }
  // A variant can make the suite throw before any assertion runs (a removed
  // guard, for instance). That is a red signal too, just not a named one.
  const crashed = !ok && failed.length === 0;
  return { failed, crashed };
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

    const outcome = runSuite();
    const hit = mutant.expect === null
      ? (outcome.crashed ? ['(整个套件崩溃，无断言可报)'] : [])
      : outcome.failed.filter((n) => n.indexOf(mutant.expect) >= 0);

    if (hit.length > 0) {
      console.log(`  OK  ${mutant.name}`);
      console.log(`        -> 变红 ${outcome.failed.length} 条，命中目标: ${hit.join(' / ')}`);
      pass++;
    } else {
      console.log(`  XX  ${mutant.name}  <-- 改坏了却没让目标断言变红，这条断言抓不住它`);
      console.log(`        失败用例: ${outcome.failed.length ? outcome.failed.join(' / ') : '(全绿)'}`);
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

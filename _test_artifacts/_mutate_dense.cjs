/*
 * 对「稠密检索接线」的变异验证。
 *
 * 这一轮加的东西全部是**降级语义**：向量侧装不上、装错了、或者装好了但没人用，
 * 表现都应该是"退回纯词法"，而不是报错。降级路径天生难测 —— 写错一处，
 * 功能悄悄失效，测试照样全绿。所以每条护栏都必须证明"改坏了它会红"。
 *
 * 特别要盯住三类：
 *   1. 单飞、粘住失败、暖启动不重嵌 —— 这三条是"别重复花钱"的护栏，恒真的话
 *      账单会替你发现问题；
 *   2. 启动路径不得够到嵌入器 —— 原来的写法是"文件里不出现代理类名"，
 *      这只是一种代理指标，本轮门面开始自己决定何时嵌入后它就不成立了，
 *      新写法直接断言可达性，因此必须验证它真的抓得住"预热顺手嵌一把"；
 *   3. 打包编码 —— 退回浮点直存会让排序断言反而**更容易**通过（无损），
 *      所以必须有一条盯着文件结构的断言。
 *
 * 每个变异按字节备份、按字节还原，跑完逐字节比对。
 */

const fs = require('node:fs');
const { execFileSync } = require('node:child_process');

const NODE = 'C:/Users/Messi/.workbuddy/binaries/node/versions/22.22.2-3/node.exe';
const ROOT = 'D:/Education_Framework_Code_V1';
const SERVICE = ROOT + '/features/aiagent/src/main/ets/service/';
const RESULT_JSON = ROOT + '/_test_artifacts/ai_agent_p7_test_result.json';

const mutants = [
  {
    name: '去掉单飞：并发提问各建一份向量（嵌入账单乘以调用者数量）',
    file: SERVICE + 'KnowledgeStore.ets',
    from: '    if (this.densePromise !== null) {\n      return;\n    }\n',
    to: '',
    expect: '并发触发只嵌一份语料',
  },
  {
    name: '不后台建向量：首次提问只做词法，之后永远保持词法',
    file: SERVICE + 'KnowledgeStore.ets',
    from: '      } else {\n        this.startDenseBuild(embedder);\n      }',
    to: '      }',
    expect: '首次提问不等嵌入',
  },
  {
    name: '忽略「已装向量」：每次都重新嵌一遍语料（暖启动失去意义）',
    file: SERVICE + 'KnowledgeStore.ets',
    from: '      if (this.hasVectors()) {',
    to: '      if (false) {',
    expect: '暖启动',
  },
  {
    name: '失败不粘住：每次提问都重试一次死端点（每问都等一个超时）',
    file: SERVICE + 'KnowledgeStore.ets',
    from: '    if (this.denseFailedKey.length === 0) {\n      return false;\n    }',
    to: '    return false;',
    expect: '嵌入失败会粘在该端点上',
  },
  {
    name: '失败粘住整个进程：换了端点也不重试（改完设置必须重启才生效）',
    file: SERVICE + 'KnowledgeStore.ets',
    from: '    if (this.denseFailedKey === key) {\n      return true;\n    }\n'
      + '    this.denseFailedKey = \'\';\n    return false;',
    to: '    return this.denseFailedKey.length > 0;',
    expect: '端点换了就重新尝试',
  },
  {
    name: '一次性把整份语料塞进一个请求（客户端不再自己分批，单请求超时风险）',
    file: SERVICE + 'KnowledgeStore.ets',
    from: 'start += DENSE_EMBED_BATCH_SIZE)',
    to: 'start += chunks.length)',
    expect: '整份语料按批次发完',
  },
  {
    name: 'prepareVectors 吞掉嵌入器自报的权重（真模型被当成哈希替身压权）',
    file: SERVICE + 'KnowledgeStore.ets',
    from: '    this.vectorWeight = Number.isFinite(weight) && weight > 0 ? weight : RRF_DEFAULT_VECTOR_WEIGHT;',
    to: '    this.vectorWeight = RRF_DEFAULT_VECTOR_WEIGHT;',
    expect: '权重取远端实测值',
  },
  {
    name: '预热顺手把向量也建了（启动路径够到嵌入器，开机就出网）',
    file: SERVICE + 'KnowledgeStore.ets',
    from: '  warmUp(): void {\n    this.ensureBuilt();\n  }',
    to: '  warmUp(): void {\n    this.ensureBuilt();\n    this.startDenseBuild(this.embedder());\n  }',
    expect: '预热不联网',
  },
  {
    name: '权重不再随签名走（暖启动悄悄用回保守权重，冷暖行为不一致）',
    file: SERVICE + 'KnowledgeEmbeddingProxy.ets',
    from: '  return isRemoteVectorSignature(signature) ? RRF_REMOTE_VECTOR_WEIGHT : RRF_DEFAULT_VECTOR_WEIGHT;',
    to: '  return RRF_DEFAULT_VECTOR_WEIGHT;',
    expect: '融合权重由「谁产出了向量」决定',
  },
  {
    name: '快照退回浮点直存（无损，所以排序断言反而更绿——只有体积断言能抓）',
    file: SERVICE + 'KnowledgeSnapshotCodec.ets',
    from: '    vectors: [],\n    vectorsQuantized: quantized.rows,\n    vectorScales: quantized.scales,',
    to: '    vectors: snapshot.vectors,\n    vectorsQuantized: [],\n    vectorScales: [],',
    expect: '快照文件里写的是打包向量',
  },
  {
    name: '量化偏移写成 0（负分量被夹成 0，向量被削掉一半；本地替身全为正分量，抓不住它）',
    file: SERVICE + 'KnowledgeSnapshotCodec.ets',
    from: 'const BYTE_OFFSET = 128;',
    to: 'const BYTE_OFFSET = 0;',
    expect: '量化的整数域覆盖正负两端',
  },
  {
    name: '不再拒绝行宽不一致的打包载荷（位置错位会算错块）',
    file: SERVICE + 'KnowledgeSnapshotCodec.ets',
    from: '    if (width === 0) {\n      width = bytes.length;\n    } else if (bytes.length !== width) {\n'
      + '      return null;\n    }',
    to: '    width = bytes.length;',
    expect: '打包载荷损坏的每一种形状都被拒绝',
  },
  {
    name: '不再检测嵌入模型是否换了（旧模型的向量配新模型的查询，排序看着正常但毫无意义）',
    file: SERVICE + 'KnowledgeStore.ets',
    from: '          if (this.denseVectorsAreStale(embedder)) {',
    to: '          if (false) {',
    expect: '同一个地址换了模型',
  },
  {
    name: 'agent 工具退回纯词法检索（接线只改一处，留下一条没有向量的通路）',
    file: SERVICE + 'AgentTools.ets',
    from: '    const hits = await this.knowledgeStore.searchBest(query);',
    to: '    const hits = this.knowledgeStore.search(query);',
    expect: '两条问答通路都改走 searchBest',
  },
];

function runP7() {
  try {
    execFileSync(NODE, ['_test_artifacts/ai_agent_p7_test.cjs'], {
      cwd: ROOT,
      encoding: 'utf8',
      timeout: 300000,
    });
  } catch (error) {
    // 有断言失败时脚本以非 0 退出，结果照旧写进 JSON。
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

    const failed = runP7();
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

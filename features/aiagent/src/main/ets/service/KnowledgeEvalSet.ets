/*
 * Copyright (c) 2025 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 */

/**
 * A hand-labelled retrieval case.
 *
 * Relevance is judged by *answer-term containment*: a hit counts when it comes
 * from the named document and one of its `expected` terms appears in the
 * heading path or in the body. That is a proxy for human judgement, not a
 * substitute for it — it is reproducible and it can be re-run on every commit,
 * which is what the project's test report was missing ("掌握度评估仍是启发式，
 * 尚无标注集验证准确率").
 *
 * The proxy is deliberately biased *against* the retriever: a chunk that
 * mentions the topic but does not answer the question still counts as relevant,
 * so a score below 1.0 means passages were genuinely not found rather than that
 * the grader was strict.
 */
export class KnowledgeEvalCase {
  /** What the learner types. */
  query: string = '';
  /** Where the answer lives, e.g. `doc_note_13`. Empty means "any document". */
  docId: string = '';
  /**
   * Answer terms. Each must be at least two characters — a single character
   * would match almost any chunk and make the measurement meaningless.
   */
  expected: string[] = [];
  /** `direct` or `paraphrase`; see the two bucket constants. */
  bucket: string = '';
  /** Why this case is here, so a future reader can judge the label. */
  note: string = '';
}

/** The query uses the material's own vocabulary ("拥塞控制有哪些算法"). */
export const EVAL_BUCKET_DIRECT = 'direct';
/**
 * The query is worded the way a learner actually asks ("为什么建立连接不能只
 * 握两次手"). This bucket is the honest measure of the lexical retriever's
 * ceiling, and the reason a semantic stage is worth adding later.
 */
export const EVAL_BUCKET_PARAPHRASE = 'paraphrase';

const NOTE_NETWORK = 'doc_note_13';
const NOTE_OS = 'doc_note_12';
const NOTE_DATA_STRUCTURE = 'doc_note_9';
const NOTE_ALGORITHM = 'doc_note_10';
const NOTE_DATABASE = 'doc_note_14';
const NOTE_COMPILER = 'doc_note_15';
const NOTE_SOFTWARE = 'doc_note_16';
const NOTE_MATH = 'doc_note_1';
const NOTE_ML = 'doc_note_23';
const NOTE_WEB = 'doc_note_24';
const NOTE_LINUX = 'doc_note_25';
const NOTE_ARCHITECTURE = 'doc_note_11';
const NOTE_PROGRAMMING = 'doc_note_7';

function evalCase(query: string, docId: string, expected: string[], bucket: string,
  note: string): KnowledgeEvalCase {
  const item = new KnowledgeEvalCase();
  item.query = query;
  item.docId = docId;
  item.expected = expected;
  item.bucket = bucket;
  item.note = note;
  return item;
}

/**
 * The labelled set. Thirty cases over the shipped notes: eighteen phrased in
 * the material's own terms, twelve phrased the way a student asks.
 *
 * Kept as data rather than being derived from the corpus on purpose — a set
 * generated from the index would only ever confirm that the index can find what
 * it was built from.
 */
export function buildKnowledgeEvalSet(): KnowledgeEvalCase[] {
  const cases: KnowledgeEvalCase[] = [];

  // ---------- direct: the query speaks the course's language ----------
  cases.push(evalCase('TCP 三次握手的过程是怎样的', NOTE_NETWORK, ['三次握手'],
    EVAL_BUCKET_DIRECT, '讲义里有带序号的完整三步过程'));
  cases.push(evalCase('TCP 四次挥手为什么是四次', NOTE_NETWORK, ['四次挥手'],
    EVAL_BUCKET_DIRECT, '全双工各自关闭'));
  cases.push(evalCase('TCP 的拥塞控制包含哪些算法', NOTE_NETWORK, ['拥塞控制'],
    EVAL_BUCKET_DIRECT, '慢开始、拥塞避免、快重传、快恢复'));
  cases.push(evalCase('什么时候应该用 UDP 而不是 TCP', NOTE_NETWORK, ['UDP'],
    EVAL_BUCKET_DIRECT, '无连接、开销小、适合实时场景'));
  cases.push(evalCase('ARP 协议的作用是什么', NOTE_NETWORK, ['ARP'],
    EVAL_BUCKET_DIRECT, '只在正文出现，标题里没有'));
  cases.push(evalCase('OSPF 和 RIP 有什么区别', NOTE_NETWORK, ['OSPF'],
    EVAL_BUCKET_DIRECT, '链路状态 vs 距离向量'));
  cases.push(evalCase('对称加密和非对称加密的区别', NOTE_NETWORK, ['对称加密'],
    EVAL_BUCKET_DIRECT, '网络安全小节'));
  cases.push(evalCase('进程和线程的主要区别', NOTE_OS, ['进程与线程'],
    EVAL_BUCKET_DIRECT, '资源分配 vs 调度单位'));
  cases.push(evalCase('死锁产生的四个必要条件', NOTE_OS, ['死锁'],
    EVAL_BUCKET_DIRECT, '设备管理与死锁'));
  cases.push(evalCase('二叉搜索树的中序遍历特点', NOTE_DATA_STRUCTURE, ['二叉搜索树'],
    EVAL_BUCKET_DIRECT, '中序有序'));
  cases.push(evalCase('栈和队列的区别', NOTE_DATA_STRUCTURE, ['栈与队列'],
    EVAL_BUCKET_DIRECT, '后进先出 vs 先进先出'));
  cases.push(evalCase('动态规划的适用条件', NOTE_ALGORITHM, ['动态规划'],
    EVAL_BUCKET_DIRECT, '重叠子问题与最优子结构'));
  cases.push(evalCase('数据库事务的 ACID 特性', NOTE_DATABASE, ['ACID'],
    EVAL_BUCKET_DIRECT, '专设小节'));
  cases.push(evalCase('词法分析把字符流变成什么', NOTE_COMPILER, ['词法分析'],
    EVAL_BUCKET_DIRECT, 'Token 序列'));
  cases.push(evalCase('软件测试中黑盒测试关注什么', NOTE_SOFTWARE, ['软件测试'],
    EVAL_BUCKET_DIRECT, '输入输出是否符合需求'));
  cases.push(evalCase('定积分怎么计算', NOTE_MATH, ['定积分'],
    EVAL_BUCKET_DIRECT, '求原函数-代上限-减下限'));
  cases.push(evalCase('监督学习和无监督学习的区别', NOTE_ML, ['监督学习'],
    EVAL_BUCKET_DIRECT, '有无标签'));
  cases.push(evalCase('CSS 响应式设计怎么做', NOTE_WEB, ['响应式'],
    EVAL_BUCKET_DIRECT, '媒体查询等'));
  cases.push(evalCase('Linux 用户与权限管理', NOTE_LINUX, ['用户与权限'],
    EVAL_BUCKET_DIRECT, '小节标题即答案位置'));
  cases.push(evalCase('机器指令的寻址方式', NOTE_ARCHITECTURE, ['指令系统'],
    EVAL_BUCKET_DIRECT, '指令系统小节'));
  cases.push(evalCase('C 语言里指针和数组的关系', NOTE_PROGRAMMING, ['数组与指针'],
    EVAL_BUCKET_DIRECT, '专设小节'));

  // ---------- paraphrase: the learner's own words ----------
  cases.push(evalCase('为什么建立连接不能只握两次手', NOTE_NETWORK, ['三次握手'],
    EVAL_BUCKET_PARAPHRASE, '共享「两次」「握手」，靠语序不同拉低重合度'));
  cases.push(evalCase('客户端和服务器怎么确认对方能收到消息', NOTE_NETWORK, ['三次握手'],
    EVAL_BUCKET_PARAPHRASE, '只共享「确认」「收到」等通用词'));
  cases.push(evalCase('客人已经走了，为什么还要多等一会儿才真正断开', NOTE_NETWORK, ['TIME_WAIT'],
    EVAL_BUCKET_PARAPHRASE, '几乎零词面重合，预期是最难的一类'));
  cases.push(evalCase('多个学校之间怎么交换各自能到哪些网络', NOTE_NETWORK, ['BGP'],
    EVAL_BUCKET_PARAPHRASE, '只共享「网络」「交换」'));
  cases.push(evalCase('网页打开特别慢，问题可能出在哪一层', NOTE_NETWORK, ['应用层'],
    EVAL_BUCKET_PARAPHRASE, '只共享「网页」'));
  cases.push(evalCase('内存不够用的时候操作系统会怎么处理', NOTE_OS, ['内存管理'],
    EVAL_BUCKET_PARAPHRASE, '共享「内存」'));
  cases.push(evalCase('给一堆数字按大小排好，用什么办法快', NOTE_DATA_STRUCTURE, ['排序'],
    EVAL_BUCKET_PARAPHRASE, '共享「排」但不成词'));
  cases.push(evalCase('树这种结构为什么查找起来快', NOTE_DATA_STRUCTURE, ['二叉搜索树'],
    EVAL_BUCKET_PARAPHRASE, '共享「树」「查找」'));
  cases.push(evalCase('两个事务同时改一条数据会出什么问题', NOTE_DATABASE, ['并发控制'],
    EVAL_BUCKET_PARAPHRASE, '共享「事务」'));
  cases.push(evalCase('把一个难题拆成若干小块分别解决，这叫什么', NOTE_ALGORITHM, ['分治'],
    EVAL_BUCKET_PARAPHRASE, '零词面重合，靠同段落其它术语兜底'));
  cases.push(evalCase('怎么让程序跑得更快但算出来的结果不变', NOTE_COMPILER, ['代码优化'],
    EVAL_BUCKET_PARAPHRASE, '零词面重合'));
  cases.push(evalCase('样本太少的时候模型会不会学不准', NOTE_ML, ['模型评估'],
    EVAL_BUCKET_PARAPHRASE, '共享「模型」'));

  return cases;
}

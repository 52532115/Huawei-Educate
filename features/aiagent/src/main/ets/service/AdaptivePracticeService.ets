/*
 * Copyright (c) 2025 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 */

import fileIo from '@ohos.file.fs';
import { DataCollectService } from './DataCollectService';
import { ErrorAttributionService } from './ErrorAttributionService';
import {
  ErrorBookPracticeSource,
  normalizeKnowledgeTag,
  normalizeQuestionTitle,
} from './ErrorBookPracticeSource';
import {
  DEFAULT_SEED_MASTERY,
  PracticeHistoryEntry,
  PracticeHistoryStore,
  PracticeHistoryTotals,
  buildPracticeHistoryLine,
} from './PracticeHistoryStore';
import { LearnerProfileStore } from './LearnerProfileStore';
import { ErrorQuestionItem, LearningDataSnapshot } from '../viewmodel/ChatModels';
import {
  AdaptivePracticeQuestion,
  AdaptivePracticeSession,
  KnowledgePracticeProfile,
  PracticeDifficulty,
  PracticeSessionSummary,
} from '../viewmodel/AdaptivePracticeModels';

interface ErrorBookRecord {
  id: string;
  title: string;
  option: string[];
  rightQues: number;
  answer?: number;
  userNote: string;
  mistakeReason: string;
  knowledgeTag: string;
  createTime: number;
  analysis?: string;
  key: string;
  source?: string;
  sourceId?: string;
  /** How many times the learner has re-answered this mistake incorrectly. */
  wrongCount?: number;
  /** Last time the learner reviewed this record (ms); drives review priority. */
  lastReviewTime?: number;
}

const ERROR_STORE_KEY = 'ErrorQuestions';
const ERROR_BOOK_FILE = '/errorBook.json';
/** Ids of the shipped sample mistakes (see MineLocalData.DEFAULT_ERROR_MODELS). */
const DEMO_RECORD_PREFIX = 'err_default_';
/** How many low-mastery knowledge points are pushed into the learner profile. */
const PROFILE_WEAK_SYNC_LIMIT = 3;

export class AdaptivePracticeService {
  private dataCollectService: DataCollectService = new DataCollectService();
  private attributionService: ErrorAttributionService = new ErrorAttributionService();
  private errorBookSource: ErrorBookPracticeSource = new ErrorBookPracticeSource();
  private historyStore: PracticeHistoryStore = new PracticeHistoryStore();
  private profileStore: LearnerProfileStore = new LearnerProfileStore();
  /**
   * The heuristic mastery per tag, captured while building the profiles. It is
   * the seed a knowledge point starts from the first time it is answered, so a
   * learner upgrading mid-course does not see every number restart.
   */
  private profileSeeds: Map<string, number> = new Map<string, number>();
  /** Last weak-tag set pushed to the learner profile, so it is not rewritten per answer. */
  private syncedWeakTagKey: string = '';
  /** Record ids that were answered correctly and should be de-prioritised. */
  private pendingReviewIds: string[] = [];

  /**
   * Builds a session in four layers, best material first:
   *   1. the learner's own error-book records (the adaptive part)
   *   2. knowledge-point profiles, as before
   *   3. the shipped question bank, for whatever is still missing
   *   4. nothing else — the profile layer already falls back to a placeholder
   *
   * `now` is a parameter so ordering stays reproducible in tests. `excludeIds`
   * lets a caller ask for a fresh set — the error-book layer, which is fully
   * deterministic, would otherwise return the same top N every time.
   */
  generateSession(questionCount: number = 6, now: number = Date.now(),
    excludeIds: string[] = []): AdaptivePracticeSession {
    const snapshot = this.dataCollectService.collectAllData();
    const profiles = this.buildProfiles(snapshot, now);
    const questions: AdaptivePracticeQuestion[] = [];
    const usedIds: string[] = [];
    const usedTitles: string[] = [];

    const fromErrorBook =
      this.errorBookSource.buildQuestions(snapshot.errorQuestions, questionCount, now, excludeIds);
    for (let i = 0; i < fromErrorBook.length && questions.length < questionCount; i++) {
      const question = fromErrorBook[i];
      if (usedIds.indexOf(question.id) >= 0) {
        continue;
      }
      questions.push(question);
      usedIds.push(question.id);
      usedTitles.push(normalizeQuestionTitle(question.title));
    }

    for (let i = 0; i < profiles.length && questions.length < questionCount; i++) {
      const question = this.pickQuestionForProfile(profiles[i], usedIds, now);
      if (this.containsTitle(usedTitles, question.title)) {
        continue;
      }
      questions.push(question);
      usedIds.push(question.id);
      usedTitles.push(normalizeQuestionTitle(question.title));
    }

    const bank = this.buildQuestionBank();
    for (let i = 0; i < bank.length && questions.length < questionCount; i++) {
      if (usedIds.indexOf(bank[i].id) < 0 && !this.containsTitle(usedTitles, bank[i].title)) {
        questions.push(this.cloneQuestion(bank[i]));
        usedIds.push(bank[i].id);
        usedTitles.push(normalizeQuestionTitle(bank[i].title));
      }
    }

    return new AdaptivePracticeSession(`practice_${now}`, questions, profiles);
  }

  submitAnswer(question: AdaptivePracticeQuestion, selectedIndex: number,
    now: number = Date.now()): AdaptivePracticeQuestion {
    question.selectedIndex = selectedIndex;
    question.isSubmitted = true;

    // Recorded before the error-book write-back, and on its own guard: the
    // learner may abandon the session on the next tap, and a failure while
    // updating the error book must not also cost them the mastery update.
    if (!question.masteryRecorded) {
      question.masteryRecorded = true;
      this.recordMastery(question.knowledgeTag, selectedIndex === question.correctIndex, now);
    }

    if (selectedIndex !== question.correctIndex) {
      question.attribution = this.attributionService.diagnosePracticeQuestion(question);
      if (!question.syncedToErrorBook) {
        this.recordPracticeMistake(question, now);
        question.syncedToErrorBook = true;
      }
    } else if (question.sourceRecordId.length > 0) {
      this.pendingReviewIds.push(question.sourceRecordId);
    }

    return question;
  }

  buildSummary(session: AdaptivePracticeSession, now: number = Date.now()): PracticeSessionSummary {
    const summary = new PracticeSessionSummary();
    summary.totalCount = session.questions.length;

    const weakMap = new Map<string, number>();
    const masteredMap = new Map<string, number>();
    for (let i = 0; i < session.questions.length; i++) {
      const question = session.questions[i];
      if (!question.isSubmitted) {
        continue;
      }
      if (question.selectedIndex === question.correctIndex) {
        summary.correctCount += 1;
        masteredMap.set(question.knowledgeTag, (masteredMap.get(question.knowledgeTag) || 0) + 1);
      } else {
        weakMap.set(question.knowledgeTag, (weakMap.get(question.knowledgeTag) || 0) + 1);
      }
    }

    summary.score = summary.totalCount === 0 ? 0 : Math.round(summary.correctCount / summary.totalCount * 100);
    summary.weakTags = this.mapKeys(weakMap);
    summary.masteredTags = this.mapKeys(masteredMap);
    summary.advice = this.buildAdvice(summary);

    const totals: PracticeHistoryTotals = this.historyStore.getTotals();
    summary.historyAttempts = totals.attempts;
    summary.historyCorrect = totals.correct;
    summary.historyTags = totals.tags;
    summary.historyWeakTags = this.historyStore.weakestTags(now, PROFILE_WEAK_SYNC_LIMIT);
    // Converge here as well: an answer that never crossed the weak threshold on
    // its own still gets linked once the session is summarised.
    this.syncProfileWeakPoints(now);

    session.summary = summary;
    this.flushReviewMarks(now);
    return summary;
  }

  /** All-time practice counters, for the panel shown before a session finishes. */
  getHistoryTotals(): PracticeHistoryTotals {
    return this.historyStore.getTotals();
  }

  /**
   * The shipped question bank (stem, options, answer, explanation, advice),
   * exposed so the knowledge index can index the explanations. Every call
   * builds a fresh array of fresh questions, so a caller cannot mutate the bank
   * the practice engine hands out.
   */
  getShippedQuestionBank(): AdaptivePracticeQuestion[] {
    return this.buildQuestionBank();
  }

  /**
   * Records one answer against the cumulative mastery and persists it right away.
   * Nothing here is allowed to depend on the session finishing.
   */
  private recordMastery(tag: string, isCorrect: boolean, now: number): void {
    const newMastery = this.historyStore.recordAnswer(tag, isCorrect, now, this.resolveSeedMastery(tag, now));
    if (newMastery < 0) {
      return;
    }
    this.syncProfileWeakPoints(now);
  }

  /**
   * What this knowledge point starts from the first time it is answered.
   * Falls back to building the profiles once when the session arrived from the
   * agent (which hands a session over without generateSession ever running).
   */
  private resolveSeedMastery(tag: string, now: number): number {
    if (this.profileSeeds.size === 0) {
      this.buildProfiles(this.dataCollectService.collectAllData(), now);
    }
    const seed = this.profileSeeds.get(normalizeKnowledgeTag(tag));
    return seed === undefined ? DEFAULT_SEED_MASTERY : seed;
  }

  /**
   * Mirrors the weakest knowledge points into the learner profile so the tutor
   * can talk about them. Guarded by the last set pushed: without it every single
   * answer would trigger a profile read-modify-write.
   */
  private syncProfileWeakPoints(now: number): void {
    const weakTags = this.historyStore.weakestTags(now, PROFILE_WEAK_SYNC_LIMIT);
    const key = weakTags.join('|');
    if (key === this.syncedWeakTagKey) {
      return;
    }
    this.syncedWeakTagKey = key;
    this.profileStore.recordPracticeWeakPoints(weakTags, now);
  }

  /**
   * Knowledge-point profiles, weakest first.
   *
   * The error-book/course heuristic below no longer *is* the mastery — it only
   * seeds it. A knowledge point that has been practiced takes its value from the
   * cumulative history instead (which is what makes answering questions actually
   * move the number); one that never has keeps the heuristic so a fresh install
   * behaves exactly as before.
   */
  private buildProfiles(snapshot: LearningDataSnapshot, now: number): KnowledgePracticeProfile[] {
    const profileMap = new Map<string, KnowledgePracticeProfile>();
    this.profileSeeds.clear();
    const courseNotes = new Map<string, string>();

    for (let i = 0; i < snapshot.errorQuestions.length; i++) {
      const item: ErrorQuestionItem = snapshot.errorQuestions[i];
      const tag = normalizeKnowledgeTag(item.category);
      const existing = profileMap.get(tag);
      if (existing) {
        existing.errorCount += 1;
        existing.priority += 12;
        existing.mastery = Math.max(20, existing.mastery - 8);
        existing.reason = `错题集中「${tag}」累计 ${existing.errorCount} 道错题`;
      } else {
        profileMap.set(tag, new KnowledgePracticeProfile(
          tag,
          1,
          68,
          86,
          `错题集中出现「${tag}」相关错误`,
        ));
      }
    }

    for (let i = 0; i < snapshot.courseProgress.length; i++) {
      const course = snapshot.courseProgress[i];
      if (course.progress >= 65) {
        continue;
      }
      const courseName = normalizeKnowledgeTag(course.name);
      const existing = profileMap.get(courseName);
      if (existing) {
        existing.priority += 20;
        // No longer caps the mastery. A cumulative value that a course
        // percentage can clamp would make "+6 for a correct answer" invisible
        // on exactly the knowledge points the learner is working on; the hint
        // survives as text instead.
        courseNotes.set(courseName, `课程进度仅 ${course.progress}%，建议先跟课`);
      } else {
        courseNotes.set(courseName, `课程进度仅 ${course.progress}%，建议先跟课`);
        profileMap.set(courseName, new KnowledgePracticeProfile(
          courseName,
          0,
          course.progress,
          70 + (65 - course.progress),
          `课程「${courseName}」进度仅 ${course.progress}%`,
        ));
      }
    }

    if (profileMap.size === 0) {
      profileMap.set('数据结构', new KnowledgePracticeProfile('数据结构', 0, 70, 78, '默认巩固专业核心课程'));
      profileMap.set('操作系统', new KnowledgePracticeProfile('操作系统', 0, 72, 74, '默认巩固专业核心课程'));
      profileMap.set('计算机网络', new KnowledgePracticeProfile('计算机网络', 0, 68, 76, '默认巩固专业核心课程'));
    }

    // The heuristic values are what a knowledge point starts from once answered.
    profileMap.forEach((value: KnowledgePracticeProfile) => {
      this.profileSeeds.set(value.tag, value.mastery);
    });

    this.applyPracticeHistory(profileMap, courseNotes, now);

    const profiles: KnowledgePracticeProfile[] = [];
    profileMap.forEach((value: KnowledgePracticeProfile) => {
      profiles.push(value);
    });
    // Weakest first — this is the one signal that actually steers which question
    // the profile layer serves. priority keeps its old meaning as the tie-break
    // (the UI and PracticeSessionStore both still read it), and the tag makes the
    // order total, so the same inputs always produce the same sequence.
    profiles.sort((a: KnowledgePracticeProfile, b: KnowledgePracticeProfile): number => {
      if (a.mastery !== b.mastery) {
        return a.mastery - b.mastery;
      }
      if (a.priority !== b.priority) {
        return b.priority - a.priority;
      }
      return a.tag < b.tag ? -1 : (a.tag > b.tag ? 1 : 0);
    });
    return profiles;
  }

  /**
   * Overlays the cumulative history onto the seeded profiles, and adds any
   * knowledge point the learner has practiced that the heuristic alone never
   * produced — a question answered from the shipped bank would otherwise move a
   * mastery number that no row ever displays.
   */
  private applyPracticeHistory(profileMap: Map<string, KnowledgePracticeProfile>,
    courseNotes: Map<string, string>, now: number): void {
    // One storage read for the whole overlay; decays each entry off the copy.
    const practiced: PracticeHistoryEntry[] = this.historyStore.getPracticedEntries();
    for (let i = 0; i < practiced.length; i++) {
      const entry = practiced[i];
      const effective = this.historyStore.effectiveMasteryFor(entry, now);
      if (effective < 0) {
        continue;
      }
      let profile = profileMap.get(entry.tag);
      if (profile === undefined) {
        // Practiced from the shipped bank, which the heuristic never seeded —
        // without this the mastery would move with no row showing it.
        profile = new KnowledgePracticeProfile(entry.tag, 0, entry.mastery, 70, '');
        profileMap.set(entry.tag, profile);
      }
      profile.mastery = effective;
      profile.attempts = entry.attempts;
      profile.correct = entry.correct;
      profile.lastPracticeTime = entry.lastPracticeTime;
      profile.reason = this.buildHistoryReason(entry, effective, courseNotes.get(entry.tag), now);
    }
  }

  /**
   * Replaces the heuristic's reason with what the history actually knows, e.g.
   * "已练 6 次 · 正确 4 次（67%）· 10 天前练过，掌握度 66%（已衰减 8%）".
   */
  private buildHistoryReason(entry: PracticeHistoryEntry, effective: number,
    courseNote: string | undefined, now: number): string {
    let reason = `${buildPracticeHistoryLine(entry.attempts, entry.correct, entry.lastPracticeTime, now)}，掌握度 ${effective}%`;
    const decay = entry.mastery - effective;
    if (decay > 0) {
      reason += `（已衰减 ${decay}%）`;
    }
    if (courseNote !== undefined && courseNote.length > 0) {
      reason += `；${courseNote}`;
    }
    return reason;
  }

  private pickQuestionForProfile(profile: KnowledgePracticeProfile, usedIds: string[],
    now: number): AdaptivePracticeQuestion {
    const bank = this.buildQuestionBank();
    for (let i = 0; i < bank.length; i++) {
      if (usedIds.indexOf(bank[i].id) < 0 && bank[i].knowledgeTag === profile.tag) {
        return this.cloneQuestion(bank[i]);
      }
    }

    for (let i = 0; i < bank.length; i++) {
      if (usedIds.indexOf(bank[i].id) < 0 && this.isRelatedTag(profile.tag, bank[i].knowledgeTag)) {
        return this.cloneQuestion(bank[i]);
      }
    }

    return new AdaptivePracticeQuestion(
      // `now`, not Date.now(): the whole session is reproducible for a given now.
      `q_custom_${profile.tag}_${now}`,
      `关于「${profile.tag}」的复习，最有效的第一步是什么？`,
      ['直接刷高难题', '先回顾概念和典型例题，再做针对性练习', '只看答案解析', '暂时跳过该知识点'],
      1,
      profile.tag,
      PracticeDifficulty.BASIC,
      profile.reason,
      `对薄弱知识点应先建立概念框架，再用少量典型题验证掌握情况。`,
      `建议今天围绕「${profile.tag}」完成 3 道基础题和 2 道变式题。`,
    );
  }

  private buildQuestionBank(): AdaptivePracticeQuestion[] {
    return [
      new AdaptivePracticeQuestion(
        'q_limit_basic_1',
        '极限 lim(x→0) sin(2x)/x 的值为？',
        ['0', '1', '2', '不存在'],
        2,
        '函数与极限',
        PracticeDifficulty.BASIC,
        '根据错题本中的极限类错误生成',
        '当 x→0 时，sin(2x) 与 2x 等价，因此原式等于 2。',
        '复习等价无穷小替换时要保留系数。',
      ),
      new AdaptivePracticeQuestion(
        'q_derivative_medium_1',
        '函数 f(x)=x²-4x+1 在实数范围内的最小值是？',
        ['-3', '0', '1', '4'],
        0,
        '导数与微分',
        PracticeDifficulty.MEDIUM,
        '根据错题本中的导数类错误生成',
        '配方得 f(x)=(x-2)²-3，所以最小值为 -3。',
        '求最值时要检查驻点和端点，闭区间题还要看边界。',
      ),
      new AdaptivePracticeQuestion(
        'q_integral_basic_1',
        '不定积分 ∫2x dx 的结果是？',
        ['x²+C', '2x²+C', 'x²', '2+C'],
        0,
        '不定积分',
        PracticeDifficulty.BASIC,
        '根据错题本中的积分类错误生成',
        '∫2x dx = x² + C，不定积分必须写积分常数。',
        '每次写不定积分答案时最后检查是否有 +C。',
      ),
      new AdaptivePracticeQuestion(
        'q_definite_integral_1',
        '定积分 ∫₀² x dx 的值为？',
        ['1', '2', '3', '4'],
        1,
        '定积分',
        PracticeDifficulty.BASIC,
        '根据错题本中的定积分错误生成',
        '原函数为 x²/2，代入 0 到 2 得 2。',
        '定积分计算要按“求原函数-代上限-减下限”三步走。',
      ),
      new AdaptivePracticeQuestion(
        'q_series_1',
        '级数 ∑1/n² 的敛散性是？',
        ['发散', '条件收敛', '收敛', '无法判断'],
        2,
        '无穷级数',
        PracticeDifficulty.MEDIUM,
        '根据错题本中的级数判别错误生成',
        '这是 p 级数，p=2>1，因此收敛。',
        '比较 p 级数时先确认分母最高次幂对应的 p 值。',
      ),
      new AdaptivePracticeQuestion(
        'q_data_structure_1',
        '在二叉搜索树中，中序遍历得到的序列通常具有什么特征？',
        ['层次顺序', '递减或递增有序', '随机顺序', '只包含叶子结点'],
        1,
        '数据结构',
        PracticeDifficulty.BASIC,
        '根据课程进度和专业核心课程生成',
        '二叉搜索树左子树小于根、右子树大于根，中序遍历会得到有序序列。',
        '复习树结构时把遍历顺序和结构性质一起记。',
      ),
      new AdaptivePracticeQuestion(
        'q_algorithm_1',
        '动态规划最核心的两个特征是？',
        ['贪心选择和排序', '重叠子问题和最优子结构', '递归和循环', '枚举和剪枝'],
        1,
        '算法设计与分析',
        PracticeDifficulty.MEDIUM,
        '根据课程进度和专业核心课程生成',
        '动态规划适合具有重叠子问题和最优子结构的问题。',
        '遇到优化问题时先判断状态、转移和边界。',
      ),
      new AdaptivePracticeQuestion(
        'q_os_1',
        '操作系统中，进程和线程的主要区别是？',
        ['线程拥有独立地址空间', '进程是资源分配单位，线程是调度执行单位', '进程只能运行一个', '线程不能并发'],
        1,
        '操作系统',
        PracticeDifficulty.BASIC,
        '根据课程进度和专业核心课程生成',
        '进程通常是资源分配的基本单位，线程是 CPU 调度的基本单位。',
        '复习并发时重点区分资源、调度、同步三个概念。',
      ),
      new AdaptivePracticeQuestion(
        'q_network_1',
        'TCP 相比 UDP 最典型的特征是？',
        ['无连接', '可靠传输', '不校验数据', '一定更快'],
        1,
        '计算机网络',
        PracticeDifficulty.BASIC,
        '根据课程进度和专业核心课程生成',
        'TCP 面向连接，提供可靠传输；UDP 无连接、开销较小。',
        '比较协议时从连接性、可靠性、开销和典型场景四个维度入手。',
      ),
      new AdaptivePracticeQuestion(
        'q_database_1',
        '数据库事务 ACID 中的 I 表示什么？',
        ['原子性', '一致性', '隔离性', '持久性'],
        2,
        '数据库系统原理',
        PracticeDifficulty.BASIC,
        '根据课程进度和专业核心课程生成',
        'ACID 分别是 Atomicity、Consistency、Isolation、Durability。',
        '把事务特性和并发控制、恢复机制联系起来复习。',
      ),
      new AdaptivePracticeQuestion(
        'q_compiler_1',
        '编译过程中的词法分析主要输出什么？',
        ['语法树', 'Token 序列', '目标代码', '优化后的中间代码'],
        1,
        '编译原理',
        PracticeDifficulty.BASIC,
        '根据课程进度和专业核心课程生成',
        '词法分析把字符流切分为 Token 序列，供语法分析继续处理。',
        '复习编译流程时按词法、语法、语义、中间代码、优化、目标代码排序。',
      ),
      new AdaptivePracticeQuestion(
        'q_software_1',
        '软件测试中，黑盒测试主要关注什么？',
        ['内部代码路径', '输入输出是否符合需求', '编译器优化', '数据库索引结构'],
        1,
        '软件工程',
        PracticeDifficulty.BASIC,
        '根据课程进度和专业核心课程生成',
        '黑盒测试不关注内部实现，主要根据需求验证输入输出行为。',
        '复习测试方法时把黑盒、白盒、单元、集成、系统测试分清楚。',
      ),
    ];
  }

  /**
   * Records a wrong answer against the error book. An existing record for the
   * same question is always updated in place — never appended to — so a
   * question the learner keeps missing can't pile up as duplicates.
   *
   * Only review bookkeeping is written: the learner's own note, the question
   * wording and the original createTime (the "how long have I been getting this
   * wrong" signal) are left alone.
   */
  private recordPracticeMistake(question: AdaptivePracticeQuestion, now: number): void {
    const records = this.readErrorBookRecords();
    const index = this.findMistakeRecordIndex(records, question);

    if (index >= 0) {
      const record = records[index];
      record.answer = question.selectedIndex;
      const previous = typeof record.wrongCount === 'number' && record.wrongCount > 0 ? record.wrongCount : 1;
      record.wrongCount = previous + 1;
      record.lastReviewTime = now;
      if (question.attribution) {
        record.analysis = `${question.attribution.causeLabel}（置信度 ${question.attribution.confidence}%）：` +
          `${question.attribution.remediation}本次重做仍误选 ${this.toOptionLabel(question.selectedIndex)}。`;
      }
      question.sourceRecordId = record.id;
      this.writeErrorBookRecords(records);
      return;
    }

    const analysis = question.attribution ?
      `${question.attribution.causeLabel}（置信度 ${question.attribution.confidence}%）：${question.attribution.remediation}` :
      '自适应练习中答错，建议回看解析并完成同类训练。';

    const recordId = `adaptive_${now}_${Math.random().toString(36).substring(2, 8)}`;
    records.unshift({
      id: recordId,
      title: question.title,
      option: question.options,
      rightQues: question.correctIndex,
      answer: question.selectedIndex,
      userNote: question.explanation,
      mistakeReason: question.attribution ? question.attribution.evidence : '',
      knowledgeTag: question.knowledgeTag,
      createTime: now,
      analysis: analysis,
      key: '',
      source: 'adaptive_practice',
      sourceId: question.id,
      wrongCount: 1,
      lastReviewTime: now,
    });
    question.sourceRecordId = recordId;
    this.writeErrorBookRecords(records);
  }

  /**
   * Finds the record a question belongs to. Matching on the record id alone is
   * not enough: demo records are regenerated with fresh ids whenever the app
   * starts with an empty error book, and the same question may also have been
   * entered by hand. So fall back to the question text, preferring a
   * learner-owned record over a shipped demo one.
   */
  private findMistakeRecordIndex(records: ErrorBookRecord[], question: AdaptivePracticeQuestion): number {
    if (question.sourceRecordId.length > 0) {
      for (let i = 0; i < records.length; i++) {
        if (records[i].id === question.sourceRecordId) {
          return i;
        }
      }
    }

    const key = normalizeQuestionTitle(question.title);
    if (key.length === 0) {
      return -1;
    }

    let demoIndex = -1;
    for (let i = 0; i < records.length; i++) {
      if (normalizeQuestionTitle(records[i].title) !== key) {
        continue;
      }
      if (records[i].id.indexOf(DEMO_RECORD_PREFIX) !== 0) {
        return i;
      }
      if (demoIndex < 0) {
        demoIndex = i;
      }
    }
    return demoIndex;
  }

  /**
   * Marks correctly-answered error-book questions as reviewed so they sink in
   * the next session's ordering and stale mistakes surface instead. Nothing is
   * ever deleted — only the learner removes their own data.
   */
  private flushReviewMarks(now: number): void {
    if (this.pendingReviewIds.length === 0) {
      return;
    }
    const reviewedIds = this.pendingReviewIds;
    this.pendingReviewIds = [];

    const records = this.readErrorBookRecords();
    if (records.length === 0) {
      return;
    }

    let changed = false;
    for (let i = 0; i < records.length; i++) {
      const record = records[i];
      if (reviewedIds.indexOf(record.id) < 0) {
        continue;
      }
      record.lastReviewTime = now;
      changed = true;
    }
    if (changed) {
      this.writeErrorBookRecords(records);
    }
  }

  private buildAdvice(summary: PracticeSessionSummary): string {
    if (summary.totalCount === 0) {
      return '暂无练习记录，请先完成一次自适应练习。';
    }
    if (summary.score >= 85) {
      return '本轮掌握较好，可以进入更高难度的变式训练。';
    }
    if (summary.weakTags.length > 0) {
      return `建议优先复习「${summary.weakTags[0]}」，先做基础题，再做同类变式题。`;
    }
    return '继续保持练习节奏，建议每次练习后回顾错题解析。';
  }

  private isRelatedTag(sourceTag: string, bankTag: string): boolean {
    if (sourceTag.indexOf(bankTag) >= 0 || bankTag.indexOf(sourceTag) >= 0) {
      return true;
    }
    const mathTags = ['函数与极限', '导数与微分', '不定积分', '定积分', '无穷级数'];
    if (mathTags.indexOf(sourceTag) >= 0 && mathTags.indexOf(bankTag) >= 0) {
      return true;
    }
    return false;
  }

  // The local mojibake guard that used to live here is gone: the profile path
  // now calls ErrorBookPracticeSource.normalizeKnowledgeTag, the same one the
  // question path uses, so both key the same knowledge point. That version also
  // maps a corrupt tag to 未分类 instead of dropping the row, and does not treat
  // a half-width question mark as corruption.

  private cloneQuestion(question: AdaptivePracticeQuestion): AdaptivePracticeQuestion {
    return new AdaptivePracticeQuestion(
      question.id,
      question.title,
      [...question.options],
      question.correctIndex,
      question.knowledgeTag,
      question.difficulty,
      question.source,
      question.explanation,
      question.recommendation,
      question.sourceRecordId,
    );
  }

  private containsTitle(titles: string[], title: string): boolean {
    const normalized = normalizeQuestionTitle(title);
    if (normalized.length === 0) {
      return false;
    }
    return titles.indexOf(normalized) >= 0;
  }

  private toOptionLabel(index: number): string {
    if (index < 0) {
      return '';
    }
    return String.fromCharCode(65 + index);
  }

  private mapKeys(map: Map<string, number>): string[] {
    const keys: string[] = [];
    map.forEach((value: number, key: string) => {
      keys.push(key);
    });
    return keys;
  }

  private readErrorBookRecords(): ErrorBookRecord[] {
    let errorJson = '';
    try {
      const stored = AppStorage.get<string>(ERROR_STORE_KEY);
      if (stored && stored.length > 0) {
        errorJson = stored;
      }
    } catch (e) {
      // AppStorage may not be initialized during preview.
    }

    if (errorJson.length === 0) {
      const filePath = this.getErrorBookFilePath();
      if (filePath) {
        try {
          errorJson = fileIo.readTextSync(filePath);
        } catch (e) {
          // No persisted error book yet.
        }
      }
    }

    if (errorJson.length === 0) {
      return [];
    }

    try {
      return JSON.parse(errorJson) as ErrorBookRecord[];
    } catch (e) {
      return [];
    }
  }

  private writeErrorBookRecords(records: ErrorBookRecord[]): void {
    const json = JSON.stringify(records);
    AppStorage.setOrCreate(ERROR_STORE_KEY, json);
    const filePath = this.getErrorBookFilePath();
    if (!filePath) {
      return;
    }

    try {
      const file: fileIo.File = fileIo.openSync(filePath, 0o2 | 0o100 | 0o1000);
      fileIo.writeSync(file.fd, json);
      fileIo.closeSync(file);
    } catch (e) {
      // Persist failure should not interrupt practice.
    }
  }

  private getErrorBookFilePath(): string | null {
    const filesDir = AppStorage.get<string>('filesDir');
    if (!filesDir) {
      return null;
    }
    return filesDir + ERROR_BOOK_FILE;
  }
}

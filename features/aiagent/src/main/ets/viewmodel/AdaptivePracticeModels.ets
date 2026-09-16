/*
 * Copyright (c) 2025 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 */

export enum PracticeDifficulty {
  BASIC = '基础',
  MEDIUM = '进阶',
  HARD = '挑战',
}

export enum ErrorCauseType {
  CONCEPT = 'concept',
  FORMULA = 'formula',
  METHOD = 'method',
  CALCULATION = 'calculation',
  CARELESS = 'careless',
  UNKNOWN = 'unknown',
}

export class ErrorAttributionResult {
  causeType: ErrorCauseType;
  causeLabel: string;
  confidence: number;
  evidence: string;
  remediation: string;
  nextAction: string;

  constructor(
    causeType: ErrorCauseType,
    causeLabel: string,
    confidence: number,
    evidence: string,
    remediation: string,
    nextAction: string,
  ) {
    this.causeType = causeType;
    this.causeLabel = causeLabel;
    this.confidence = confidence;
    this.evidence = evidence;
    this.remediation = remediation;
    this.nextAction = nextAction;
  }
}

export class AdaptivePracticeQuestion {
  id: string;
  title: string;
  options: string[];
  correctIndex: number;
  knowledgeTag: string;
  difficulty: PracticeDifficulty;
  source: string;
  explanation: string;
  recommendation: string;
  selectedIndex: number;
  isSubmitted: boolean;
  attribution?: ErrorAttributionResult;
  syncedToErrorBook: boolean;
  /**
   * Id of the error-book record this question was built from. '' means the
   * question has no backing record (bank question, placeholder, demo record),
   * so answering it wrong appends a new record instead of updating one.
   */
  sourceRecordId: string;
  /**
   * Guards the cumulative mastery write: one answer must count once, however
   * many times the same question is submitted. Deliberately not persisted —
   * a handed-over session arrives unanswered, exactly like isSubmitted.
   */
  masteryRecorded: boolean;

  constructor(
    id: string,
    title: string,
    options: string[],
    correctIndex: number,
    knowledgeTag: string,
    difficulty: PracticeDifficulty,
    source: string,
    explanation: string,
    recommendation: string,
    sourceRecordId: string = '',
  ) {
    this.id = id;
    this.title = title;
    this.options = options;
    this.correctIndex = correctIndex;
    this.knowledgeTag = knowledgeTag;
    this.difficulty = difficulty;
    this.source = source;
    this.explanation = explanation;
    this.recommendation = recommendation;
    this.selectedIndex = -1;
    this.isSubmitted = false;
    this.syncedToErrorBook = false;
    this.sourceRecordId = sourceRecordId;
    this.masteryRecorded = false;
  }
}

/**
 * One cleaned, scored error-book record on its way to becoming a practice
 * question. Exported so the offline tests can assert cleaning, scoring and
 * ordering without going through the full session builder.
 */
export class ErrorBookPracticeCandidate {
  recordId: string = '';
  title: string = '';
  normalizedTitle: string = '';
  options: string[] = [];
  correctIndex: number = -1;
  knowledgeTag: string = '';
  userNote: string = '';
  mistakeReason: string = '';
  analysis: string = '';
  createTime: number = 0;
  /** max(createTime, lastReviewTime) — the age signal used for scoring. */
  lastActivityTime: number = 0;
  /** >= 1: how many times this mistake has been recorded/failed. */
  repeatCount: number = 1;
  isDemo: boolean = false;
  score: number = 0;
  difficulty: PracticeDifficulty = PracticeDifficulty.BASIC;
}

export class KnowledgePracticeProfile {
  tag: string;
  errorCount: number;
  mastery: number;
  priority: number;
  reason: string;
  /**
   * Practice history behind `mastery`, filled in by the service once the
   * knowledge point has been practiced. Defaults of 0 mean "no history yet",
   * which is why they are fields rather than constructor parameters — every
   * existing 5-argument construction keeps working untouched.
   */
  attempts: number = 0;
  correct: number = 0;
  lastPracticeTime: number = 0;

  constructor(tag: string, errorCount: number, mastery: number, priority: number, reason: string) {
    this.tag = tag;
    this.errorCount = errorCount;
    this.mastery = mastery;
    this.priority = priority;
    this.reason = reason;
  }
}

export class PracticeSessionSummary {
  totalCount: number;
  correctCount: number;
  score: number;
  weakTags: string[];
  masteredTags: string[];
  advice: string;
  generatedAt: number;
  /** All-time counters from the practice history, not just this session. */
  historyAttempts: number;
  historyCorrect: number;
  historyTags: number;
  /** Knowledge points the history still rates below the weak threshold. */
  historyWeakTags: string[];

  constructor() {
    this.totalCount = 0;
    this.correctCount = 0;
    this.score = 0;
    this.weakTags = [];
    this.masteredTags = [];
    this.advice = '';
    this.generatedAt = Date.now();
    this.historyAttempts = 0;
    this.historyCorrect = 0;
    this.historyTags = 0;
    this.historyWeakTags = [];
  }
}

export class AdaptivePracticeSession {
  id: string;
  questions: AdaptivePracticeQuestion[];
  profiles: KnowledgePracticeProfile[];
  summary: PracticeSessionSummary;

  constructor(id: string, questions: AdaptivePracticeQuestion[], profiles: KnowledgePracticeProfile[]) {
    this.id = id;
    this.questions = questions;
    this.profiles = profiles;
    this.summary = new PracticeSessionSummary();
  }
}

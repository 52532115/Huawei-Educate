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
  }
}

export class KnowledgePracticeProfile {
  tag: string;
  errorCount: number;
  mastery: number;
  priority: number;
  reason: string;

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

  constructor() {
    this.totalCount = 0;
    this.correctCount = 0;
    this.score = 0;
    this.weakTags = [];
    this.masteredTags = [];
    this.advice = '';
    this.generatedAt = Date.now();
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

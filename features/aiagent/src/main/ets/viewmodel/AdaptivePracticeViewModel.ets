/*
 * Copyright (c) 2025 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 */

import { AdaptivePracticeService } from '../service/AdaptivePracticeService';
import { ErrorAttributionService } from '../service/ErrorAttributionService';
import { PracticeSessionStore } from '../service/PracticeSessionStore';
import { SOURCE_ERROR_BOOK } from '../service/ErrorBookPracticeSource';
import { PracticeHistoryTotals } from '../service/PracticeHistoryStore';
import {
  AdaptivePracticeQuestion,
  AdaptivePracticeSession,
  PracticeSessionSummary,
} from './AdaptivePracticeModels';

@Observed
export class AdaptivePracticeViewModel {
  session: AdaptivePracticeSession;
  currentIndex: number;
  isFinished: boolean;
  attributionUpdatedCount: number;
  /** All-time practice counters, for the panel shown before a session finishes. */
  historyTotals: PracticeHistoryTotals;
  private practiceService: AdaptivePracticeService;
  private attributionService: ErrorAttributionService;
  private sessionStore: PracticeSessionStore;
  /** Error-book questions already served, so "换一组" moves on instead of repeating. */
  private seenQuestionIds: string[] = [];

  constructor() {
    this.practiceService = new AdaptivePracticeService();
    this.attributionService = new ErrorAttributionService();
    this.sessionStore = new PracticeSessionStore();
    // Prefer a session handed over by the agent (e.g. "帮我出几道练习题"),
    // otherwise generate one locally.
    const pending = this.sessionStore.loadPendingSession();
    this.session = pending ? pending : this.practiceService.generateSession();
    this.currentIndex = 0;
    this.isFinished = false;
    this.attributionUpdatedCount = 0;
    this.seenQuestionIds = this.collectErrorBookIds(this.session);
    this.historyTotals = this.practiceService.getHistoryTotals();
  }

  resetSession(): void {
    // Error-book selection is deterministic, so without this the same top N
    // would come back on every "换一组".
    const next = this.practiceService.generateSession(6, Date.now(), this.seenQuestionIds);
    const nextIds = this.collectErrorBookIds(next);
    // No unseen mistakes left: start the rotation over rather than repeat forever.
    this.seenQuestionIds = nextIds.length > 0 ? this.seenQuestionIds.concat(nextIds) : [];
    this.session = next;
    this.currentIndex = 0;
    this.isFinished = false;
  }

  private collectErrorBookIds(session: AdaptivePracticeSession): string[] {
    const ids: string[] = [];
    for (let i = 0; i < session.questions.length; i++) {
      const question = session.questions[i];
      if (question.source === SOURCE_ERROR_BOOK && this.seenQuestionIds.indexOf(question.id) < 0 &&
        ids.indexOf(question.id) < 0) {
        ids.push(question.id);
      }
    }
    return ids;
  }

  getCurrentQuestion(): AdaptivePracticeQuestion | undefined {
    if (this.session.questions.length === 0 || this.currentIndex >= this.session.questions.length) {
      return undefined;
    }
    return this.session.questions[this.currentIndex];
  }

  selectOption(index: number): void {
    const question = this.getCurrentQuestion();
    if (!question || question.isSubmitted) {
      return;
    }
    question.selectedIndex = index;
    this.session.questions = [...this.session.questions];
  }

  submitCurrent(): boolean {
    const question = this.getCurrentQuestion();
    if (!question || question.selectedIndex < 0 || question.isSubmitted) {
      return false;
    }
    this.practiceService.submitAnswer(question, question.selectedIndex);
    this.session.questions = [...this.session.questions];
    return true;
  }

  nextQuestion(): void {
    if (this.currentIndex < this.session.questions.length - 1) {
      this.currentIndex += 1;
      return;
    }
    this.finishSession();
  }

  previousQuestion(): void {
    if (this.currentIndex > 0) {
      this.currentIndex -= 1;
    }
  }

  finishSession(): void {
    this.practiceService.buildSummary(this.session);
    this.isFinished = true;
  }

  runErrorBookAttribution(): number {
    this.attributionUpdatedCount = this.attributionService.updateErrorBookAttributions();
    return this.attributionUpdatedCount;
  }

  getAnsweredCount(): number {
    let count = 0;
    for (let i = 0; i < this.session.questions.length; i++) {
      if (this.session.questions[i].isSubmitted) {
        count += 1;
      }
    }
    return count;
  }

  getCorrectCount(): number {
    let count = 0;
    for (let i = 0; i < this.session.questions.length; i++) {
      const q = this.session.questions[i];
      if (q.isSubmitted && q.selectedIndex === q.correctIndex) {
        count += 1;
      }
    }
    return count;
  }

  getSummary(): PracticeSessionSummary {
    return this.session.summary;
  }

  /**
   * Re-reads the all-time counters. Answered questions change them mid-session,
   * and the focus panel shows them before any summary exists.
   */
  refreshHistoryTotals(): void {
    this.historyTotals = this.practiceService.getHistoryTotals();
  }

  getOptionLabel(index: number): string {
    return String.fromCharCode(65 + index);
  }
}

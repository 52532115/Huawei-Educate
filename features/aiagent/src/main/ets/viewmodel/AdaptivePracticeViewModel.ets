/*
 * Copyright (c) 2025 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 */

import { AdaptivePracticeService } from '../service/AdaptivePracticeService';
import { ErrorAttributionService } from '../service/ErrorAttributionService';
import { PracticeSessionStore } from '../service/PracticeSessionStore';
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
    this.seenQuestionIds = this.collectQuestionIds(this.session);
    this.historyTotals = this.practiceService.getHistoryTotals();
    this.prepareNextRound();
  }

  /**
   * Asks the service to stock material for the next round, in the background.
   *
   * Neither awaited nor reported: this round is already complete, so the learner
   * waits for nothing, and whatever comes back shows up the next time they tap
   * "换一组". That ordering is the point — paying for questions after the round
   * rather than before it is what keeps the page opening instantly.
   */
  private prepareNextRound(): void {
    this.practiceService.schedulePrepare(this.session.profiles);
  }

  /**
   * Serves a fresh round, skipping everything already shown in this sitting.
   *
   * Every layer of the generator honours the skip list — not just the error book
   * — because the shipped bank holds about a dozen questions: without this,
   * "换一组" on a cold install handed back the very same six cards.
   */
  resetSession(): void {
    const seen = this.seenQuestionIds;
    const next = this.practiceService.generateSession(6, Date.now(), seen);
    const allIds = this.collectQuestionIds(next);
    // The service had to fall back to repeats, i.e. the pool is exhausted: start
    // the rotation over from this round. Growing the list forever would instead
    // leave every later round empty.
    let reused = false;
    const fresh: string[] = [];
    for (let i = 0; i < allIds.length; i++) {
      if (seen.indexOf(allIds[i]) >= 0) {
        reused = true;
      } else if (fresh.indexOf(allIds[i]) < 0) {
        fresh.push(allIds[i]);
      }
    }
    this.seenQuestionIds = reused ? allIds : seen.concat(fresh);
    this.session = next;
    this.currentIndex = 0;
    this.isFinished = false;
    // The round just handed out consumed whatever the pool had; ask for more so
    // the *next* tap has something new to show.
    this.prepareNextRound();
  }

  private collectQuestionIds(session: AdaptivePracticeSession): string[] {
    const ids: string[] = [];
    for (let i = 0; i < session.questions.length; i++) {
      const id = session.questions[i].id;
      if (ids.indexOf(id) < 0) {
        ids.push(id);
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

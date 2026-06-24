/*
 * Copyright (c) 2025 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 */

import { AdaptivePracticeService } from '../service/AdaptivePracticeService';
import { ErrorAttributionService } from '../service/ErrorAttributionService';
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
  private practiceService: AdaptivePracticeService;
  private attributionService: ErrorAttributionService;

  constructor() {
    this.practiceService = new AdaptivePracticeService();
    this.attributionService = new ErrorAttributionService();
    this.session = this.practiceService.generateSession();
    this.currentIndex = 0;
    this.isFinished = false;
    this.attributionUpdatedCount = 0;
  }

  resetSession(): void {
    this.session = this.practiceService.generateSession();
    this.currentIndex = 0;
    this.isFinished = false;
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

  getOptionLabel(index: number): string {
    return String.fromCharCode(65 + index);
  }
}

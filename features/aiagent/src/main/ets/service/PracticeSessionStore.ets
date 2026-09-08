/*
 * Copyright (c) 2025 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import {
  AdaptivePracticeQuestion,
  AdaptivePracticeSession,
  KnowledgePracticeProfile,
  PracticeDifficulty,
} from '../viewmodel/AdaptivePracticeModels';

const PENDING_SESSION_KEY = 'PendingPracticeSession';

interface PracticeQuestionRecord {
  id: string;
  title: string;
  options: string[];
  correctIndex: number;
  knowledgeTag: string;
  difficulty: string;
  source: string;
  explanation: string;
  recommendation: string;
}

interface KnowledgeProfileRecord {
  tag: string;
  errorCount: number;
  mastery: number;
  priority: number;
  reason: string;
}

interface PracticeSessionRecord {
  id: string;
  questions: PracticeQuestionRecord[];
  profiles: KnowledgeProfileRecord[];
}

/**
 * Hands an agent-generated practice session to the practice page. The agent
 * (or the PRACTICE intent) stores the session in AppStorage; the practice
 * view model consumes it once on startup and clears the slot.
 */
export class PracticeSessionStore {
  savePendingSession(session: AdaptivePracticeSession): void {
    const questions: PracticeQuestionRecord[] = [];
    for (const q of session.questions) {
      const record: PracticeQuestionRecord = {
        id: q.id,
        title: q.title,
        options: q.options,
        correctIndex: q.correctIndex,
        knowledgeTag: q.knowledgeTag,
        difficulty: q.difficulty,
        source: q.source,
        explanation: q.explanation,
        recommendation: q.recommendation,
      };
      questions.push(record);
    }

    const profiles: KnowledgeProfileRecord[] = [];
    for (const p of session.profiles) {
      const record: KnowledgeProfileRecord = {
        tag: p.tag,
        errorCount: p.errorCount,
        mastery: p.mastery,
        priority: p.priority,
        reason: p.reason,
      };
      profiles.push(record);
    }

    const record: PracticeSessionRecord = {
      id: session.id,
      questions: questions,
      profiles: profiles,
    };
    AppStorage.setOrCreate(PENDING_SESSION_KEY, JSON.stringify(record));
  }

  /** Consumes the pending session; returns null when none is stored or broken. */
  loadPendingSession(): AdaptivePracticeSession | null {
    let json = '';
    try {
      json = AppStorage.get<string>(PENDING_SESSION_KEY) || '';
    } catch (e) {
      return null;
    }
    if (json.length === 0) {
      return null;
    }
    // Consume immediately so the next manual entry regenerates fresh.
    AppStorage.setOrCreate(PENDING_SESSION_KEY, '');

    try {
      const record = JSON.parse(json) as PracticeSessionRecord;
      const questions: AdaptivePracticeQuestion[] = [];
      for (const r of record.questions) {
        questions.push(new AdaptivePracticeQuestion(
          r.id,
          r.title,
          r.options,
          r.correctIndex,
          r.knowledgeTag,
          this.parseDifficulty(r.difficulty),
          r.source,
          r.explanation,
          r.recommendation,
        ));
      }
      const profiles: KnowledgePracticeProfile[] = [];
      for (const r of record.profiles) {
        profiles.push(new KnowledgePracticeProfile(r.tag, r.errorCount, r.mastery, r.priority, r.reason));
      }
      if (questions.length === 0) {
        return null;
      }
      return new AdaptivePracticeSession(record.id, questions, profiles);
    } catch (e) {
      return null;
    }
  }

  private parseDifficulty(raw: string): PracticeDifficulty {
    if (raw === PracticeDifficulty.MEDIUM) {
      return PracticeDifficulty.MEDIUM;
    }
    if (raw === PracticeDifficulty.HARD) {
      return PracticeDifficulty.HARD;
    }
    return PracticeDifficulty.BASIC;
  }
}

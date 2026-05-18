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
  LearningAnalysisData,
  ScoreTrendItem,
  KnowledgePoint,
  CourseProgressItem,
} from './ChatModels';
import { DataCollectService } from '../service/DataCollectService';

@Observed
export class AnalysisViewModel {
  analysisData: LearningAnalysisData;
  isDataLoaded: boolean;
  private dataCollectService: DataCollectService;

  constructor() {
    this.dataCollectService = new DataCollectService();
    this.isDataLoaded = false;
    this.analysisData = {
      totalExams: 0,
      avgScore: 0,
      scoreTrend: [],
      knowledgePoints: [],
      courseProgress: [],
      weakPoints: [],
      strengths: [],
    };
  }

  loadAnalysisData(): void {
    const snapshot = this.dataCollectService.collectAllData();
    this.analysisData = this.dataCollectService.analyzeData(snapshot);
    this.isDataLoaded = true;
  }

  refreshAnalysisData(): void {
    this.loadAnalysisData();
  }

  getScoreLevel(score: number): string {
    if (score >= 90) {
      return '优秀';
    }
    if (score >= 80) {
      return '良好';
    }
    if (score >= 70) {
      return '中等';
    }
    if (score >= 60) {
      return '及格';
    }
    return '需提升';
  }

  getScoreLevelColor(score: number): string {
    if (score >= 90) {
      return '#10B981';
    }
    if (score >= 80) {
      return '#1A56DB';
    }
    if (score >= 70) {
      return '#F59E0B';
    }
    if (score >= 60) {
      return '#F97316';
    }
    return '#EF4444';
  }

  getMasteryColor(mastery: number): string {
    if (mastery >= 80) {
      return '#10B981';
    }
    if (mastery >= 50) {
      return '#F59E0B';
    }
    return '#EF4444';
  }
}

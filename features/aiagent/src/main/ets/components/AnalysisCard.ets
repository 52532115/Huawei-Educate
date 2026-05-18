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

import { LearningAnalysisData, ScoreTrendItem, KnowledgePoint, CourseProgressItem } from '../viewmodel/ChatModels';

@Component
export struct AnalysisCard {
  @Prop analysisData: LearningAnalysisData;

  build() {
    Column() {
      Text('📊 学习分析报告')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1A56DB')
        .margin({ bottom: 12 });

      this.ScoreOverview();
      Divider().strokeWidth(0.5).color('#E5E7EB').margin({ top: 8, bottom: 8 });
      this.KnowledgePointsSection();
      Divider().strokeWidth(0.5).color('#E5E7EB').margin({ top: 8, bottom: 8 });
      this.CourseProgressSection();
      Divider().strokeWidth(0.5).color('#E5E7EB').margin({ top: 8, bottom: 8 });
      this.WeakAndStrengthSection();
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
    .border({ width: 1, color: '#BFDBFE' });
  }

  @Builder
  ScoreOverview() {
    Row() {
      Column() {
        Text(`${this.analysisData.avgScore}`)
          .fontSize(36)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.getScoreColor(this.analysisData.avgScore));
        Text('平均分')
          .fontSize(12)
          .fontColor('#6B7280');
      }
      .width('40%');

      Column({ space: 4 }) {
        Text(`共 ${this.analysisData.totalExams} 次考试`)
          .fontSize(12)
          .fontColor('#374151');
        ForEach(this.analysisData.scoreTrend, (item: ScoreTrendItem) => {
          Row({ space: 8 }) {
            Text(item.examName)
              .fontSize(11)
              .fontColor('#6B7280')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: 80 });
            Text(`${item.score}分`)
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor('#333333');
          };
        }, (item: ScoreTrendItem) => item.examName);
      }
      .width('60%')
      .padding({ left: 12 });
    }
    .width('100%')
    .alignItems(VerticalAlign.Center);
  }

  @Builder
  KnowledgePointsSection() {
    Column({ space: 6 }) {
      Text('知识点掌握情况')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor('#374151')
        .margin({ bottom: 4 });

      ForEach(this.analysisData.knowledgePoints, (kp: KnowledgePoint) => {
        Row() {
          Text(kp.name)
            .fontSize(12)
            .fontColor('#374151')
            .width(80);

          Progress({
            value: kp.mastery,
            total: 100,
            type: ProgressType.Capsule,
          })
            .width('100%')
            .height(8)
            .color(this.getMasteryColor(kp.mastery))
            .layoutWeight(1);

          Text(`${kp.mastery}%`)
            .fontSize(11)
            .fontColor(this.getMasteryColor(kp.mastery))
            .fontWeight(FontWeight.Medium)
            .width(36)
            .textAlign(TextAlign.End);
        }
        .width('100%');
      }, (kp: KnowledgePoint) => kp.name);
    }
    .width('100%');
  }

  @Builder
  CourseProgressSection() {
    Column({ space: 6 }) {
      Text('课程学习进度')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor('#374151')
        .margin({ bottom: 4 });

      ForEach(this.analysisData.courseProgress, (cp: CourseProgressItem) => {
        Row() {
          Column() {
            Text(cp.courseName)
              .fontSize(12)
              .fontColor('#374151')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width(100);
            Text(cp.teacher)
              .fontSize(10)
              .fontColor('#9CA3AF');
          };

          Progress({
            value: cp.progress,
            total: 100,
            type: ProgressType.Capsule,
          })
            .width('100%')
            .height(6)
            .color('#10B981')
            .layoutWeight(1);

          Text(`${cp.progress}%`)
            .fontSize(11)
            .fontColor('#6B7280')
            .width(36)
            .textAlign(TextAlign.End);
        }
        .width('100%');
      }, (cp: CourseProgressItem) => cp.courseName);
    }
    .width('100%');
  }

  @Builder
  WeakAndStrengthSection() {
    Column({ space: 4 }) {
      if (this.analysisData.weakPoints.length > 0) {
        Row() {
          Text('⚠ 薄弱环节：')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor('#EF4444');
          Text(this.analysisData.weakPoints.join('、'))
            .fontSize(12)
            .fontColor('#EF4444')
            .layoutWeight(1);
        };
      }

      if (this.analysisData.strengths.length > 0) {
        Row() {
          Text('✅ 优势领域：')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor('#10B981');
          Text(this.analysisData.strengths.join('、'))
            .fontSize(12)
            .fontColor('#10B981')
            .layoutWeight(1);
        };
      }
    }
    .width('100%');
  }

  private getScoreColor(score: number): string {
    if (score >= 80) {
      return '#10B981';
    }
    if (score >= 60) {
      return '#F59E0B';
    }
    return '#EF4444';
  }

  private getMasteryColor(mastery: number): string {
    if (mastery >= 80) {
      return '#10B981';
    }
    if (mastery >= 50) {
      return '#F59E0B';
    }
    return '#EF4444';
  }
}

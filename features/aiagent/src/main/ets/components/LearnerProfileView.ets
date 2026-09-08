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

import { StyleConstants } from '@safe/basic';
import { promptAction } from '@kit.ArkUI';
import { LearnerProfileStore } from '../service/LearnerProfileStore';

/**
 * "AI 眼中的你" — visualizes the learner profile the AI tutor has built
 * across sessions. Read-only; the only action is resetting the profile.
 */
@Component
export struct LearnerProfileView {
  @StorageProp('topRectHeight') topRectHeight: number = 0;
  @State weakPoints: string[] = [];
  @State strengths: string[] = [];
  @State focusTopics: string[] = [];
  @State examCount: number = 0;
  @State avgScore: number = 0;
  @State totalStudyTime: number = 0;
  @State analysisSummaries: string[] = [];
  @State updatedAt: number = 0;
  pathStack: NavPathStack = AppStorage.get('pathStack') as NavPathStack;

  aboutToAppear(): void {
    this.load();
  }

  private load(): void {
    const profile = new LearnerProfileStore().loadProfile();
    this.weakPoints = [...profile.weakPoints];
    this.strengths = [...profile.strengths];
    this.focusTopics = [...profile.focusTopics];
    this.examCount = profile.examCount;
    this.avgScore = profile.avgScore;
    this.totalStudyTime = profile.totalStudyTime;
    this.analysisSummaries = [...profile.analysisSummaries];
    this.updatedAt = profile.updatedAt;
  }

  private isEmpty(): boolean {
    return this.weakPoints.length === 0 && this.strengths.length === 0 &&
      this.focusTopics.length === 0 && this.examCount === 0 &&
      this.totalStudyTime === 0 && this.analysisSummaries.length === 0;
  }

  private formatStudyTime(): string {
    if (this.totalStudyTime < 60) {
      return `${this.totalStudyTime}分钟`;
    }
    const hours = Math.floor(this.totalStudyTime / 60);
    const minutes = this.totalStudyTime % 60;
    return minutes > 0 ? `${hours}小时${minutes}分` : `${hours}小时`;
  }

  private formatUpdateTime(): string {
    if (this.updatedAt <= 0) {
      return '';
    }
    const date = new Date(this.updatedAt);
    const month = (date.getMonth() + 1).toString().padStart(2, '0');
    const day = date.getDate().toString().padStart(2, '0');
    const hours = date.getHours().toString().padStart(2, '0');
    const minutes = date.getMinutes().toString().padStart(2, '0');
    return `${date.getFullYear()}-${month}-${day} ${hours}:${minutes}`;
  }

  private handleReset(): void {
    AlertDialog.show({
      title: '重置档案',
      message: '确定要清空 AI 助教对你的全部记忆吗？清空后无法恢复。',
      primaryButton: {
        value: '取消',
        action: () => {
        },
      },
      secondaryButton: {
        value: '清空',
        fontColor: '#FF4444',
        action: () => {
          new LearnerProfileStore().clearProfile();
          this.load();
          promptAction.showToast({ message: '档案已重置', duration: 1500 });
        },
      },
    });
  }

  build() {
    NavDestination() {
      Column() {
        // --- Header ---
        Row() {
          Button('←')
            .fontSize(24)
            .fontColor('#1A1A1A')
            .width(40)
            .height(40)
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              this.pathStack.pop();
            });

          Text('AI 眼中的你')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor('#1F2937')
            .layoutWeight(1)
            .textAlign(TextAlign.Center);

          Button('重置')
            .fontSize(13)
            .fontColor('#9CA3AF')
            .height(32)
            .backgroundColor(Color.Transparent)
            .visibility(this.isEmpty() ? Visibility.Hidden : Visibility.Visible)
            .onClick(() => {
              this.handleReset();
            });
        }
        .width(StyleConstants.FULL_WIDTH)
        .height(48)
        .padding({ left: 16, right: 16 })
        .backgroundColor('#FFFFFF')
        .border({ width: { bottom: 0.5 }, color: '#E5E7EB' });

        if (this.isEmpty()) {
          // --- Empty state ---
          Column({ space: 12 }) {
            Text('🤖').fontSize(48);
            Text('AI 助教还不够了解你')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor('#1F2937');
            Text('去和 AI 助教聊聊你的学习情况吧\n我会慢慢记住你的薄弱点、优势和进步')
              .fontSize(13)
              .fontColor('#6B7280')
              .textAlign(TextAlign.Center)
              .lineHeight(20);
            Button('去找 AI 助教聊聊')
              .fontSize(14)
              .fontColor('#FFFFFF')
              .height(40)
              .padding({ left: 24, right: 24 })
              .margin({ top: 8 })
              .backgroundColor('#1A56DB')
              .borderRadius(20)
              .onClick(() => {
                this.pathStack.pop();
              });
          }
          .width(StyleConstants.FULL_WIDTH)
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center);
        } else {
          Scroll() {
            Column({ space: 12 }) {
              // --- 学习概况 ---
              Column() {
                Row() {
                  Text('📊 学习概况').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#1F2937');
                  Blank();
                  Text(this.formatUpdateTime())
                    .fontSize(11)
                    .fontColor('#9CA3AF');
                }
                .width('100%');

                Row() {
                  this.StatItem(`${this.examCount}`, '考试次数');
                  this.StatItem(`${this.avgScore}`, '平均分');
                  this.StatItem(this.formatStudyTime(), '累计学习');
                }
                .width('100%')
                .margin({ top: 12 });
              }
              .width('100%')
              .padding(16)
              .backgroundColor('#FFFFFF')
              .borderRadius(16);

              // --- 薄弱点 ---
              this.TagCard('🎯 需要加强', this.weakPoints, '#FEF2F2', '#DC2626', '还没有记录薄弱点，多做几次练习或分析吧');

              // --- 优势 ---
              this.TagCard('✅ 优势领域', this.strengths, '#F0FDF4', '#16A34A', '还没有记录优势领域');

              // --- 近期练习 ---
              this.TagCard('📝 近期练习', this.focusTopics, '#EFF6FF', '#1D4ED8', '还没有练习记录，去刷一组题吧');

              // --- 分析记忆 ---
              Column() {
                Text('🧠 AI 的分析记忆')
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#1F2937')
                  .width('100%');

                if (this.analysisSummaries.length === 0) {
                  Text('分析过学习情况后，结论会记录在这里')
                    .fontSize(13)
                    .fontColor('#9CA3AF')
                    .width('100%')
                    .margin({ top: 8 });
                } else {
                  ForEach(this.analysisSummaries, (summary: string, index: number) => {
                    Text(`${index + 1}. ${summary}`)
                      .fontSize(13)
                      .fontColor('#4B5563')
                      .lineHeight(20)
                      .width('100%')
                      .margin({ top: 8 });
                  }, (summary: string, index: number) => `${index}_${summary.length}`);
                }
              }
              .width('100%')
              .padding(16)
              .backgroundColor('#FFFFFF')
              .borderRadius(16);

              Text('档案仅保存在本机，由你的真实学习数据与 AI 助教的历史分析自动生成，可随时重置。')
                .fontSize(11)
                .fontColor('#9CA3AF')
                .textAlign(TextAlign.Center)
                .width('100%')
                .padding({ left: 24, right: 24, top: 4, bottom: 16 });
            }
            .width('92%')
            .padding({ top: 16 });
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.None);
        }
      }
      .width(StyleConstants.FULL_WIDTH)
      .height(StyleConstants.FULL_HEIGHT)
      .backgroundColor('#F3F4F6');
    }
    .hideTitleBar(true)
    .padding({ top: this.getUIContext().px2vp(this.topRectHeight) });
  }

  @Builder
  StatItem(value: string, label: string) {
    Column({ space: 4 }) {
      Text(value)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1A56DB')
        .maxLines(1);
      Text(label)
        .fontSize(11)
        .fontColor('#6B7280');
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center);
  }

  @Builder
  TagCard(title: string, tags: string[], bgColor: string, textColor: string, emptyText: string) {
    Column() {
      Text(title)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor('#1F2937')
        .width('100%');

      if (tags.length === 0) {
        Text(emptyText)
          .fontSize(13)
          .fontColor('#9CA3AF')
          .width('100%')
          .margin({ top: 8 });
      } else {
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach(tags, (tag: string) => {
            Text(tag)
              .fontSize(12)
              .fontColor(textColor)
              .backgroundColor(bgColor)
              .borderRadius(14)
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .margin({ right: 8, top: 8 });
          }, (tag: string) => tag);
        }
        .width('100%');
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FFFFFF')
    .borderRadius(16);
  }
}

@Builder
export function LearnerProfileViewBuilder() {
  LearnerProfileView();
}

/*
 * Copyright (c) 2025 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 */

import { promptAction } from '@kit.ArkUI';
import { AdaptivePracticeViewModel } from '../viewmodel/AdaptivePracticeViewModel';
import {
  AdaptivePracticeQuestion,
  KnowledgePracticeProfile,
  PracticeSessionSummary,
} from '../viewmodel/AdaptivePracticeModels';

@Component
export struct AdaptivePracticeView {
  @StorageProp('topRectHeight') topRectHeight: number = 0;
  @StorageProp('bottomRectHeight') bottomRectHeight: number = 0;
  @State questions: AdaptivePracticeQuestion[] = [];
  @State profiles: KnowledgePracticeProfile[] = [];
  @State focusProfiles: KnowledgePracticeProfile[] = [];
  @State currentIndex: number = 0;
  @State isFinished: boolean = false;
  @State answeredCount: number = 0;
  @State correctCount: number = 0;
  @State summary: PracticeSessionSummary = new PracticeSessionSummary();
  @State attributionUpdatedCount: number = 0;
  private vm: AdaptivePracticeViewModel = new AdaptivePracticeViewModel();
  pathStack: NavPathStack = AppStorage.get('pathStack') as NavPathStack;

  aboutToAppear(): void {
    this.syncState();
  }

  private syncState(): void {
    this.questions = [...this.vm.session.questions];
    this.profiles = [...this.vm.session.profiles];
    this.focusProfiles = this.profiles.slice(0, Math.min(3, this.profiles.length));
    this.currentIndex = this.vm.currentIndex;
    this.isFinished = this.vm.isFinished;
    this.answeredCount = this.vm.getAnsweredCount();
    this.correctCount = this.vm.getCorrectCount();
    this.summary = this.vm.getSummary();
    this.attributionUpdatedCount = this.vm.attributionUpdatedCount;
  }

  build() {
    NavDestination() {
      Column() {
        this.Header();

        if (this.isFinished) {
          this.SummaryView(this.summary);
        } else if (this.questions.length === 0) {
          this.EmptyView();
        } else {
          this.PracticeContent(this.questions[this.currentIndex]);
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#F5F7FB');
    }
    .hideTitleBar(true)
    .padding({
      top: this.getUIContext().px2vp(this.topRectHeight),
      bottom: this.getUIContext().px2vp(this.bottomRectHeight),
    });
  }

  @Builder
  Header() {
    Row({ space: 8 }) {
      Button('←')
        .fontSize(20)
        .fontColor('#1F2937')
        .width(40)
        .height(40)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.pathStack.pop();
        });

      Column() {
        Text('AI 自适应练习')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#111827');
        Text(`${this.answeredCount}/${this.questions.length} 已完成 · ${this.correctCount} 正确`)
          .fontSize(11)
          .fontColor('#6B7280')
          .margin({ top: 2 });
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);

      Button('换一组')
        .fontSize(13)
        .fontColor('#1A56DB')
        .height(34)
        .backgroundColor('#E6F0FF')
        .borderRadius(17)
        .onClick(() => {
          this.vm.resetSession();
          this.syncState();
        });
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor('#FFFFFF')
    .border({ width: { bottom: 0.5 }, color: '#E5E7EB' });
  }

  @Builder
  PracticeContent(question: AdaptivePracticeQuestion) {
    Scroll() {
      Column({ space: 12 }) {
        this.FocusPanel();
        this.QuestionCard(question);
        this.ActionBar(question);
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 14, bottom: 24 });
    }
    .layoutWeight(1)
    .scrollBar(BarState.Off);
  }

  @Builder
  FocusPanel() {
    Column({ space: 8 }) {
      Row() {
        Text('本轮重点')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor('#111827');
        Blank();
        Button('归因错题本')
          .fontSize(12)
          .fontColor('#D97706')
          .height(30)
          .backgroundColor('#FEF3C7')
          .borderRadius(15)
          .onClick(() => {
            this.handleRunAttribution();
          });
      }
      .width('100%');

      ForEach(this.focusProfiles, (profile: KnowledgePracticeProfile) => {
        Row() {
          Column() {
            Text(profile.tag)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor('#374151')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis });
            Text(profile.reason)
              .fontSize(11)
              .fontColor('#9CA3AF')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 2 });
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1);

          Text(`${profile.mastery}%`)
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getMasteryColor(profile.mastery));
        }
        .width('100%')
        .padding({ top: 8, bottom: 8 })
        .border({ width: { bottom: 0.5 }, color: '#F3F4F6' });
      }, (profile: KnowledgePracticeProfile) => profile.tag);

      if (this.attributionUpdatedCount > 0) {
        Text(`已为 ${this.attributionUpdatedCount} 道错题补充智能归因`)
          .fontSize(11)
          .fontColor('#D97706')
          .width('100%');
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
    .shadow({ radius: 8, color: '#08000000', offsetY: 2 });
  }

  @Builder
  QuestionCard(question: AdaptivePracticeQuestion) {
    Column({ space: 12 }) {
      Row() {
        Text(`${this.currentIndex + 1}/${this.questions.length}`)
          .fontSize(12)
          .fontColor('#1A56DB')
          .fontWeight(FontWeight.Bold)
          .backgroundColor('#E6F0FF')
          .borderRadius(12)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 });
        Text(question.knowledgeTag)
          .fontSize(12)
          .fontColor('#047857')
          .backgroundColor('#D1FAE5')
          .borderRadius(12)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .margin({ left: 8 });
        Text(question.difficulty)
          .fontSize(12)
          .fontColor('#7C3AED')
          .backgroundColor('#EDE9FE')
          .borderRadius(12)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .margin({ left: 8 });
      }
      .width('100%');

      Text(question.title)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor('#111827')
        .lineHeight(26)
        .width('100%');

      Column({ space: 10 }) {
        ForEach(question.options, (option: string, index: number) => {
          Row({ space: 10 }) {
            Text(this.vm.getOptionLabel(index))
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.getOptionLabelColor(question, index))
              .width(28)
              .height(28)
              .textAlign(TextAlign.Center)
              .backgroundColor(this.getOptionLabelBg(question, index))
              .borderRadius(14);
            Text(option)
              .fontSize(14)
              .fontColor(this.getOptionTextColor(question, index))
              .layoutWeight(1)
              .lineHeight(20);
          }
          .width('100%')
          .padding(12)
          .backgroundColor(this.getOptionBg(question, index))
          .borderRadius(10)
          .border({ width: 1, color: this.getOptionBorder(question, index) })
          .onClick(() => {
            this.vm.selectOption(index);
            this.syncState();
          });
        }, (option: string, index: number) => `${index}_${option}`);
      }
      .width('100%');

      if (question.isSubmitted) {
        this.AnswerAnalysis(question);
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
    .shadow({ radius: 10, color: '#08000000', offsetY: 3 });
  }

  @Builder
  AnswerAnalysis(question: AdaptivePracticeQuestion) {
    Column({ space: 8 }) {
      Text(question.selectedIndex === question.correctIndex ? '回答正确' : '智能归因')
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(question.selectedIndex === question.correctIndex ? '#047857' : '#DC2626')
        .width('100%');

      Text(question.explanation)
        .fontSize(13)
        .fontColor('#374151')
        .lineHeight(21)
        .width('100%');

      if (question.attribution) {
        Column({ space: 6 }) {
          Text(`${question.attribution.causeLabel} · 置信度 ${question.attribution.confidence}%`)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor('#92400E');
          Text(question.attribution.evidence)
            .fontSize(12)
            .fontColor('#6B7280')
            .lineHeight(18);
          Text(question.attribution.nextAction)
            .fontSize(12)
            .fontColor('#92400E')
            .lineHeight(18);
        }
        .width('100%')
        .padding(10)
        .backgroundColor('#FFFBEB')
        .borderRadius(8);
      }

      if (question.syncedToErrorBook) {
        Text('已同步到错题本')
          .fontSize(11)
          .fontColor('#1A56DB')
          .width('100%');
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#F9FAFB')
    .borderRadius(10);
  }

  @Builder
  ActionBar(question: AdaptivePracticeQuestion) {
    Row({ space: 10 }) {
      Button('上一题')
        .fontSize(14)
        .fontColor('#4B5563')
        .height(42)
        .layoutWeight(1)
        .backgroundColor('#FFFFFF')
        .borderRadius(10)
        .enabled(this.currentIndex > 0)
        .onClick(() => {
          this.vm.previousQuestion();
          this.syncState();
        });

      Button(question.isSubmitted ? (this.currentIndex === this.questions.length - 1 ? '完成练习' : '下一题') : '提交答案')
        .fontSize(14)
        .fontColor('#FFFFFF')
        .height(42)
        .layoutWeight(2)
        .backgroundColor(question.selectedIndex >= 0 ? '#1A56DB' : '#9CA3AF')
        .borderRadius(10)
        .onClick(() => {
          if (question.isSubmitted) {
            this.vm.nextQuestion();
          } else {
            const submitted = this.vm.submitCurrent();
            if (!submitted) {
              promptAction.showToast({ message: '请先选择一个答案' });
            }
          }
          this.syncState();
        });
    }
    .width('100%');
  }

  @Builder
  SummaryView(summary: PracticeSessionSummary) {
    Scroll() {
      Column({ space: 14 }) {
        Column({ space: 6 }) {
          Text(`${summary.score}`)
            .fontSize(52)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getScoreColor(summary.score));
          Text(`本轮正确 ${summary.correctCount}/${summary.totalCount}`)
            .fontSize(14)
            .fontColor('#6B7280');
        }
        .width('100%')
        .padding({ top: 30, bottom: 24 })
        .backgroundColor('#FFFFFF')
        .borderRadius(12);

        Column({ space: 10 }) {
          Text('练习结论')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor('#111827')
            .width('100%');
          Text(summary.advice)
            .fontSize(14)
            .fontColor('#374151')
            .lineHeight(22)
            .width('100%');

          if (summary.weakTags.length > 0) {
            Text(`待加强：${summary.weakTags.join('、')}`)
              .fontSize(13)
              .fontColor('#DC2626')
              .width('100%');
          }
          if (summary.masteredTags.length > 0) {
            Text(`表现较好：${summary.masteredTags.join('、')}`)
              .fontSize(13)
              .fontColor('#047857')
              .width('100%');
          }
        }
        .width('100%')
        .padding(16)
        .backgroundColor('#FFFFFF')
        .borderRadius(12);

        Row({ space: 10 }) {
          Button('再练一组')
            .fontSize(14)
            .fontColor('#FFFFFF')
            .height(44)
            .layoutWeight(1)
            .backgroundColor('#1A56DB')
            .borderRadius(10)
            .onClick(() => {
              this.vm.resetSession();
              this.syncState();
            });

          Button('打开错题本')
            .fontSize(14)
            .fontColor('#1A56DB')
            .height(44)
            .layoutWeight(1)
            .backgroundColor('#E6F0FF')
            .borderRadius(10)
            .onClick(() => {
              AppStorage.setOrCreate('currentTabIndex', 4);
              this.pathStack.clear();
            });
        }
        .width('100%');
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 18, bottom: 24 });
    }
    .layoutWeight(1)
    .scrollBar(BarState.Off);
  }

  @Builder
  EmptyView() {
    Column({ space: 12 }) {
      Text('暂无练习题')
        .fontSize(16)
        .fontColor('#6B7280');
      Button('重新生成')
        .fontSize(14)
        .fontColor('#FFFFFF')
        .backgroundColor('#1A56DB')
        .borderRadius(10)
        .onClick(() => {
          this.vm.resetSession();
          this.syncState();
        });
    }
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center);
  }

  private handleRunAttribution(): void {
    const count = this.vm.runErrorBookAttribution();
    this.syncState();
    promptAction.showToast({ message: count > 0 ? `已补充 ${count} 道错题归因` : '错题本暂无需要补充的归因' });
  }

  private getOptionBg(question: AdaptivePracticeQuestion, index: number): string {
    if (!question.isSubmitted) {
      return question.selectedIndex === index ? '#E6F0FF' : '#FFFFFF';
    }
    if (index === question.correctIndex) {
      return '#ECFDF5';
    }
    if (index === question.selectedIndex) {
      return '#FEF2F2';
    }
    return '#FFFFFF';
  }

  private getOptionBorder(question: AdaptivePracticeQuestion, index: number): string {
    if (!question.isSubmitted) {
      return question.selectedIndex === index ? '#1A56DB' : '#E5E7EB';
    }
    if (index === question.correctIndex) {
      return '#10B981';
    }
    if (index === question.selectedIndex) {
      return '#EF4444';
    }
    return '#E5E7EB';
  }

  private getOptionLabelBg(question: AdaptivePracticeQuestion, index: number): string {
    if (!question.isSubmitted) {
      return question.selectedIndex === index ? '#1A56DB' : '#F3F4F6';
    }
    if (index === question.correctIndex) {
      return '#10B981';
    }
    if (index === question.selectedIndex) {
      return '#EF4444';
    }
    return '#F3F4F6';
  }

  private getOptionTextColor(question: AdaptivePracticeQuestion, index: number): string {
    if (!question.isSubmitted && question.selectedIndex === index) {
      return '#1A56DB';
    }
    if (question.isSubmitted && (index === question.correctIndex || index === question.selectedIndex)) {
      return '#111827';
    }
    return '#374151';
  }

  private getOptionLabelColor(question: AdaptivePracticeQuestion, index: number): string {
    if (!question.isSubmitted && question.selectedIndex === index) {
      return '#FFFFFF';
    }
    if (question.isSubmitted && (index === question.correctIndex || index === question.selectedIndex)) {
      return '#FFFFFF';
    }
    return '#374151';
  }

  private getMasteryColor(mastery: number): string {
    if (mastery >= 80) {
      return '#047857';
    }
    if (mastery >= 60) {
      return '#D97706';
    }
    return '#DC2626';
  }

  private getScoreColor(score: number): string {
    if (score >= 85) {
      return '#047857';
    }
    if (score >= 60) {
      return '#D97706';
    }
    return '#DC2626';
  }
}

@Builder
export function AdaptivePracticeViewBuilder() {
  AdaptivePracticeView();
}

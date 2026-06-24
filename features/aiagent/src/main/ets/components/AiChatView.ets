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
import { ChatViewModel } from '../viewmodel/ChatViewModel';
import { AnalysisViewModel } from '../viewmodel/AnalysisViewModel';
import { ChatMessage, MessageRole, MessageStatus, LearningAnalysisData } from '../viewmodel/ChatModels';
import { ChatBubble } from './ChatBubble';
import { AnalysisCard } from './AnalysisCard';
import { RecommendQuestions } from './RecommendQuestions';
import { AiConstants } from '../utils/AiConstants';

@Component
export struct AiChatView {
  @StorageProp('topRectHeight') topRectHeight: number = 0;
  @StorageProp('bottomRectHeight') bottomRectHeight: number = 0;
  @StorageProp('triggerErrorAnalysis') @Watch('onTriggerErrorAnalysis') triggerErrorAnalysis: boolean = false;
  @StorageProp('triggerErrorAttribution') @Watch('onTriggerErrorAttribution') triggerErrorAttribution: boolean = false;
  @State inputText: string = '';
  @State showRecommend: boolean = true;
  @State messages: ChatMessage[] = [];
  @State isSending: boolean = false;
  @State isReceiving: boolean = false;
  @State sessionCount: number = 1;
  private chatVM: ChatViewModel = new ChatViewModel();
  private analysisVM: AnalysisViewModel = new AnalysisViewModel();
  scroller: Scroller = new Scroller();
  pathStack: NavPathStack = AppStorage.get('pathStack') as NavPathStack;

  aboutToAppear(): void {
    this.analysisVM.loadAnalysisData();
    this.syncState();
    this.chatVM.setStateChangeCallback(() => {
      this.syncState();
    });
    this.checkTriggerErrorAnalysis();
    this.checkTriggerErrorAttribution();
  }

  private syncState(): void {
    this.messages = [...this.chatVM.currentSession.messages];
    this.isSending = this.chatVM.isLoading;
    this.isReceiving = this.chatVM.isStreaming;
    this.sessionCount = this.chatVM.sessionList.length;
  }

  onTriggerErrorAnalysis(): void {
    this.checkTriggerErrorAnalysis();
  }

  private checkTriggerErrorAnalysis(): void {
    if (this.triggerErrorAnalysis) {
      AppStorage.setOrCreate('triggerErrorAnalysis', false);
      this.showRecommend = false;
      this.chatVM.requestErrorBookAnalysis();
    }
  }

  onTriggerErrorAttribution(): void {
    this.checkTriggerErrorAttribution();
  }

  private checkTriggerErrorAttribution(): void {
    if (this.triggerErrorAttribution) {
      AppStorage.setOrCreate('triggerErrorAttribution', false);
      this.showRecommend = false;
      this.chatVM.requestErrorAttribution();
    }
  }

  build() {
    NavDestination() {
      Column() {
        // --- Header ---
        Row() {
          Button('📋')
            .fontSize(18)
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              this.chatVM.newSession();
              this.showRecommend = true;
            });

          Text('AI 助教')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor('#1F2937')
            .layoutWeight(1)
            .textAlign(TextAlign.Center);

          Text(`${this.sessionCount}`)
            .fontSize(10)
            .fontColor('#FFFFFF')
            .backgroundColor('#1A56DB')
            .borderRadius(10)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .visibility(this.sessionCount > 1 ? Visibility.Visible : Visibility.Hidden);
        }
        .width(StyleConstants.FULL_WIDTH)
        .height(48)
        .padding({ left: 16, right: 16 })
        .backgroundColor('#FFFFFF')
        .border({ width: { bottom: 0.5 }, color: '#E5E7EB' });

        // --- Message List / Welcome ---
        Column() {
          if (this.messages.length <= 1) {
            // Welcome content
            Column({ space: 16 }) {
              Text('🤖').fontSize(48);
              Text('你好！我是你的 AI 学习助教')
                .fontSize(16).fontWeight(FontWeight.Medium).fontColor('#1F2937');
              Text('我可以帮你分析学习成绩、解答问题、制定学习计划')
                .fontSize(13).fontColor('#6B7280').textAlign(TextAlign.Center);

              Column({ space: 10 }) {
                Row({ space: 8 }) {
                  this.ActionButton('📊 学习分析', '#1A56DB', () => {
                    this.showRecommend = false;
                    const data = this.analysisVM.analysisData;
                    this.chatVM.requestAnalysis(data);
                  });
                  this.ActionButton('📝 错题分析', '#F56C6C', () => {
                    this.showRecommend = false;
                    this.chatVM.requestErrorBookAnalysis();
                  });
                  this.ActionButton('🧠 自适应练习', '#7C3AED', () => {
                    this.pathStack.pushPathByName('AdaptivePracticeView', null);
                  });
                }
                .width('100%');

                Row({ space: 8 }) {
                  this.ActionButton('💡 学习建议', '#10B981', () => {
                    this.showRecommend = false;
                    this.chatVM.sendMessage('请根据我的学习情况给我一些学习建议', true);
                  });
                  this.ActionButton('📸 拍照搜题', '#8B5CF6', () => {
                    this.pathStack.pushPathByName('PhotoSearchView', null);
                  });
                  this.ActionButton('🔎 智能归因', '#D97706', () => {
                    this.showRecommend = false;
                    this.chatVM.requestErrorAttribution();
                  });
                }
                .width('100%');
              }
              .width('92%');
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center);
          } else {
            // Message list
            Scroll(this.scroller) {
              Column({ space: 0 }) {
                ForEach(this.messages, (msg: ChatMessage, index: number) => {
                  Column() {
                    if (msg.role === MessageRole.ANALYSIS && msg.analysisData) {
                      AnalysisCard({ analysisData: msg.analysisData });
                    }
                    if (msg.role === MessageRole.USER || msg.role === MessageRole.AI ||
                        msg.role === MessageRole.ANALYSIS) {
                      ChatBubble({ message: msg });
                    }
                    if (msg.role === MessageRole.ANALYSIS && msg.content) {
                      Text('📋 以上为学习数据分析结果')
                        .fontSize(11).fontColor('#9CA3AF')
                        .textAlign(TextAlign.Center).width('100%').padding(4);
                    }
                  };
                }, (msg: ChatMessage) => msg.id + '_' + msg.status + '_' + msg.content.length);

                if (this.isReceiving) {
                  Row() {
                    LoadingProgress().width(16).height(16).color('#1A56DB');
                    Text('正在思考...').fontSize(12).fontColor('#9CA3AF').margin({ left: 8 });
                  }
                  .width('100%').padding(12);
                }
              }
              .width(StyleConstants.FULL_WIDTH);
            }
            .scrollBar(BarState.Off)
            .scrollable(ScrollDirection.Vertical)
            .edgeEffect(EdgeEffect.None)
            .layoutWeight(1);
          }
        }
        .layoutWeight(1);

        // --- Recommend Questions ---
        if (this.showRecommend && this.messages.length <= 1) {
          RecommendQuestions({
            questions: this.chatVM.getRecommendQuestions(),
            onQuestionClick: (question: string) => {
              if (question.includes('错题本')) {
                this.showRecommend = false;
                if (question.includes('智能归因')) {
                  this.chatVM.requestErrorAttribution();
                } else {
                  this.chatVM.requestErrorBookAnalysis();
                }
              } else if (question.includes('自适应练习')) {
                this.pathStack.pushPathByName('AdaptivePracticeView', null);
              } else {
                this.doSend(question);
              }
            },
          });
        }

        // --- Input Area ---
        Row({ space: 8 }) {
          TextInput({ text: $$this.inputText, placeholder: '输入你的问题...' })
            .placeholderColor('#9CA3AF')
            .fontSize(14)
            .backgroundColor('#F3F4F6')
            .borderRadius(20)
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .layoutWeight(1)
            .maxLines(4)
            .onSubmit(() => {
              this.doSend(this.inputText);
            });

          Button() {
            Text('发送').fontSize(12).fontColor('#FFFFFF');
          }
          .width(56)
          .height(40)
          .borderRadius(20)
          .backgroundColor(this.inputText.trim().length > 0 ? '#1A56DB' : '#D1D5DB')
          .enabled(this.inputText.trim().length > 0 && !this.isSending)
          .onClick(() => {
            this.doSend(this.inputText);
          });
        }
        .width(StyleConstants.FULL_WIDTH)
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .backgroundColor('#FFFFFF')
        .border({ width: { top: 0.5 }, color: '#E5E7EB' });
      }
      .width(StyleConstants.FULL_WIDTH)
      .height(StyleConstants.FULL_HEIGHT)
      .backgroundColor('#F3F4F6');
    }
    .hideTitleBar(true)
    .padding({ top: this.getUIContext().px2vp(this.topRectHeight) });
  }

  @Builder
  ActionButton(label: string, bgColor: string, action: () => void) {
    Button() {
      Text(label).fontSize(12).maxLines(1);
    }
    .height(36)
    .layoutWeight(1)
    .backgroundColor(bgColor)
    .borderRadius(18)
    .onClick(action);
  }

  private doSend(text: string): void {
    if (text.trim() === '' || this.isSending) {
      return;
    }
    this.inputText = '';
    this.showRecommend = false;
    this.chatVM.sendMessage(text.trim());
    this.scrollToBottom();
  }

  private scrollToBottom(): void {
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 100);
  }
}

@Builder
export function AiChatViewBuilder() {
  AiChatView();
}

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
  @State inputText: string = '';
  @State showRecommend: boolean = true;
  scroller: Scroller = new Scroller();
  private chatVM: ChatViewModel = new ChatViewModel();
  private analysisVM: AnalysisViewModel = new AnalysisViewModel();

  aboutToAppear(): void {
    this.analysisVM.loadAnalysisData();
  }

  build() {
    NavDestination() {
      Column() {
        this.HeaderBar();

        Column() {
          this.MessageListView();
        }
        .layoutWeight(1);

        if (this.showRecommend && this.chatVM.currentSession.messages.length <= 1) {
          RecommendQuestions({
            questions: this.chatVM.getRecommendQuestions(),
            onQuestionClick: (question: string) => {
              this.handleSend(question);
            },
          });
        }

        this.InputAreaView();
      }
      .width(StyleConstants.FULL_WIDTH)
      .height(StyleConstants.FULL_HEIGHT)
      .backgroundColor('#F3F4F6');
    }
    .hideTitleBar(true)
    .padding({ top: this.getUIContext().px2vp(this.topRectHeight) });
  }

  @Builder
  HeaderBar() {
    Row() {
      Image($r('app.media.ic_public_cards_filled'))
        .width(22)
        .height(22)
        .fillColor('#333333')
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

      Text(`${this.chatVM.sessionList.length}`)
        .fontSize(10)
        .fontColor('#FFFFFF')
        .backgroundColor('#1A56DB')
        .borderRadius(10)
        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        .visibility(this.chatVM.sessionList.length > 1 ? Visibility.Visible : Visibility.Hidden);
    }
    .width(StyleConstants.FULL_WIDTH)
    .height(48)
    .padding({ left: 16, right: 16 })
    .backgroundColor('#FFFFFF')
    .border({ width: { bottom: 0.5 }, color: '#E5E7EB' });
  }

  @Builder
  MessageListView() {
    Column() {
      if (this.chatVM.currentSession.messages.length <= 1) {
        this.WelcomeView();
      } else {
        Scroll(this.scroller) {
          Column({ space: 0 }) {
            ForEach(
              this.chatVM.currentSession.messages,
              (msg: ChatMessage, index: number) => {
                if (index === 0 && msg.role === MessageRole.AI) {
                  this.WelcomeView();
                } else {
                  Column() {
                    if (msg.role === MessageRole.ANALYSIS && msg.analysisData) {
                      AnalysisCard({
                        analysisData: msg.analysisData,
                      });
                    }

                    if (msg.content) {
                      ChatBubble({
                        message: msg,
                      });
                    }

                    if (msg.role === MessageRole.ANALYSIS && msg.content) {
                      Text('📋 以上为学习数据分析结果')
                        .fontSize(11)
                        .fontColor('#9CA3AF')
                        .textAlign(TextAlign.Center)
                        .width('100%')
                        .padding(4);
                    }
                  };
                }
              },
              (msg: ChatMessage) => msg.id,
            );

            if (this.chatVM.isStreaming) {
              Row() {
                LoadingProgress()
                  .width(16)
                  .height(16)
                  .color('#1A56DB');
                Text('正在思考...')
                  .fontSize(12)
                  .fontColor('#9CA3AF')
                  .margin({ left: 8 });
              }
              .width('100%')
              .padding(12);
            }
          }
          .width(StyleConstants.FULL_WIDTH);
        }
        .scrollBar(BarState.Off)
        .scrollable(ScrollDirection.Vertical)
        .edgeEffect(EdgeEffect.None)
        .layoutWeight(1)
        .onDidScroll(() => {
          // Scrolled to the end
        });
      }
    }
    .height('100%')
    .onClick(() => {
      this.showRecommend = false;
    });
  }

  @Builder
  WelcomeView() {
    Column({ space: 16 }) {
      Text('🤖')
        .fontSize(48);

      Text('你好！我是你的 AI 学习助教')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor('#1F2937');

      Text('我可以帮你分析学习成绩、解答问题、制定学习计划')
        .fontSize(13)
        .fontColor('#6B7280')
        .textAlign(TextAlign.Center);

      Row({ space: 12 }) {
        Button() {
          Text('📊 学习分析')
            .fontSize(13)
        }
        .backgroundColor('#1A56DB')
        .borderRadius(20)
        .onClick(() => {
          this.showRecommend = false;
          const data = this.analysisVM.analysisData;
          this.chatVM.requestAnalysis(data);
        });

        Button() {
          Text('📝 学习建议')
            .fontSize(13)
        }
        .backgroundColor('#10B981')
        .borderRadius(20)
        .onClick(() => {
          this.showRecommend = false;
          this.chatVM.sendMessage('请根据我的学习情况给我一些学习建议', true);
        });
      };
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center);
  }

  @Builder
  InputAreaView() {
    Row({ space: 8 }) {
      TextInput({ text: this.inputText, placeholder: '输入你的问题...' })
        .placeholderColor('#9CA3AF')
        .fontSize(14)
        .backgroundColor('#F3F4F6')
        .borderRadius(20)
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .layoutWeight(1)
        .maxLines(4)
        .onChange((value: string) => {
          this.inputText = value;
        })
        .onSubmit(() => {
          this.handleSend(this.inputText);
        });

      Button() {
        Text('发送')
          .fontSize(12)
          .fontColor('#FFFFFF');
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .backgroundColor(this.inputText.trim() ? '#1A56DB' : '#D1D5DB')
      .enabled(this.inputText.trim().length > 0 && !this.chatVM.isLoading)
      .onClick(() => {
        this.handleSend(this.inputText);
      });
    }
    .width(StyleConstants.FULL_WIDTH)
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor('#FFFFFF')
    .border({ width: { top: 0.5 }, color: '#E5E7EB' });
  }

  private handleSend(text: string): void {
    if (text.trim() === '' || this.chatVM.isLoading) {
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

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
import { ChatViewModel } from '../viewmodel/ChatViewModel';
import { AnalysisViewModel } from '../viewmodel/AnalysisViewModel';
import { ChatMessage, ChatSession, MessageRole, MessageStatus, LearningAnalysisData } from '../viewmodel/ChatModels';
import { ChatBubble } from './ChatBubble';
import { AnalysisCard } from './AnalysisCard';
import { RecommendQuestions } from './RecommendQuestions';
import { AiConstants } from '../utils/AiConstants';
import { ApiKeyStore } from '../service/ApiKeyStore';
import { AiBackend, AiBackendStore } from '../service/AiBackend';

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
  @State showSessionSheet: boolean = false;
  @State sessionList: ChatSession[] = [];
  @State currentSessionId: string = '';
  @State showSettingsSheet: boolean = false;
  @State apiKeyInput: string = '';
  @State apiKeyConfigured: boolean = false;
  @State backendUrlInput: string = '';
  @State backendTokenInput: string = '';
  @State usingBackend: boolean = false;
  @State probing: boolean = false;
  @State probeOk: boolean = false;
  @State probeTitle: string = '';
  @State probeDetail: string = '';
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
    this.sessionList = [...this.chatVM.sessionList];
    this.currentSessionId = this.chatVM.currentSession.id;
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
              this.showSessionSheet = true;
            });

          Text('AI 助教')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor('#1F2937')
            .layoutWeight(1)
            .textAlign(TextAlign.Center);

          Button('👤')
            .fontSize(18)
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              this.pathStack.pushPathByName('LearnerProfileView', null);
            });

          Button('⚙️')
            .fontSize(16)
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              const backend = AiBackend.current();
              this.backendUrlInput = backend.getBaseUrl();
              this.backendTokenInput = backend.getToken();
              this.usingBackend = backend.isConfigured();
              this.apiKeyInput = new ApiKeyStore().getKey();
              this.apiKeyConfigured = this.apiKeyInput.length > 0;
              // Start each visit with no verdict: the previous one described a
              // different moment, and stale reassurance is worse than none.
              this.clearProbe();
              this.showSettingsSheet = true;
            });

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
        .border({ width: { bottom: 0.5 }, color: '#E5E7EB' })
        // A node can only carry one bindSheet, so the settings sheet lives here
        // and the session sheet on the root Column below. Chaining both on the
        // same node made them overwrite each other: 📋 flipped the state but the
        // panel only appeared after ⚙️ forced a rebuild.
        .bindSheet($$this.showSettingsSheet, this.SettingsSheet(), {
          height: 420,
          dragBar: true,
        });

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
                        msg.role === MessageRole.ANALYSIS || msg.role === MessageRole.STEP) {
                      ChatBubble({ message: msg });
                    }
                    if (msg.role === MessageRole.AI && msg.action === 'start_practice') {
                      Button('🚀 开始自适应练习')
                        .fontSize(13)
                        .fontColor('#FFFFFF')
                        .backgroundColor('#7C3AED')
                        .borderRadius(18)
                        .height(36)
                        .padding({ left: 16, right: 16 })
                        .margin({ left: 12, top: 4, bottom: 8 })
                        .onClick(() => {
                          this.pathStack.pushPathByName('AdaptivePracticeView', null);
                        });
                    }
                    if (msg.role === MessageRole.ANALYSIS && msg.content) {
                      Text('📋 以上为学习数据分析结果')
                        .fontSize(11).fontColor('#9CA3AF')
                        .textAlign(TextAlign.Center).width('100%').padding(4);
                    }
                  };
                }, (msg: ChatMessage) => msg.id + '_' + msg.status + '_' + msg.content.length + (msg.stepDone ? '_done' : ''));

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

          if (this.isSending || this.isReceiving) {
            Button() {
              Text('⏹ 停止').fontSize(12).fontColor('#FFFFFF');
            }
            .height(40)
            .borderRadius(20)
            .padding({ left: 14, right: 14 })
            .backgroundColor('#EF4444')
            .onClick(() => {
              this.chatVM.cancelRequest();
            });
          } else {
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
        }
        .width(StyleConstants.FULL_WIDTH)
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .backgroundColor('#FFFFFF')
        .border({ width: { top: 0.5 }, color: '#E5E7EB' });
      }
      .width(StyleConstants.FULL_WIDTH)
      .height(StyleConstants.FULL_HEIGHT)
      .backgroundColor('#F3F4F6')
      .bindSheet($$this.showSessionSheet, this.SessionSheet(), {
        height: 520,
        dragBar: true,
      });
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

  /** Saving needs at least one usable way to reach a model. */
  private canSaveSettings(): boolean {
    return this.backendUrlInput.trim().length > 0 || this.apiKeyInput.trim().length > 0;
  }

  /** Probing needs a backend address, and only one run at a time. */
  private canProbe(): boolean {
    return !this.probing && this.backendUrlInput.trim().length > 0;
  }

  /**
   * Drops a stale verdict. Once the address or token changes, the previous
   * result describes values that are no longer on screen — leaving it up would
   * read as "this is fine" for a configuration that was never tested.
   */
  private clearProbe(): void {
    this.probeTitle = '';
    this.probeDetail = '';
  }

  private saveSettings(): void {
    const backend = new AiBackend(this.backendUrlInput, this.backendTokenInput);
    new AiBackendStore().save(backend);
    const key = this.apiKeyInput.trim();
    if (key.length > 0) {
      new ApiKeyStore().saveKey(key);
    }
    this.usingBackend = backend.isConfigured();
    this.apiKeyConfigured = key.length > 0;
    this.showSettingsSheet = false;
    let mode = '直连模式';
    if (this.usingBackend) {
      mode = '后端模式';
    }
    promptAction.showToast({ message: `AI 配置已保存（${mode}）`, duration: 1500 });
  }

  /** The indicator shown in the sheet header. */
  private settingsStatusText(): string {
    if (this.usingBackend) {
      return '后端模式 ✓';
    }
    return this.apiKeyConfigured ? '直连模式 ✓' : '未配置';
  }

  /**
   * Probes the values currently typed in the sheet — not the saved ones — so
   * a typo can be caught before it is committed.
   *
   * Without this, the only feedback the sheet could give came from sending a
   * real message and reading whatever error came back, which lumps "wrong
   * address", "wrong token" and "the backend is down" into one sentence.
   */
  private async runProbe(): Promise<void> {
    if (this.probing) {
      return;
    }
    this.probing = true;
    this.probeTitle = '';
    this.probeDetail = '';
    try {
      const target = new AiBackend(this.backendUrlInput, this.backendTokenInput);
      const result = await this.chatVM.probeBackend(target);
      this.probeOk = result.ok;
      this.probeTitle = result.title;
      this.probeDetail = result.detail;
    } catch (e) {
      this.probeOk = false;
      this.probeTitle = '测试失败';
      this.probeDetail = '探测过程中出现异常，请确认网络可用后重试。';
    }
    this.probing = false;
  }

  @Builder
  SettingsSheet() {
    Scroll() {
      Column({ space: 14 }) {
        Row() {
          Text('AI 设置')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#1F2937');
          Blank();
          Text(this.settingsStatusText())
            .fontSize(12)
            .fontColor(this.usingBackend || this.apiKeyConfigured ? '#10B981' : '#9CA3AF');
        }
        .width('100%')
        .height(36)
        .padding({ left: 16, right: 16 });

        // The backend comes first because it is the recommended way to run this:
        // the model key stays on a server the team controls, and the device
        // never holds a vendor credential at all.
        Text('后端地址（推荐）\n填写团队部署的 AI 后端，例如 https://ai.example.edu。\n配置后模型 Key 保存在服务端，本机不再需要 API Key。')
          .fontSize(12)
          .fontColor('#6B7280')
          .lineHeight(18)
          .width('90%');

        TextInput({ text: this.backendUrlInput, placeholder: 'https://...' })
          .fontSize(13)
          .backgroundColor('#FFFFFF')
          .borderRadius(10)
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .width('90%')
          .onChange((value: string) => {
            this.backendUrlInput = value;
            this.clearProbe();
          });

        TextInput({ text: this.backendTokenInput, placeholder: '应用令牌（后端未启用鉴权可留空）' })
          .fontSize(13)
          .type(InputType.Password)
          .showPasswordIcon(true)
          .backgroundColor('#FFFFFF')
          .borderRadius(10)
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .width('90%')
          .onChange((value: string) => {
            this.backendTokenInput = value;
            this.clearProbe();
          });

        // Tests what is typed above, not what was saved — otherwise a typo
        // would only surface later, as a failed chat message.
        Row({ space: 10 }) {
          Button(this.probing ? '测试中…' : '测试连接')
            .fontSize(13)
            .fontColor(this.canProbe() ? '#1A56DB' : '#9CA3AF')
            .height(34)
            .padding({ left: 18, right: 18 })
            .backgroundColor('#EFF6FF')
            .borderRadius(17)
            .enabled(this.canProbe())
            .onClick(() => {
              this.runProbe();
            });

          if (this.probeTitle.length > 0) {
            Text(this.probeTitle)
              .fontSize(12)
              .fontColor(this.probeOk ? '#10B981' : '#DC2626');
          }
        }
        .width('90%')
        .justifyContent(FlexAlign.Start);

        if (this.probeDetail.length > 0) {
          Text(this.probeDetail)
            .fontSize(12)
            .fontColor('#6B7280')
            .lineHeight(18)
            .width('90%');
        }

        Divider()
          .width('90%')
          .color('#E5E7EB');

        Text('API Key（仅直连时使用）\n不填后端地址时，助手直接调用 DeepSeek。Key 仅保存在本机沙箱，不会打包进安装包。')
          .fontSize(12)
          .fontColor('#6B7280')
          .lineHeight(18)
          .width('90%');

        TextInput({ text: this.apiKeyInput, placeholder: 'sk-...' })
          .fontSize(13)
          .type(InputType.Password)
          .showPasswordIcon(true)
          .backgroundColor('#FFFFFF')
          .borderRadius(10)
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .width('90%')
          .onChange((value: string) => {
            this.apiKeyInput = value;
          });

        Row({ space: 12 }) {
          Button('清除')
            .fontSize(13)
            .fontColor('#DC2626')
            .height(36)
            .padding({ left: 20, right: 20 })
            .backgroundColor('#FEF2F2')
            .borderRadius(18)
            .onClick(() => {
              // Both are cleared together: leaving a stale API Key behind after
              // switching to a backend would keep a vendor credential on the
              // device for no reason.
              new AiBackendStore().clear();
              new ApiKeyStore().clearKey();
              this.backendUrlInput = '';
              this.backendTokenInput = '';
              this.usingBackend = false;
              this.apiKeyInput = '';
              this.apiKeyConfigured = false;
              promptAction.showToast({ message: 'AI 配置已清除', duration: 1500 });
            });

          Button('保存')
            .fontSize(13)
            .fontColor('#FFFFFF')
            .height(36)
            .padding({ left: 28, right: 28 })
            .backgroundColor(this.canSaveSettings() ? '#1A56DB' : '#D1D5DB')
            .borderRadius(18)
            .enabled(this.canSaveSettings())
            .onClick(() => {
              this.saveSettings();
            });
        }
        .width('90%')
        .justifyContent(FlexAlign.Center);
      }
      .width(StyleConstants.FULL_WIDTH)
      .padding({ top: 12, bottom: 24 });
    }
    .width(StyleConstants.FULL_WIDTH)
    .height('100%')
    .backgroundColor('#F3F4F6')
    .align(Alignment.Top);
  }

  @Builder
  SessionSheet() {
    Column() {
      // --- Sheet header ---
      Row() {
        Text('会话历史')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#1F2937');
        Blank();
        Button('＋ 新会话')
          .fontSize(13)
          .fontColor('#1A56DB')
          .height(32)
          .padding({ left: 12, right: 12 })
          .backgroundColor('#EFF6FF')
          .borderRadius(16)
          .onClick(() => {
            this.showSessionSheet = false;
            this.chatVM.newSession();
            this.showRecommend = true;
          });
      }
      .width('100%')
      .height(48)
      .padding({ left: 16, right: 16 });

      // --- Session list ---
      List({ space: 8 }) {
        ForEach(this.sessionList, (session: ChatSession) => {
          ListItem() {
            Row({ space: 10 }) {
              Column({ space: 3 }) {
                Row() {
                  Text(session.title)
                    .fontSize(14)
                    .fontColor(session.id === this.currentSessionId ? '#1A56DB' : '#1F2937')
                    .fontWeight(session.id === this.currentSessionId ? FontWeight.Medium : FontWeight.Normal)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1);
                  Text(`${session.messages.length} 条`)
                    .fontSize(11)
                    .fontColor('#9CA3AF');
                }
                .width('100%');

                Text(this.formatSessionTime(session))
                  .fontSize(11)
                  .fontColor('#9CA3AF');
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1);

              Button('🗑')
                .fontSize(15)
                .width(32)
                .height(32)
                .backgroundColor(Color.Transparent)
                .onClick(() => {
                  this.confirmDeleteSession(session);
                });
            }
            .width('100%')
            .padding(12)
            .backgroundColor(session.id === this.currentSessionId ? '#EFF6FF' : '#FFFFFF')
            .borderRadius(12)
          }
          .onClick(() => {
            this.showSessionSheet = false;
            this.chatVM.switchSession(session.id);
            this.showRecommend = false;
          });
        }, (session: ChatSession) => session.id);
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 16, right: 16 })
      .scrollBar(BarState.Off);

      Text('删除会话后无法恢复；当前会话仅保存在本机。')
        .fontSize(11)
        .fontColor('#9CA3AF')
        .textAlign(TextAlign.Center)
        .width('100%')
        .padding({ top: 8, bottom: 16 });
    }
    .width(StyleConstants.FULL_WIDTH)
    .height('100%')
    .backgroundColor('#F3F4F6')
    .padding({ top: 8 });
  }

  private formatSessionTime(session: ChatSession): string {
    const ts = session.updateTime > 0 ? session.updateTime : session.createTime;
    const date = new Date(ts);
    const month = (date.getMonth() + 1).toString().padStart(2, '0');
    const day = date.getDate().toString().padStart(2, '0');
    const hours = date.getHours().toString().padStart(2, '0');
    const minutes = date.getMinutes().toString().padStart(2, '0');
    return `更新于 ${month}-${day} ${hours}:${minutes}`;
  }

  private confirmDeleteSession(session: ChatSession): void {
    AlertDialog.show({
      title: '删除会话',
      message: `确定要删除「${session.title}」吗？删除后无法恢复。`,
      primaryButton: {
        value: '取消',
        action: () => {
        },
      },
      secondaryButton: {
        value: '删除',
        fontColor: '#FF4444',
        action: () => {
          this.chatVM.deleteSession(session.id);
          this.showRecommend = true;
          this.showSessionSheet = false;
        },
      },
    });
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

/*
 *  Copyright (c) 2025 Huawei Device Co., Ltd.
 *  Licensed under the Apache License, Version 2.0 (the "License");
 *  you may not use this file except in compliance with the License.
 *  You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 *
 */

import { ResManager } from '@safe/basic';
import { addErrorModel } from '../viewmodel/MineLocalData';
import { createErrorModel } from '../viewmodel/MineErrorModel';
import { promptAction } from '@kit.ArkUI';

@Component
export struct MineAddErrorPage {
  @StorageProp('topRectHeight') topRectHeight: number = 0;
  pathStack: NavPathStack = AppStorage.get('pathStack') as NavPathStack;
  @State title: string = '';
  @State options: string[] = ['', ''];
  @State rightAnswer: number = 0;
  @State wrongAnswer: number = -1;
  @State userNote: string = '';
  @State mistakeReason: string = '';
  @State knowledgeTag: string = '';
  private tagLabels: string[] = ['A', 'B', 'C', 'D', 'E', 'F'];

  addOption(): void {
    if (this.options.length < 6) {
      this.options.push('');
    }
  }

  removeOption(index: number): void {
    if (this.options.length > 2) {
      this.options.splice(index, 1);
      if (this.rightAnswer >= this.options.length) {
        this.rightAnswer = this.options.length - 1;
      }
    }
  }

  canSave(): boolean {
    return this.title.trim().length > 0 &&
      this.options.every((o) => o.trim().length > 0) &&
      this.knowledgeTag.trim().length > 0;
  }

  saveError(): void {
    if (!this.canSave()) {
      promptAction.showToast({ message: '请填写完整信息（题目、选项、知识点标签为必填）', duration: 2000 });
      return;
    }

    const model = createErrorModel(
      this.title.trim(),
      this.options.map((o) => o.trim()),
      this.rightAnswer,
      this.wrongAnswer >= 0 ? this.wrongAnswer : undefined,
      this.userNote.trim(),
      this.mistakeReason.trim(),
      this.knowledgeTag.trim(),
    );

    addErrorModel(model);
    promptAction.showToast({ message: '添加成功', duration: 1500 });
    this.pathStack.pop();
  }

  build() {
    NavDestination() {
      Column() {
        // Header
        Row() {
          RelativeContainer() {
            Image(ResManager.getBackIcon())
              .width(ResManager.getVp_twenty())
              .height(ResManager.getVp_twenty())
              .alignRules({
                center: { anchor: '__container__', align: VerticalAlign.Center },
                left: { anchor: '__container__', align: HorizontalAlign.Start }
              })
              .id('back')
              .margin({ left: this.getUIContext().vp2px(5) })
              .onClick(() => {
                this.pathStack.pop();
              });
            Text('添加错题').alignRules({
              middle: { anchor: '__container__', align: HorizontalAlign.Center },
              center: { anchor: 'back', align: VerticalAlign.Center }
            }).fontWeight(FontWeight.Medium).fontColor('#333333').id('text');

            Text('保存')
              .fontColor('#409eff')
              .fontSize(16)
              .alignRules({
                center: { anchor: '__container__', align: VerticalAlign.Center },
                right: { anchor: '__container__', align: HorizontalAlign.End }
              })
              .id('save')
              .margin({ right: 16 })
              .onClick(() => {
                this.saveError();
              });
          };
        }
        .width('100%')
        .height(48)
        .backgroundColor(Color.White);

        // Form content
        Scroll() {
          Column({ space: 16 }) {
            // Section: Question title
            Column({ space: 8 }) {
              Text('题目内容')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor('#333333');
              TextArea({ text: this.title, placeholder: '请输入题目内容' })
                .height(80)
                .fontSize(15)
                .backgroundColor('#F5F5F5')
                .borderRadius(8)
                .padding(12)
                .onChange((value: string) => {
                  this.title = value;
                });
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start);

            // Section: Options
            Column({ space: 8 }) {
              Text('选项列表')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor('#333333');

              Column({ space: 8 }) {
                ForEach(this.options, (opt: string, index: number) => {
                  Row({ space: 8 }) {
                    Text(this.tagLabels[index])
                      .fontSize(14)
                      .fontWeight(FontWeight.Bold)
                      .fontColor('#409eff')
                      .width(24);

                    TextInput({ text: opt, placeholder: '选项 ' + this.tagLabels[index] })
                      .layoutWeight(1)
                      .height(40)
                      .fontSize(14)
                      .backgroundColor('#F5F5F5')
                      .borderRadius(6)
                      .padding({ left: 8, right: 8 })
                      .onChange((value: string) => {
                        this.options[index] = value;
                      });

                    if (this.options.length > 2) {
                      Text('-')
                        .fontSize(24)
                        .fontColor('#FF4444')
                        .width(30)
                        .textAlign(TextAlign.Center)
                        .onClick(() => {
                          this.removeOption(index);
                        });
                    }
                  }
                  .width('100%');
                }, (opt: string, index: number) => index.toString());

                if (this.options.length < 6) {
                  Row() {
                    Text('+ 添加选项')
                      .fontSize(13)
                      .fontColor('#409eff');
                  }
                  .width('100%')
                  .height(36)
                  .justifyContent(FlexAlign.Center)
                  .backgroundColor('#EBF5FF')
                  .borderRadius(6)
                  .border({ width: 1, color: '#C6E2FF', style: BorderStyle.Dashed })
                  .onClick(() => {
                    this.addOption();
                  });
                }
              };
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start);

            // Section: Correct answer
            Column({ space: 8 }) {
              Text('正确答案')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor('#333333');

              Row({ space: 12 }) {
                ForEach(this.options, (opt: string, index: number) => {
                  Row({ space: 4 }) {
                    Radio({
                      value: 'right_' + index,
                      group: 'rightAnswer',
                      indicatorType: RadioIndicatorType.TICK
                    })
                      .checked(this.rightAnswer === index)
                      .width(18)
                      .height(18)
                      .onChange((checked: boolean) => {
                        if (checked) {
                          this.rightAnswer = index;
                        }
                      });
                    Text(this.tagLabels[index])
                      .fontSize(14)
                      .fontColor('#333333');
                  };
                });
              };
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start);

            // Section: Wrong answer (optional)
            Column({ space: 8 }) {
              Text('你的错误选项（选填）')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor('#333333');

              Row({ space: 12 }) {
                ForEach(this.options, (opt: string, index: number) => {
                  Row({ space: 4 }) {
                    Radio({
                      value: 'wrong_' + index,
                      group: 'wrongAnswer',
                      indicatorType: RadioIndicatorType.TICK
                    })
                      .checked(this.wrongAnswer === index)
                      .width(18)
                      .height(18)
                      .onChange((checked: boolean) => {
                        if (checked) {
                          this.wrongAnswer = index;
                        }
                      });
                    Text(this.tagLabels[index])
                      .fontSize(14)
                      .fontColor('#333333');
                  };
                });
              };

              if (this.wrongAnswer >= 0) {
                Text('清除选择')
                  .fontSize(12)
                  .fontColor('#999999')
                  .margin({ top: 8 })
                  .onClick(() => {
                    this.wrongAnswer = -1;
                  });
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start);

            // Section: Knowledge tag
            Column({ space: 8 }) {
              Text('知识点标签')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor('#333333');
              TextInput({ text: this.knowledgeTag, placeholder: '例如：计算机网络、数据结构、操作系统' })
                .height(40)
                .fontSize(14)
                .backgroundColor('#F5F5F5')
                .borderRadius(6)
                .padding({ left: 8, right: 8 })
                .onChange((value: string) => {
                  this.knowledgeTag = value;
                });
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start);

            // Section: User notes
            Column({ space: 8 }) {
              Text('学习笔记')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor('#333333');
              TextArea({ text: this.userNote, placeholder: '记录这道题的知识点、解题技巧等' })
                .height(100)
                .fontSize(14)
                .backgroundColor('#F5F5F5')
                .borderRadius(8)
                .padding(12)
                .onChange((value: string) => {
                  this.userNote = value;
                });
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start);

            // Section: Mistake reasoning
            Column({ space: 8 }) {
              Text('错误思路分析')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor('#333333');
              TextArea({ text: this.mistakeReason, placeholder: '记录你的错误思路：当初为什么会选错？' })
                .height(100)
                .fontSize(14)
                .backgroundColor('#F5F5F5')
                .borderRadius(8)
                .padding(12)
                .onChange((value: string) => {
                  this.mistakeReason = value;
                });
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start);

            // Save button at bottom
            Button('保存错题')
              .width('100%')
              .height(46)
              .fontSize(16)
              .fontColor(Color.White)
              .backgroundColor(this.canSave() ? '#409eff' : '#C0C4CC')
              .borderRadius(8)
              .margin({ top: 8, bottom: 24 })
              .enabled(this.canSave())
              .onClick(() => {
                this.saveError();
              });
          }
          .padding({ left: 16, right: 16, top: 12 });
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.None);
      }
    }
    .hideTitleBar(true)
    .padding({ top: this.getUIContext().px2vp(this.topRectHeight) });
  }
}

@Builder
export function MineAddErrorPageBuilder() {
  MineAddErrorPage();
}

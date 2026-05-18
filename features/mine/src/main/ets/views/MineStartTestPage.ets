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
import { ERROR_MODELS } from '../viewmodel/MineLocalData';
import { AnswerModel, MineErrorModel } from '../viewmodel/MineErrorModel';
import { LogoutDialog } from './LogoutDialog';

// 考试总时长（单位毫秒）
const EXAM_DURATION = 30000;

@Component
export struct MineStartTestPage {
  @State format: string = 'mm:ss';
  @State isSubmitted: boolean = false;
  @State currentIndex: number = 0;
  @StorageProp('MyCount') count: number = 0;
  @StorageProp('Score') score: number = 0;
  @StorageProp('Time') time: number = 0;
  @StorageProp('topRectHeight') topRectHeight: number = 0;
  @StorageProp('bottomRectHeight') bottomRectHeight: number = 0;
  @State questionData: MineErrorModel[] = ERROR_MODELS;
  @State currentModel: MineErrorModel | undefined = undefined;
  textTimerController: TextTimerController = new TextTimerController();
  pathStack: NavPathStack = AppStorage.get('pathStack') as NavPathStack;
  elapsedTime: number = 0;
  tjDialog: CustomDialogController = new CustomDialogController({
    builder: LogoutDialog({
      confirm: () => {
        this.isSubmitted = true;
        this.pathStack.pushPathByName('MineTestResPage', null);
        for (let i = 1; i <= this.questionData.length; i++) {
          if (this.getValueByKey(i.toString()) === this.questionData[i-1].rightQues) {
            this.score += 10;
          }
        }
        for (let i = 0; i < ERROR_MODELS.length; i++) {
          ERROR_MODELS[i].answer = 0;
        }
        this.textTimerController.reset();
        AppStorage.setOrCreate('MyCount', 0);
        AppStorage.setOrCreate('Time', EXAM_DURATION - this.elapsedTime);
        AppStorage.setOrCreate('Score', this.score);
      },
      message: '是否提交试卷?'
    }),
    autoCancel: true,
    gridCount: 4,
    customStyle: false
  });
  private answerList: AnswerModel[] = [];
  private tagList: string[] = ['A', 'B', 'C', 'D'];

  aboutToAppear(): void {
    let myCount: number | undefined = AppStorage.get('MyCount');
    if (myCount !== undefined && myCount !== 0) {
      // AppStorage有值
      this.count = myCount;
    } else {
      this.count = 30000;
    }
    this.currentModel = ERROR_MODELS[this.currentIndex];
  }

  submit(force: Boolean): void {
    if (force) {
      this.isSubmitted = true;
      this.pathStack.pushPathByName('MineTestResPage', null);
      for (let i = 1; i <= this.questionData.length; i++) {
        if (this.getValueByKey(i.toString()) === this.questionData[i-1].rightQues) {
          this.score += 10;
        }
      }
      for (let i = 0; i < ERROR_MODELS.length; i++) {
        ERROR_MODELS[i].answer = 0;
      }
      this.textTimerController.reset();
      AppStorage.setOrCreate('MyCount', 0);
      AppStorage.setOrCreate('Score', this.score);
      AppStorage.setOrCreate('Time', EXAM_DURATION);
    } else {
      if (this.currentIndex >= ERROR_MODELS.length - 1) {
        this.tjDialog.open();
        return;
      }
      this.currentIndex += 1;
      this.currentModel = ERROR_MODELS[this.currentIndex];
    }
  }

  getValueByKey(key: string): number | undefined {
    const item = this.answerList.find(pair => pair.key === key);
    return item?.value;
  }

  build() {
    NavDestination() {
      Column() {
        Column() {
          Column() {
            TextTimer({ isCountDown: true, count: this.count, controller: this.textTimerController })
              .format(this.format)
              .fontColor(Color.Black)
              .fontSize(30)
              .onTimer((utc: number, elapsedTime: number) => {
                this.elapsedTime = this.count - elapsedTime * 1000;
                if (elapsedTime * 1000 === this.count) {
                  //倒计时结束
                  this.submit(true);
                }
              })
              .onAppear(() => {
                this.textTimerController.start();
              })
              .onDisAppear(() => {
                //页面切换，保存当前的值
                if (!this.isSubmitted) {
                  AppStorage.setOrCreate('MyCount', this.elapsedTime);
                } else {
                  AppStorage.setOrCreate('Score', 0);
                }
              });
          }
          .height(60)
          .justifyContent(FlexAlign.SpaceAround).margin({ left: 10, right: 10 });

          Column() {
            Row() {
              Text(this.currentModel!.key + '.')
                .fontSize(16)
                .fontWeight(400)
                .fontColor('rgba(0, 0, 0, 0.9)');
              Text(this.currentModel!.title)
                .fontSize(16)
                .fontWeight(400)
                .fontColor('rgba(0, 0, 0, 0.9)');
            }
            .width('100%');

            Column({ space: 8 }) {
              ForEach(this.currentModel!.option, ((item: string, index: number) => {
                Row() {
                  Radio({
                    value: `${index}`, group: `radioGroup${this.currentModel!.key}`,
                    indicatorType: RadioIndicatorType.TICK
                  })
                    .margin({ right: 10 })
                    .checked(this.currentModel!.answer === index + 1)
                    .height(20)
                    .width(20)
                    .onChange((isChecked: boolean) => {
                      if (isChecked) {
                        this.currentModel!.answer = index + 1;
                        this.answerList.push({ key: this.currentModel!.key, value: index });
                      }
                    });
                  Text(this.tagList[index] + '.')
                    .fontSize(16)
                    .fontWeight(400)
                    .fontColor('rgba(0, 0, 0, 0.9)');
                  Text(item)
                    .fontSize(16)
                    .fontWeight(400)
                    .fontColor('rgba(0, 0, 0, 0.9)');
                }
                .width('100%')
                .height(56)
                .borderRadius(8)
                .backgroundColor('rgba(0, 0, 0, 0.05)');
              }));
            }
            .alignItems(HorizontalAlign.Start)
            .margin({ top: 19 });
          }
          .width(this.getUIContext().px2vp(328 * 3.5))
          .backgroundColor(Color.White)
          .borderRadius(16)
          .padding(16)
          .margin({
            top: 8,
            left: 16,
            right: 16
          });

          Stack({ alignContent: Alignment.Bottom }) {
            Row() {
              Button('上一题', { buttonStyle: ButtonStyleMode.NORMAL })
                .width(106)
                .height(40)
                .borderRadius(20)
                .onClick(() => {
                  if (this.currentIndex > 0) {
                    this.currentIndex -= 1;
                    this.currentModel = ERROR_MODELS[this.currentIndex];
                  }
                })
                .margin({
                  bottom: 16,
                  left: 16
                });

              Text() {
                Span('试题').fontColor('#666666').fontSize(14);
                Span((this.currentIndex + 1).toString() + '/' + ERROR_MODELS.length.toString())
                  .fontColor('#333333')
                  .fontSize(14);
              }
              .margin({
                bottom: 16
              });

              Button((this.currentIndex + 1) === ERROR_MODELS.length ? '交卷' : '下一题',
                { buttonStyle: ButtonStyleMode.NORMAL })
                .width(106)
                .height(40)
                .borderRadius(20)
                .fontColor(Color.Blue)
                .onClick(() => {
                  this.submit(false);
                })
                .margin({
                  bottom: 16,
                  right: 16
                });
            }
            .alignItems(VerticalAlign.Center)
            .justifyContent(FlexAlign.SpaceBetween)
            .width('100%');
          }
          .width('100%')
          .layoutWeight(1);
        }.layoutWeight(1);

      }.width(StyleConstants.FULL_WIDTH)
      .height(StyleConstants.FULL_HEIGHT);
    }
    .title('考试标题xxxxx')
    .backgroundColor('#F1F3F5')
    .padding({
      top: this.getUIContext().px2vp(this.topRectHeight),
      bottom: this.getUIContext().px2vp(this.bottomRectHeight)
    });
  }
}

@Builder
export function MineStartTestPageBuilder() {
  MineStartTestPage();
}



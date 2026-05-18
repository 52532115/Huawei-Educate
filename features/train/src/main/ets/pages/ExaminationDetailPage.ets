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
import TrainConstants from '../common/constants/TrainConstants';
import { examinationDetailObj } from '../viewmodel/ExaminationInfoModel';
import { JSON } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';

interface GridItemType {
  img: Resource,
  name: string,
  value: string,
  code: string,
}

//培训列表info 枚举
enum ExaminationDetailInfoEnum {
  totalScore = '试卷总分',
  score = '及格分数',
  hours = '考试时长',
  topicNum = '题目数量'

}

@Component
export struct ExaminationDetailPage {
  @State gridList: GridItemType[] = [];
  count: number = (examinationDetailObj.examNum as number) - (examinationDetailObj.useExamNum as number);
  @StorageProp('topRectHeight') topRectHeight: number = 0;
  pathStack: NavPathStack = AppStorage.get('pathStack') as NavPathStack;

  build() {
    NavDestination() {
      Column() {
        Stack({
          alignContent: Alignment.TopStart
        }) {
          Image($r('app.media.ic_app_background'))
            .width('100%')
            .zIndex(0);

          Row() {
            Image($r('app.media.ic_back'))
              .width(this.getUIContext().px2vp(40 * 3.5))
              .height(this.getUIContext().px2vp(40 * 3.5))
              .borderRadius(20)
              .margin({ right: 6.5 })
              .onClick(() => {
                this.pathStack.pop();
              });
            Text('考试详情')
              .fontSize(20)
              .fontWeight(700)
              .fontFamily('HarmonyHeiTi');
          }
          .zIndex(2)
          .margin({
            top: 44,
            left: 16
          });

          Column() {
            Blank()
              .height(this.getUIContext().px2vp(96 * 3.5));
            Text('理论测试复习')
              .width(this.getUIContext().px2vp(328 * 3.5))
              .fontWeight(FontWeight.Bold)
              .fontSize(18)
              .fontFamily('HarmonyHeiTi')
              .textAlign(TextAlign.Start)
              .margin({
                top: 94,
                bottom: 14
              });

            Column() {
              Row() {
                Text('复习')
                  .fontSize(14)
                  .fontWeight(400)
                  .fontFamily('HarmonyOS Sans SC 2024');
                Text('全部已学 >')
                  .fontSize(14)
                  .fontWeight(400)
                  .fontFamily('HarmonyOS Sans SC 2024');
              }
              .width('100%')
              .padding(16)
              .justifyContent(FlexAlign.SpaceBetween);

              Stack() {
                Text()
                  .width(115)
                  .height(115)
                  .borderRadius(57.5)
                  .backgroundColor('rgba(83, 141, 255, 0.2)');
                Button('开始考试')
                  .width(95)
                  .height(95)
                  .fontColor(Color.White)
                  .fontSize(14)
                  .borderRadius(47.5)
                  .backgroundColor('rgba(10, 89, 247, 0.8)')
                  .onClick(() => {
                    this.pathStack.pushPathByName('MineStartTestPage', null);
                  });
              }
              .margin({
                bottom: 16
              });

              Grid() {
                ForEach(this.gridList, (item: GridItemType, index: number) => {
                  GridItem() {
                    Row() {
                      Column() {
                        Text(`${item.value}`)
                          .fontSize(16)
                          .fontWeight(500)
                          .fontFamily('HarmonyOS Sans SC 2024');
                        Text(item.name)
                          .fontColor($r('app.color.gray_color'))
                          .fontSize(14)
                          .fontWeight(400)
                          .fontFamily('HarmonyOS Sans SC 2024')
                          .margin({
                            top: 5
                          });
                      };
                    };
                  }
                  .height(60)
                  .width('100%')
                  .onClick(() => {
                    hilog.info(0x0001, '[Scan CPSample]', 'Promise scan result: %{public}s', JSON.stringify(index));
                  });
                }, (item: GridItemType) => JSON.stringify(item));
              }
              .width(this.getUIContext().px2vp(296 * 3.5))
              .height(60)
              .columnsTemplate('1fr 1fr 1fr 1fr');

              Row() {
                Column() {
                  Text('提示')
                    .fontSize(14)
                    .fontWeight(400)
                    .fontFamily('HarmonyOS Sans SC 2024')
                    .margin({
                      bottom: 4
                    });
                  Text(`本期考试已考${examinationDetailObj.useExamNum}次，还剩${this.count}次机会，最高分${examinationDetailObj.highScore}分`)
                    .fontSize(12)
                    .fontWeight(400)
                    .fontFamily('HarmonyOS Sans SC 2024')
                    .opacity(0.4);
                }
                .alignItems(HorizontalAlign.Start)
                .width(this.getUIContext().px2vp(177 * 3.5));

                Image($r('app.media.ic_pencil'))
                  .width(this.getUIContext().px2vp(66 * 3.5))
                  .height(this.getUIContext().px2vp(66 * 3.5))
                  .margin({
                    bottom: 14
                  });
              }
              .backgroundColor('rgba(10, 89, 247, 0.05)')
              .borderRadius(8)
              .width(this.getUIContext().px2vp(296 * 3.5))
              .height(this.getUIContext().px2vp(80 * 3.5))
              .padding(16)
              .justifyContent(FlexAlign.SpaceBetween)
              .margin({
                top: 24,
                bottom: 16
              });

            }
            .width(this.getUIContext().px2vp(328 * 3.5))
            .borderRadius(20)
            .backgroundColor(Color.White);
          }
          .zIndex(1)
          .width(TrainConstants.FULL_WIDTH)
          .height(TrainConstants.FULL_HEIGHT);
        }
        .width(TrainConstants.FULL_WIDTH)
        .height(TrainConstants.FULL_HEIGHT);
      }
      .width(TrainConstants.FULL_WIDTH)
      .height(TrainConstants.FULL_HEIGHT);
    }
    .hideTitleBar(true)
    .onReady(() => {
      for (const key of Object.keys(examinationDetailObj)) {
        if (key === 'totalScore') {
          let obj: GridItemType = {
            img: $r('app.media.course'),
            name: ExaminationDetailInfoEnum[key],
            value: `${Reflect.get(examinationDetailObj, key)}分`,
            code: key
          };
          this.gridList.push(obj);

        } else if (key === 'score') {
          let obj: GridItemType = {
            img: $r('app.media.course'),
            name: ExaminationDetailInfoEnum[key],
            value: `${Reflect.get(examinationDetailObj, key)}分`,
            code: key
          };
          this.gridList.push(obj);

        } else if (key === 'hours') {
          let obj: GridItemType = {
            img: $r('app.media.course'),
            name: ExaminationDetailInfoEnum[key],
            value: `${Reflect.get(examinationDetailObj, key)}秒`,
            code: key
          };
          this.gridList.push(obj);

        } else if (key === 'topicNum') {
          let obj: GridItemType = {
            img: $r('app.media.course'),
            name: ExaminationDetailInfoEnum[key],
            value: `${Reflect.get(examinationDetailObj, key)}题`,
            code: key
          };
          this.gridList.push(obj);
        }
      }
    });
  }
}

@Builder
export function ExaminationDetailPageBuilder() {
  ExaminationDetailPage();
}
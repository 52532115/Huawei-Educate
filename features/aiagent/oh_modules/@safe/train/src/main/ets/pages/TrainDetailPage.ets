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
import { TrainInfo, TrainList } from '../viewmodel/TrainInfoModel';
import { IntroductionComponent } from '../view/Introduction';
import { ExaminationComponent } from '../view/Examination';
import { CourseComponent } from '../view/Course';
import { IdInfo, NavInfo } from '../viewmodel/NavInfoModel';

@Component
export struct TrainDetailPage {
  @State currentIndex: number = 0;
  @State params: NavInfo = new NavInfo('培训', '');
  @State title: string = '详情';
  @StorageProp('topRectHeight') topRectHeight: number = 0;
  pathStack: NavPathStack = AppStorage.get('pathStack') as NavPathStack;
  private detailInfo: TrainInfo = new TrainInfo();
  private tabsController: TabsController = new TabsController();

  goToExaminationDetail() {
    this.pathStack.pushPathByName('ExaminationDetailPage', null);
  }

  @Builder
  TabBarBuilder(title: string, targetIndex: number) {
    Text(title)
      .fontSize(this.getUIContext().px2vp(14 * 3.5))
      .fontWeight(500)
      .fontFamily('HarmonyHeiTi')
      .fontColor(targetIndex === this.currentIndex ? '#FFFFFF' : '#000000')
      .width(this.getUIContext().px2vp(60 * 3.5))
      .height(this.getUIContext().px2vp(36 * 3.5))
      .borderRadius(this.getUIContext().px2vp(21 * 3.5))
      .textAlign(TextAlign.Center)
      .backgroundColor(targetIndex === this.currentIndex ? '#0A59F7' : '#E5E5E5')
      .padding(5)
      .border(targetIndex === this.currentIndex ? {
        width: { bottom: 2 },
        color: { bottom: $r('app.color.blue_text_color') },
        style: {
          bottom: BorderStyle.Solid
        }
      } : {
        width: { bottom: 0 }
      })
      .margin({ top: 12, right: 10 })
      .onClick(() => {
        this.tabsController.changeIndex(targetIndex);
      });
  }

  build() {
    NavDestination() {
      Column() {
        Column() {
          Text(this.detailInfo.title)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textAlign(TextAlign.Start)
            .fontSize(20)
            .fontWeight(700)
            .fontFamily('HarmonyHeiTi')
            .width(TrainConstants.FULL_WIDTH)
            .margin({
              top: 24
            })
            .lineHeight(27);
          Row() {
            Row() {
              Image(this.detailInfo.img)
                .width(80)
                .height(80)
                .borderRadius(12);
              Column() {
                Text(`已有${this.detailInfo.applyNum}报名`)
                  .textAlign(TextAlign.Start)
                  .fontColor($r('app.color.gray_color'))
                  .fontFamily('HarmonyHeiTi')
                  .fontWeight(400)
                  .fontSize(14)
                  .margin({
                    bottom: 10
                  })
                  .width(TrainConstants.FULL_WIDTH);
                Row() {
                  Text(`￥`)
                    .fontColor(Color.Red)
                    .fontWeight(700)
                    .fontFamily('HarmonyHeiTi')
                    .fontSize(18);
                  Text(`${this.detailInfo.money}`)
                    .fontColor(Color.Red)
                    .fontWeight(700)
                    .fontFamily('HarmonyHeiTi')
                    .fontSize(18);
                }
                .width(TrainConstants.FULL_WIDTH);
              }
              .margin({
                left: 10
              })
              .layoutWeight(1);

            }
            .layoutWeight(1);

            Text('取消报名')
              .padding({
                top: 6,
                bottom: 6,
                left: 10,
                right: 10
              })
              .fontColor('rgba(10, 89, 247, 1)')
              .fontSize(14)
              .fontWeight(500)
              .fontFamily('HarmonyHeiTi')
              .backgroundColor('#E5E5E5')
              .borderRadius(14);
          }
          .width(TrainConstants.FULL_WIDTH)
          .margin({
            top: 10,
            bottom: 12
          });

          //tab
          Flex({ direction: FlexDirection.Row }) {
            this.TabBarBuilder('简介', 0);
            this.TabBarBuilder('课程', 1);
            this.TabBarBuilder('考试', 2);
          };
        }
        .width(TrainConstants.FULL_WIDTH)
        .padding({
          top: 10,
          bottom: 10
        });

        //tab内容
        Column() {
          Tabs({ barPosition: BarPosition.End, controller: this.tabsController }) {
            TabContent() {
              //简介
              IntroductionComponent()
                .margin({ top: 10 })
                .width(TrainConstants.FULL_WIDTH)
                .height(TrainConstants.FULL_HEIGHT);
            };

            TabContent() {
              //课程
              CourseComponent()
                .width(TrainConstants.FULL_WIDTH)
                .height(TrainConstants.FULL_HEIGHT);
            };

            TabContent() {
              //考试  传方法过去
              ExaminationComponent({
                onClickItem: (): void => this.goToExaminationDetail()
              })
                .width(TrainConstants.FULL_WIDTH)
                .height(TrainConstants.FULL_HEIGHT);
            };

          }.onChange((index: number) => {
            this.currentIndex = index;
          })
          .width(TrainConstants.FULL_WIDTH)
          .height(TrainConstants.FULL_HEIGHT)
          .barHeight(0);
        }
        .layoutWeight(1);
      }
      .padding({ left: 16, right: 16 })
      .width(TrainConstants.FULL_WIDTH)
      .height(TrainConstants.FULL_HEIGHT);
    }
    .backgroundColor('#F1F3F5')
    .title(this.title)
    .padding({ top: this.getUIContext().px2vp(this.topRectHeight) })
    .onReady((ctx: NavDestinationContext) => {
      this.params = (ctx?.pathInfo?.param as NavInfo);
      this.title = this.params.title;
      let id = (JSON.parse(this.params.params) as IdInfo).id;
      this.detailInfo = TrainList.find(v => v.id === id) as TrainInfo;
    });
  }
}

@Builder
export function TrainDetailPageBuilder() {
  TrainDetailPage();
}
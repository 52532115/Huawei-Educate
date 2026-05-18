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

import { ResManager, StyleConstants } from '@safe/basic';

@Component
export struct MineTestResPage {
  @StorageProp('topRectHeight') topRectHeight: number = 0;
  @StorageProp('bottomRectHeight') bottomRectHeight: number = 0;
  @StorageProp('Time') time: number = 0;
  @StorageProp('Score') score: number = 0;
  scroller: Scroller = new Scroller();
  pathStack: NavPathStack = AppStorage.get('pathStack') as NavPathStack;

  @Styles
  cardStyle(){
    .width(StyleConstants.FULL_WIDTH)
    .backgroundColor(Color.White)
    .borderRadius(ResManager.getVp_twelve())
    .margin({ bottom: ResManager.getVp_twelve() })
    .shadow({ color: 'f5f5f5', radius: ResManager.getVp_twelve() });
  }

  build() {
    NavDestination() {
      Column() {
        Row({ space: 8 }) {
          Image($r('app.media.back'))
            .width(24)
            .height(24)
            .onClick(() => {
              this.pathStack.popToName('ExaminationDetailPage');
            });
          Text('考试结果')
            .fontSize(20)
            .fontWeight(700);
        }
        .width('100%')
        .height(this.getUIContext().vp2px(10))
        .padding({ left: 16, right: 16 });

        Stack({ alignContent: Alignment.Bottom }) {
          Stack({ alignContent: Alignment.Top }) {
            Image('')
              .width(StyleConstants.FULL_WIDTH)
              .height($r('app.float.personal_background_image_height'))
              .objectFit(ImageFit.Auto).backgroundColor(Color.Green);
            Flex({ direction: FlexDirection.Column }) {
              RelativeContainer() {
                Text('考试1').fontColor(Color.White).alignRules({
                  top: { anchor: '__container__', align: VerticalAlign.Top },
                  middle: { anchor: '__container__', align: HorizontalAlign.Center }
                }).offset({
                  y: 10
                }).id('title');

                Text() {
                  Span(`${this.score}   `).fontSize(30).fontColor(Color.Red);
                  Span('分').fontSize(20).fontColor(Color.Red);
                }.fontColor(Color.White).alignRules({
                  top: { anchor: 'title', align: VerticalAlign.Bottom },
                  middle: { anchor: '__container__', align: HorizontalAlign.Center }
                }).offset({
                  y: 30
                }).id('score');
              }
              .width(StyleConstants.FULL_WIDTH)
              .height(160);

              Text(this.score < 60 ? '未通过，再接再厉！' : '恭喜通过考试！')
                .alignRules({
                  top: { anchor: 'score', align: VerticalAlign.Bottom },
                  middle: { anchor: '__container__', align: HorizontalAlign.Center }
                })
                .fontSize(16)
                .fontWeight(FontWeight.Normal)
                .width(160)
                .height(40)
                .borderRadius(5)
                .textAlign(TextAlign.Center)
                .id('status')
                .offset({
                  y: -30
                })
                .width(StyleConstants.FULL_WIDTH)
                .height(20);

              Column() {
                Flex({
                  justifyContent: FlexAlign.SpaceEvenly,
                  alignItems: ItemAlign.Center
                }) {
                  Column() {
                    Text('答题用时').fontSize(12).fontColor('#666666');
                    Text(`${(this.time / 1000)}秒`).fontSize(16).fontColor('#333333');
                  }.justifyContent(FlexAlign.SpaceAround).height(60);

                  Column() {
                    Text('合格/总分')
                      .fontSize(12)
                      .fontColor('#666666');
                    Text(`${this.score}/100`)
                      .fontSize(16)
                      .fontColor('#333333');
                  }
                  .justifyContent(FlexAlign.SpaceAround)
                  .height(60);

                  Column() {
                    Text('剩余可考').fontSize(12).fontColor('#666666');
                    Text('992').fontSize(16).fontColor('#333333');
                  }.justifyContent(FlexAlign.SpaceAround).height(60);
                }
                .height($r('app.float.icon_dock_height'))
                .cardStyle();
              }.padding({
                left: ResManager.getVp_twelve(),
                right: ResManager.getVp_twelve(),
              });
            };
          };

        }.width('100%');
      };
    }
    .hideTitleBar(true)
    .backgroundColor('#F1F3F5')
    .padding({
      top: this.getUIContext().px2vp(this.topRectHeight),
      bottom: this.getUIContext().px2vp(this.bottomRectHeight)
    });
  }
}

@Builder
export function MineTestResPageBuilder() {
  MineTestResPage();
}
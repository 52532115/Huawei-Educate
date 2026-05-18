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
import { IdInfo, NavInfo } from '@safe/train';
import { MineCourseListModel } from '../viewmodel/MineCourseListModel';
import { courseList } from '../viewmodel/MineLocalData';


@Component
export struct MineCoursePage {
  @State currentIndex: number = 0;
  @StorageProp('topRectHeight') topRectHeight: number = 0;
  @StorageProp('bottomRectHeight') bottomRectHeight: number = 0;
  scroller: Scroller = new Scroller();
  pathStack: NavPathStack = AppStorage.get('pathStack') as NavPathStack;
  private tabController: TabsController = new TabsController();

  @Builder
  MineListItem(model: MineCourseListModel) {
    RelativeContainer() {
      Image($r('app.media.train_pic01'))
        .objectFit(ImageFit.Cover)
        .width($r('app.float.icon_dock_height'))
        .height(80)
        .borderRadius(5)
        .id('icon')
        .alignRules({
          center: { anchor: '__container__', align: VerticalAlign.Center },
          left: { anchor: '__container__', align: HorizontalAlign.Start }
        })
        .offset({
          x: 10
        });

      Text(model.name)
        .alignRules({
          left: { anchor: 'icon', align: HorizontalAlign.End },
          top: { anchor: 'icon', align: VerticalAlign.Top }
        })
        .fontWeight(FontWeight.Medium)
        .fontColor('333333')
        .id('name')
        .offset({
          x: 25
        });

      Text('教师:' + model.tec)
        .alignRules({
          left: { anchor: 'name', align: HorizontalAlign.Start },
          bottom: { anchor: 'process', align: VerticalAlign.Top },
          bias: { horizontal: 25, vertical: -10 }
        })
        .fontWeight(FontWeight.Normal)
        .fontColor('#999999')
        .fontSize(12)
        .margin({
          bottom: 5
        })
        .id('tec')
        .offset({
          x: 25
        });

      Text('进度:')
        .alignRules({
          left: { anchor: 'icon', align: HorizontalAlign.End },
          bottom: { anchor: 'icon', align: VerticalAlign.Bottom }
        })
        .fontWeight(FontWeight.Normal)
        .fontColor('#999999')
        .fontSize(12)
        .id('process')
        .offset({
          x: 25
        });

      Progress({ value: 10, type: ProgressType.Linear }).width(120).alignRules({
        left: { anchor: 'process', align: HorizontalAlign.End },
        center: { anchor: 'process', align: VerticalAlign.Center }
      }).id('pro').offset({
        x: 30
      });

      Text(model.process.toString())
        .alignRules({
          left: { anchor: 'pro', align: HorizontalAlign.End },
          center: { anchor: 'process', align: VerticalAlign.Center }
        })
        .fontWeight(FontWeight.Normal)
        .fontColor('#999999')
        .fontSize(12)
        .id('proName')
        .offset({
          x: 40
        });
    }
    .margin({ left: $r('app.float.list_left_margin'), right: $r('app.float.list_left_margin') }).height('100vp')
    .backgroundColor(Color.White)
    .onClick(() => {
      let obj: IdInfo = new IdInfo(1);
      let params = new NavInfo('课程', JSON.stringify(obj));
      this.pathStack.pushPathByName('TrainDetailPage', params);
    });

  }

  @Builder
  ListBuilder() {
    List({ scroller: this.scroller, space: 10 }) {
      ForEach(courseList, (item: MineCourseListModel) => {
        ListItem() {
          this.MineListItem(item);
        };
      }, (item: MineCourseListModel) => item.key);
    }
    .scrollBar(BarState.Off)
    .margin({
      top: 10
    })
    .width(StyleConstants.FULL_WIDTH)
    .layoutWeight(1);
  }

  @Builder
  TabBarBuilder(title: string, targetIndex: number) {
    Text(title)
      .fontWeight(targetIndex === this.currentIndex ? FontWeight.Bold : FontWeight.Normal)
      .padding(5)
      .border(targetIndex === this.currentIndex ? {
        width: { bottom: 2 },
        style: {
          bottom: BorderStyle.Solid
        }
      } : {
        width: { bottom: 0 }
      })
      .margin({ left: 10, right: 10 })
      .onClick(() => {
        this.tabController.changeIndex(targetIndex);
      });
  }

  build() {
    NavDestination() {
      Column() {
        Row() {
          RelativeContainer() {
            Image(ResManager.getBackIcon())
              .width(ResManager.getVp_twenty())
              .height(ResManager.getVp_twenty())
              .objectFit(ImageFit.Cover)
              .alignRules({
                center: { anchor: '__container__', align: VerticalAlign.Center },
                left: { anchor: '__container__', align: HorizontalAlign.Start }
              })
              .id('back')
              .margin({ left: this.getUIContext().vp2px(5) })
              .onClick(() => {
                this.pathStack.pop();
              });

            Flex({ direction: FlexDirection.Row, justifyContent: FlexAlign.Center }) {
              this.TabBarBuilder('在学', 0);
              this.TabBarBuilder('已学', 1);
            }.width(200)
            .backgroundColor(Color.White)
            .alignRules({
              middle: { anchor: '__container__', align: HorizontalAlign.Center },
              center: { anchor: 'back', align: VerticalAlign.Center }
            })
            .id('tabBar');
          };
        }.width(StyleConstants.FULL_WIDTH).height(this.getUIContext().vp2px(10))
        .backgroundColor(Color.White);

        Column() {
          Tabs({ barPosition: BarPosition.End, index: this.currentIndex, controller: this.tabController }) {
            TabContent() {
              this.ListBuilder();
            }.width(StyleConstants.FULL_WIDTH).height(StyleConstants.FULL_HEIGHT);

            TabContent() {
              this.ListBuilder();
            }.width(StyleConstants.FULL_WIDTH).height(StyleConstants.FULL_HEIGHT);
          }
          .onChange((index: number) => {
            this.currentIndex = index;
          }).layoutWeight(1);
        };
      }.width(StyleConstants.FULL_WIDTH).height(StyleConstants.FULL_HEIGHT).backgroundColor('#f7f7f7');
    }
    .hideTitleBar(true)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
    })
    .padding({
      top: this.getUIContext().px2vp(this.topRectHeight),
      bottom: this.getUIContext().px2vp(this.bottomRectHeight)
    });
  }
}

@Builder
export function MineCoursePageBuilder() {
  MineCoursePage();
}

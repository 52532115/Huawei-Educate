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
import { MineOnlineTestModel } from '../viewmodel/MineOnlineTestModel';
import { testList } from '../viewmodel/MineLocalData';

const STATUS: string = '进行中';

@Component
export struct MineOnlineTestPage {
  @StorageProp('topRectHeight') topRectHeight: number = 0;
  scroller: Scroller = new Scroller();
  pathStack: NavPathStack = AppStorage.get('pathStack') as NavPathStack;

  @Builder
  MineCourseListItem(model: MineOnlineTestModel) {
    RelativeContainer() {
      Text(model.status)
        .alignRules({
          center: { anchor: 'name', align: VerticalAlign.Center },
          left: { anchor: '__container__', align: HorizontalAlign.Start },
        })
        .fontWeight(FontWeight.Normal)

        .width(60)
        .height(25)
        .backgroundColor('#f56c6c')
        .textAlign(TextAlign.Center)
        .fontColor(Color.White)
        .fontSize(12)
        .id('status')
        .offset({
          x: 10,
          y: 10
        });

      Text(model.text)
        .alignRules({
          left: { anchor: '__container__', align: HorizontalAlign.Start },
          top: { anchor: '__container__', align: VerticalAlign.Top },
        })
        .fontWeight(FontWeight.Normal)
        .fontColor('333333')
        .fontSize(16)
        .layoutWeight(1)
        .id('name')
        .width('72%')
        .offset({
          x: 80,
          y: 10
        });

      Text(model.beginTimer + '~' + model.endTimer + '截止')
        .alignRules({
          left: { anchor: '__container__', align: HorizontalAlign.Start },
          bottom: { anchor: '__container__', align: VerticalAlign.Bottom },
        })
        .fontWeight(FontWeight.Normal)
        .fontColor('aaaaaa')
        .fontSize(12)
        .id('timer')
        .offset({
          x: 10,
          y: -5
        });

      Text(model.nums + '人参与')
        .alignRules({
          center: { anchor: 'timer', align: VerticalAlign.Center },
          right: { anchor: '__container__', align: HorizontalAlign.End },
        })
        .fontWeight(FontWeight.Normal)
        .fontColor('aaaaaa')
        .fontSize(12)
        .id('nums')
        .offset({
          x: -10,
          y: -5
        });
    }
    .margin({ left: $r('app.float.list_left_margin'), right: $r('app.float.list_left_margin') })
    .height('110vp')
    .onClick(() => {
      if (model.status === STATUS) {
        this.pathStack.pushPathByName('ExaminationDetailPage', null);
      }
    });
  }

  @Builder
  ListBuilder() {
    List({ scroller: this.scroller }) {
      ForEach(testList, (item: MineOnlineTestModel) => {
        ListItem() {
          this.MineCourseListItem(item);
        };
      }, (item: MineOnlineTestModel) => item.key);
    }
    .scrollBar(BarState.Off)
    .divider({ strokeWidth: 1, color: '#f5f5f5' })
    .width(StyleConstants.FULL_WIDTH)
    .layoutWeight(1);
  }

  build() {
    NavDestination() {
      Column() {
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
            Text('在线考试').alignRules({
              middle: { anchor: '__container__', align: HorizontalAlign.Center },
              center: { anchor: 'back', align: VerticalAlign.Center },
            }).fontWeight(FontWeight.Medium).fontColor('333333').id('text');
          };
        }
        .width(StyleConstants.FULL_WIDTH).backgroundColor(Color.White).height(this.getUIContext().vp2px(12));

        this.ListBuilder();
      };
    }
    .hideTitleBar(true)
    .padding({ top: this.getUIContext().px2vp(this.topRectHeight) });
  }
}

@Builder
export function MineOnlineTestPageBuilder() {
  MineOnlineTestPage();
}
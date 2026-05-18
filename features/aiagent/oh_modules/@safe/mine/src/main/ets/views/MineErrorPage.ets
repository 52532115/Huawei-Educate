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
import { ERROR_MODELS } from '../viewmodel/MineLocalData';
import { MineErrorModel } from '../viewmodel/MineErrorModel';
import { hilog } from '@kit.PerformanceAnalysisKit';

@Component
export struct MineErrorPage {
  @StorageProp('topRectHeight') topRectHeight: number = 0;
  pathStack: NavPathStack = AppStorage.get('pathStack') as NavPathStack;

  @Builder
  testListItem(model: MineErrorModel, index: number) {
    Flex({ direction: FlexDirection.Column }) {
      Flex({ direction: FlexDirection.Row, justifyContent: FlexAlign.SpaceBetween }) {
        Text($r('app.string.question'))
          .fontWeight(FontWeight.Normal)
          .fontColor('#ffffff')
          .width(80)
          .height(25)
          .borderRadius(5)
          .backgroundColor('#409eff')
          .textAlign(TextAlign.Center);

        Image($r('app.media.delete'))
          .objectFit(ImageFit.Cover)
          .height($r('app.float.list_icon_height'))
          .width($r('app.float.list_icon_height'));
      }.margin({ left: 10, right: 10 });

      Text(model.title)
        .fontWeight(FontWeight.Medium)
        .fontColor('333333').margin({ top: 10, left: 10, right: 10 });

      Flex({ direction: FlexDirection.Column }) {
        ForEach(model.option, ((item: string) => {
          Flex({ direction: FlexDirection.Row, alignItems: ItemAlign.Center }) {
            Text(item)
              .fontColor('#3333333').margin({ left: 5 });

          }.backgroundColor('#eeeeeee').height(50)
          .margin({ top: 8 })
          .borderRadius(5);

        }));
      }.margin({ left: 10, right: 10 });

      Flex({ direction: FlexDirection.Row, justifyContent: FlexAlign.SpaceBetween }) {
        Text() {
          Span($r('app.string.correct_option'));
          Span('A').fontColor(Color.Red);
        };

        Text() {
          Span($r('app.string.my_option'));
          Span('B').fontColor(Color.Red);
        };
      }.margin({ left: 10, right: 10, top: 8 });

      Text($r('app.string.analysis'))
        .fontWeight(FontWeight.Normal)
        .fontColor('#666666').margin({ top: 10, left: 10, right: 10 });
    }
    .onClick(() => {
      hilog.info(0x0001, '[Scan CPSample]', 'Promise scan result: %{public}s', JSON.stringify(index));
    });
  }

  @Builder
  ListViewBuild() {
    List({
      space: 10
    }) {
      ForEach(ERROR_MODELS, (item: MineErrorModel, index: number) => {
        ListItem() {
          this.testListItem(item, index);
        };
      }, (item: MineErrorModel) => JSON.stringify(item));
    }.layoutWeight(1);
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
            Text('错题集').alignRules({
              middle: { anchor: '__container__', align: HorizontalAlign.Center },
              center: { anchor: 'back', align: VerticalAlign.Center }
            }).fontWeight(FontWeight.Medium).fontColor('333333').id('text');
          };
        }
        .width('100%').backgroundColor(Color.White).height(this.getUIContext().vp2px(10));

        this.ListViewBuild();

      };
    }
    .hideTitleBar(true)
    .padding({ top: this.getUIContext().px2vp(this.topRectHeight) });
  }
}

@Builder
export function MineErrorPageBuilder() {
  MineErrorPage();
}

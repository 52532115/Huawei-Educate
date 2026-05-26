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
export struct MineFavoritePage {
  @StorageProp('topRectHeight') topRectHeight: number = 0;
  pathStack: NavPathStack = AppStorage.get('pathStack') as NavPathStack;

  @Builder
  FavoriteListItem(model: MineCourseListModel) {
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
        .offset({ x: 10 });

      Text(model.name)
        .alignRules({
          left: { anchor: 'icon', align: HorizontalAlign.End },
          top: { anchor: 'icon', align: VerticalAlign.Top }
        })
        .fontWeight(FontWeight.Medium)
        .fontColor('333333')
        .id('name')
        .offset({ x: 25 });

      Text('教师:' + model.tec)
        .alignRules({
          left: { anchor: 'name', align: HorizontalAlign.Start },
          bottom: { anchor: 'icon', align: VerticalAlign.Bottom }
        })
        .fontWeight(FontWeight.Normal)
        .fontColor('#999999')
        .fontSize(12)
        .id('tec')
        .offset({ x: 25 });
    }
    .margin({ left: $r('app.float.list_left_margin'), right: $r('app.float.list_left_margin') })
    .height('100vp')
    .backgroundColor(Color.White)
    .onClick(() => {
      let obj: IdInfo = new IdInfo(1);
      let params = new NavInfo('课程', JSON.stringify(obj));
      this.pathStack.pushPathByName('TrainDetailPage', params);
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

            Text($r('app.string.mine_title_favorites'))
              .alignRules({
                middle: { anchor: '__container__', align: HorizontalAlign.Center },
                center: { anchor: 'back', align: VerticalAlign.Center }
              })
              .fontWeight(FontWeight.Medium)
              .fontColor('333333')
              .id('text');
          };
        }
        .width(StyleConstants.FULL_WIDTH)
        .height(this.getUIContext().vp2px(10))
        .backgroundColor(Color.White);

        List({ space: 10 }) {
          ForEach(courseList, (item: MineCourseListModel) => {
            ListItem() {
              this.FavoriteListItem(item);
            };
          }, (item: MineCourseListModel) => item.key);
        }
        .scrollBar(BarState.Off)
        .margin({ top: 10 })
        .width(StyleConstants.FULL_WIDTH)
        .layoutWeight(1);
      }
      .width(StyleConstants.FULL_WIDTH)
      .height(StyleConstants.FULL_HEIGHT)
      .backgroundColor('#f7f7f7');
    }
    .hideTitleBar(true)
    .padding({ top: this.getUIContext().px2vp(this.topRectHeight) });
  }
}

@Builder
export function MineFavoritePageBuilder() {
  MineFavoritePage();
}

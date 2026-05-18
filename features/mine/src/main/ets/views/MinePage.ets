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

import { CommonConstants, ResManager, StyleConstants } from '@safe/basic';
import { listModel } from '../viewmodel/MineLocalData';
import { MineListModel } from '../viewmodel/MineListModel';


@Component
export struct MinePage {
  isLogin: boolean = true;
  @StorageProp('topRectHeight') topRectHeight: number = 0;
  scroller: Scroller = new Scroller();
  context: Context = this.getUIContext().getHostContext() as Context;
  pathStack: NavPathStack = AppStorage.get('pathStack') as NavPathStack;

  @Builder
  MineCourseListItem(model: MineListModel) {
    Flex({
      direction: FlexDirection.Row,
      justifyContent: FlexAlign.SpaceBetween,
      alignItems: ItemAlign.Center
    }) {
      Row() {
        Image(model.icon)
          .objectFit(ImageFit.Fill)
          .height($r('app.float.list_icon_height'))
          .width($r('app.float.list_icon_height'))
          .fillColor(model.bgColor);
        Text(model.text).fontSize(16).fontColor('333333').margin({ left: $r('app.float.list_left_margin') });
      }.alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Start);

      Image($r('app.media.ic_right_arrow'))
        .objectFit(ImageFit.Contain)
        .fillColor('#aaaaaa')
        .height($r('app.float.list_icon_more_height'))
        .width($r('app.float.list_icon_more_height'))
        .margin({ right: $r('app.float.list_left_margin') });
    }
    .height($r('app.float.icon_person_size'))
    .width(StyleConstants.FULL_WIDTH)
    .onClick(() => {
      let pathName = model.pathName;
      this.pathStack.pushPathByName(pathName, null);
    });
  }

  @Builder
  ListBuilder() {
    List({ scroller: this.scroller }) {
      ForEach(listModel, (item: MineListModel) => {
        ListItem() {
          this.MineCourseListItem(item);
        };
      }, (item: MineListModel) => item.key);
    }
    .scrollBar(BarState.Off)
    .divider({ strokeWidth: 1, color: '#f5f5f5' })
    .width(StyleConstants.FULL_WIDTH)
    .backgroundColor(Color.White)
    .padding({ left: 16, right: 16 });
  }

  @Builder
  personalBuilder() {
    Row() {
      Column() {
        Text('登录')
          .fontSize(ResManager.getHuge_font_size())
          .fontColor('333333')
          .fontWeight(FontWeight.Medium)
          .onClick(() => {
            this.pathStack.pushPathByName('LoginView', null);
          });
        if (this.isLogin) {
          Text() {
            Span('我的课程').fontColor('333333');
            Span('1').fontColor(Color.Red);
          };
        } else {
          Text('立即登录,解锁更多使用功能');
        }
      }
      .alignItems(HorizontalAlign.Start);

      Image($r('app.media.ic_person'))
        .objectFit(ImageFit.Cover)
        .width($r('app.float.icon_person_size'))
        .height($r('app.float.icon_person_size'));
    }
    .width(CommonConstants.FULL_WIDTH_PERCENT)
    .backgroundColor(Color.White)
    .height(this.getUIContext().vp2px(30))
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
    .padding({ left: 16, right: 16 });
  }

  build() {
    NavDestination() {
      Column() {
        Scroll() {
          Column() {
            this.personalBuilder();
            Divider().strokeWidth(5).color('#f7f7f7');
            this.ListBuilder();
          };
        }
        .scrollBar(BarState.Off);
      }
      .height(CommonConstants.FULL_HEIGHT_PERCENT)
      .backgroundColor('#f7f7f7')
      .alignItems(HorizontalAlign.Start);
    }
    .hideTitleBar(true)
    .padding({ top: this.getUIContext().px2vp(this.topRectHeight) });
  }
}
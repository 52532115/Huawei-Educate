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

import HomeViewModel, { BusinessInfo } from '../views/HomeViewModel';
import { CommonConstants } from '../views/CommonConstants';

@Component
export struct Index {
  @StorageProp('topRectHeight') topRectHeight: number = 0;
  pathStack: NavPathStack = AppStorage.get('pathStack') as NavPathStack;

  build() {
    NavDestination() {
      Column() {
        Row() {
          List({ space: CommonConstants.LIST_SPACE }) {
            ForEach(HomeViewModel.getListHomepage(), (item: BusinessInfo) => {
              ListItem() {
                Row() {
                  Image(item.icon)
                    .width('90%')
                    .height(140)
                    .borderRadius($r('app.float.list_image_radius'))
                    .margin({ left: '5%' });
                }
                .onClick(() => {
                  this.pathStack.pushPathByName('JumpPage', null);
                });
              }
              .margin({
                top: $r('app.float.text_padding_top'),
                bottom: $r('app.float.text_padding_top')
              });
            }, (item: BusinessInfo, index: number) => index + JSON.stringify(item));
          }
          .divider({ strokeWidth: 1, color: $r('app.color.business_background') })
          .width(CommonConstants.FULL_WIDTH_PERCENT);

        }
        .justifyContent(FlexAlign.SpaceBetween)

        .width(CommonConstants.FULL_WIDTH_PERCENT);
      };
    }
    .title($r('app.string.home_page'))
    .padding({ top: this.getUIContext().px2vp(this.topRectHeight) });
  }
}

@Builder
export function SecondPageBuilder() {
  Index();
}
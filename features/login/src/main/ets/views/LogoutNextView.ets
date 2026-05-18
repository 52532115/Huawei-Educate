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

import { ResManager } from '../common/resources/ResManager ';

@Component
struct LogoutNextView {
  @StorageProp('topRectHeight') topRectHeight: number = 0;
  pathStack: NavPathStack = AppStorage.get('pathStack') as NavPathStack;

  build() {
    NavDestination() {
      Column() {
        Row() {
          RelativeContainer() {
            Text('注销账号').alignRules({
              middle: { anchor: '__container__', align: HorizontalAlign.Center },
              center: { anchor: 'back', align: VerticalAlign.Center }
            }).fontWeight(FontWeight.Medium).fontColor('333333').id('text');
          };
        }
        .width('100%').backgroundColor(Color.White).height(this.getUIContext().vp2px(10));

        Flex({ direction: FlexDirection.Column }) {
          Text($r('app.string.enter_verification_code')).fontColor('333333').fontSize(ResManager.getMiddle_font_size());
          Row() {
            TextInput({ placeholder: $r('app.string.enter_verification_code') })
              .placeholderColor('#999999')
              .fontSize(ResManager.getMiddle_font_size())
              .type(InputType.Normal)
              .width('70%')
              .height('40vp')
              .backgroundColor(Color.White)
              .borderWidth(1)
              .borderColor('eeeeee')
              .borderRadius(5);
            Button('获取验证码', { type: ButtonType.Normal, stateEffect: true })
              .width('25%')
              .backgroundColor('f5f5f5')
              .height('40vp')
              .fontColor('333333')
              .borderRadius(5);
          }.margin({ top: 10 })
          .alignItems(VerticalAlign.Center)
          .justifyContent(FlexAlign.SpaceBetween).width('100%');

          Text('注销后,185****7443账户所有数据删除，不可恢复，请谨慎操作。')
            .fontColor(Color.Red)
            .fontSize(ResManager.getMiddle_font_size())
            .margin({ top: 10 });
        }.margin({ left: ResManager.getVp_eight(), right: ResManager.getVp_eight() });
      };
    }
    .padding({ top: this.getUIContext().px2vp(this.topRectHeight) });
  }
}

@Builder
export function LogoutNextViewBuilder() {
  LogoutNextView();
}
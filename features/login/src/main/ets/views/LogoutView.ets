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
export struct LogoutView {
  @StorageProp('topRectHeight') topRectHeight: number = 0;
  pathStack: NavPathStack = AppStorage.get('pathStack') as NavPathStack;

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
            Text('注销账号').alignRules({
              middle: { anchor: '__container__', align: HorizontalAlign.Center },
              center: { anchor: 'back', align: VerticalAlign.Center }
            }).fontWeight(FontWeight.Medium).fontColor('333333').id('text');
          };
        }
        .width('100%').backgroundColor(Color.White).height(this.getUIContext().vp2px(10));

        Flex({ direction: FlexDirection.Column }) {
          Text() {
            Span('当前账号注销后可重新注册');
            Span('执行注销操作后账号\'185****7443\'所有信息被清除，').fontColor(Color.Red);
            Span('主要包含以下内容：');
          }.width('100%');

          Text('1.账号信息(手机号，身份证)').fontColor(Color.Red).width('100%').height(30);
          Text('2.学习记录').fontColor(Color.Red).width('100%');
          Text('3.培训证明').fontColor(Color.Red).width('100%');
          Text() {
            Span('请确认以上信息是否有用，一旦注销无法恢复！');
            Span('请慎重!').fontColor(Color.Red);
          };

          Flex({ justifyContent: FlexAlign.Center, alignItems: ItemAlign.Center }) {
            Checkbox({ name: 'checkbox1', group: 'checkboxGroup' })
              .selectedColor(0x39a2db)
              .shape(CheckBoxShape.ROUNDED_SQUARE)
              .onChange(() => {
              })
              .mark({
                strokeColor: Color.Black,
                size: 50,
                strokeWidth: 5
              })
              .unselectedColor(Color.Red)
              .width(ResManager.getVp_twenty())
              .height(ResManager.getVp_twenty());
            Text('我已确认个人账号所有信息，确定清除上述所有内容').fontSize(ResManager.getSmall_font_size());
          };

          Flex({ justifyContent: FlexAlign.Center, alignItems: ItemAlign.Center }) {
            Button('下一步', { buttonStyle: ButtonStyleMode.EMPHASIZED }).width('80%');
          }.margin({ top: 20 }).onClick(() => {
            this.pathStack.pushPathByName('LogoutNextView', null);
          });
        }.margin({ left: ResManager.getVp_eight(), right: ResManager.getVp_eight() });
      };
    }
    .hideTitleBar(true)
    .padding({ top: this.getUIContext().px2vp(this.topRectHeight) });
  }
}

@Builder
export function LogoutViewBuilder() {
  LogoutView();
}
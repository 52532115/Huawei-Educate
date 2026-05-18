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
import { StyleConstants } from '../constants/StyleConstants';
import { common } from '@kit.AbilityKit';


@Component
export struct ModifyPasswordView {
  @StorageProp('topRectHeight') topRectHeight: number = 0;
  pathStack: NavPathStack = AppStorage.get('pathStack') as NavPathStack;
  private context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;

  async aboutToAppear() {
    //页面防止截屏
    let myWindow = this.context.windowStage.getMainWindowSync();
    myWindow.setWindowPrivacyMode(true);
  }

  aboutToDisappear(): void {
    let myWindow = this.context.windowStage.getMainWindowSync();
    myWindow.setWindowPrivacyMode(false);
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
            Text('修改密码').alignRules({
              middle: { anchor: '__container__', align: HorizontalAlign.Center },
              center: { anchor: 'back', align: VerticalAlign.Center }
            }).fontWeight(FontWeight.Medium).fontColor('333333').id('text');
          };
        }
        .width('100%').backgroundColor(Color.White).height(this.getUIContext().vp2px(10));

        Divider().strokeWidth(5).color('f5f5f5');
        Row() {
          TextInput({ placeholder: '旧密码' })
            .placeholderColor('#999999')
            .fontSize(ResManager.getMiddle_font_size())
            .type(InputType.Password)
            .width(StyleConstants.FULL_WIDTH)
            .height(ResManager.getVp_fifty_six())
            .backgroundColor(Color.White);
        };

        Divider().strokeWidth(5).color('f5f5f5');
        Row() {
          TextInput({ placeholder: '新密码' })
            .placeholderColor('#999999')
            .fontSize(ResManager.getMiddle_font_size())
            .type(InputType.Password)
            .width(StyleConstants.FULL_WIDTH)
            .height(ResManager.getVp_fifty_six())
            .backgroundColor(Color.White);
        };

        Divider().strokeWidth(5).color('f5f5f5');
        Row() {
          TextInput({ placeholder: '确认密码' })
            .placeholderColor('#999999')
            .fontSize(ResManager.getMiddle_font_size())
            .type(InputType.Password)
            .width(StyleConstants.FULL_WIDTH)
            .height(ResManager.getVp_fifty_six())
            .backgroundColor(Color.White);
        };
      }
      .width(StyleConstants.FULL_WIDTH)
      .height(StyleConstants.FULL_HEIGHT)
      .backgroundColor(0xffffff)
      .padding({ top: 5 });
    }
    .hideTitleBar(true)
    .padding({ top: this.getUIContext().px2vp(this.topRectHeight) });
  }
}

@Builder
export function ModifyPasswordViewBuilder() {
  ModifyPasswordView();
}
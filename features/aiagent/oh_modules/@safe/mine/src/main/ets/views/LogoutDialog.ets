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

@CustomDialog
export struct LogoutDialog {
  controller?: CustomDialogController;
  confirm?: () => void;
  message: string = '是否退出登录?';

  build() {
    Column() {
      Text(this.message)
        .fontSize(16)
        .fontColor('#E6000000')
        .margin({
          bottom: 8,
          top: 24,
          left: 24,
          right: 24
        });
      Row() {
        Text($r('app.string.cancel'))
          .fontColor('#007DFF')
          .fontSize(16)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            if (this.controller) {
              this.controller.close();
            }
          });
        Line().width(1).height(24).backgroundColor('#33000000').margin({ left: 4, right: 4 });
        Text($r('app.string.confirm'))
          .fontColor('#FA2A2D')
          .fontSize(16)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            if (this.confirm) {
              this.confirm();
            }
            if (this.controller) {
              this.controller.close();
            }
          });
      }.height(40)
      .margin({ left: 24, right: 24, bottom: 16 });
    }.borderRadius(24);
  }
}
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

import { common } from '@kit.AbilityKit';
import { AccountCommonConstants } from '../common/constants/AccountConstants';


@Component
export struct LoginView {
  @State phone: string = '';
  @State password: string = '';
  @State rememberPassword: number = 0; // 0:不记住密码   1:记住密码
  @State readPrivacy: boolean = false;
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
    Row() {
      NavDestination() {
        Row() {
          Column() {
            Text('账号密码登录')
              .fontSize(30)
              .fontWeight(FontWeight.Bold)
              .margin({
                top: 30,
                bottom: 60,
                left: '4%'
              })
              .alignSelf(ItemAlign.Start);

            Row() {
              Image($r('app.media.username'))
                .width(20)
                .height(20);
              TextInput({ placeholder: '请输入手机号', text: this.phone })
                .type(InputType.PhoneNumber)
                .margin({
                  top: 10,
                  bottom: 10
                })
                .width('calc(100% - 30vp)')
                .height(AccountCommonConstants.FULL_HEIGHT)
                .backgroundColor(Color.White)
                .onChange((value: string) => {
                  this.phone = value;
                });

            }
            .width('92%')
            .height(56)
            .border({
              width: { bottom: 1 },
              color: { bottom: '#eeeeee' },
              style: {
                bottom: BorderStyle.Solid
              }
            });

            Row() {
              Image($r('app.media.password'))
                .width(20)
                .height(20);
              TextInput({ placeholder: '请输入密码', text: this.password })
                .type(InputType.Password)

                .margin({
                  top: 10,
                  bottom: 10
                })
                .width('calc(100% - 30vp)')
                .height(AccountCommonConstants.FULL_HEIGHT)
                .backgroundColor(Color.White)
                .onChange((value: string) => {
                  this.password = value;
                });
            }
            .width('92%')
            .height(56)
            .border({
              width: { bottom: 1 },
              color: { bottom: '#eeeeee' },
              style: {
                bottom: BorderStyle.Solid
              }
            });

            Row() {
              Row() {
                Checkbox()
                  .select(this.rememberPassword === 0 ? false : true)
                  .shape(CheckBoxShape.ROUNDED_SQUARE)
                  .onChange((value: boolean) => {
                    this.rememberPassword = value ? 1 : 0;
                  });
                Text(`记住密码`)
                  .onClick(() => {
                    if (this.rememberPassword === 0) {
                      this.rememberPassword = 1;
                    } else if (this.rememberPassword === 1) {
                      this.rememberPassword = 0;
                    }
                  });
              };

              Text('忘记密码？')
                .blueTextStyle();
            }
            .width('92%')
            .height(56)
            .justifyContent(FlexAlign.SpaceBetween);

            Button('登录')
              .width('92%')
              .margin({
                top: 50
              })
              .enabled(isLoginClickable(this.phone, this.password, this.readPrivacy))
              .onClick(async () => {
                //登录仅为示例，不校验真实登录逻辑
                this.pathStack.pop();
              });

            Row() {
              Checkbox()
                .select(this.readPrivacy)
                .shape(CheckBoxShape.ROUNDED_SQUARE)
                .onChange((value: boolean) => {
                  this.readPrivacy = value;
                });
              Text('我已阅读并同意');
              Text('《隐私政策》')
                .blueTextStyle()
                .onClick(() => {
                  this.pathStack.pushPathByName('PolicyAgreement', null);
                });

            }
            .width('92%')
            .height(56)
            .justifyContent(FlexAlign.Center);
          }
          .width(AccountCommonConstants.FULL_WIDTH)
          .height(AccountCommonConstants.FULL_HEIGHT);

        }.width(AccountCommonConstants.FULL_WIDTH)
        .height(AccountCommonConstants.FULL_HEIGHT)
        .backgroundColor(Color.White);
      }
      .size({ width: AccountCommonConstants.FULL_WIDTH, height: AccountCommonConstants.FULL_HEIGHT })
      .padding({ top: this.getUIContext().px2vp(this.topRectHeight) });
    };
  }
}

@Extend(Text)
function blueTextStyle() {
  .fontColor($r('app.color.login_blue_text_color'));
}

function isLoginClickable(account: string, password: string, readPrivacy: boolean): boolean {
  return account !== '' && password !== '' && readPrivacy;
}

@Builder
export function LoginViewBuilder() {
  LoginView();
}


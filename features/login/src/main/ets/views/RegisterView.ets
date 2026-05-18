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
import { industryTypeList } from '../viewmodel/AccountInfo';
import { AccountCommonConstants } from '../common/constants/AccountConstants';
import DistrictTownDialog from '../dialog/DistrictTownDialog';


@Component
export struct RegisterView {
  @State isAgree: boolean = false;
  isRegister: boolean = false;
  @State returnCode: string = '';
  @State districtTownSelected: number[] = []; //所在区镇所选索引
  @State phone: string = '';
  @State verifyCode: string = '';
  @State password: string = '';
  @State confirmPassword: string = '';
  @State name: string = '';
  @State idCard: string = '';
  @State sex: number = 0;
  @State districtTown: string = '';
  @State company: string = '';
  @State industryType: string = '';
  @StorageProp('topRectHeight') topRectHeight: number = 0;
  @StorageProp('bottomRectHeight') bottomRectHeight: number = 0;
  pathStack: NavPathStack = AppStorage.get('pathStack') as NavPathStack;
  dialogController: CustomDialogController = new CustomDialogController({
    builder: DistrictTownDialog(
      {
        cancel: () => {
          this.onCancel();
        },
        confirm: (selectedValues: string[], selectedindexs: number[]) => {
          this.onConfirm(selectedValues, selectedindexs);
        },
        selected: this.districtTownSelected
      }),
    alignment: DialogAlignment.Bottom,
    offset: { dx: 0, dy: 0 },
    customStyle: true,
    autoCancel: false
  });
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

  onCancel() {
  }

  onConfirm(selectedValues: string[], selectedIndex: number[]) {
    this.dialogController.close();

    if (selectedValues?.length === 0) {
      let arr = ['辽宁省', '沈阳市', '沈河区'];
      this.districtTown = arr.join(' ');
      this.districtTownSelected = [0, 0, 0];
    } else {
      this.districtTown = (selectedValues as string[])?.join(' ');
      this.districtTownSelected = selectedIndex;
    }
  }

  build() {
    Row() {
      NavDestination() {
        Column() {
          List() {
            //手机号码
            ListItem() {
              Row() {
                Row() {
                  Text('手机号码');
                  Text('*')
                    .fontColor(Color.Red);
                }
                .width(80);

                TextInput({ placeholder: '手机号码', text: this.phone })
                  .type(InputType.PhoneNumber)
                  .textBgColorStyle()
                  .layoutWeight(1)
                  .onChange((value: string) => {
                    this.phone = value;
                  });
                Text('获取验证码')
                  .fontColor($r('app.color.font_gray_color'))
                  .onClick(() => {
                    if (this.phone === '') {
                      this.getUIContext().getPromptAction().showToast({
                        message: '请输入手机号码！',
                        duration: AccountCommonConstants.TOAST_INTERVAL_TIME
                      });
                      return;
                    }
                    this.returnCode = AccountCommonConstants.VERIFY_NUMBER;
                    this.getUIContext().getPromptAction().showToast({
                      message: '验证码已生成，请在控制台中查看',
                      duration: AccountCommonConstants.TOAST_INTERVAL_TIME
                    });
                  });
              }
              .listItemStyle()
              .justifyContent(FlexAlign.SpaceBetween);
            }
            .width(AccountCommonConstants.FULL_WIDTH);


            //验证码
            ListItem() {
              Row() {
                Row() {
                  Text($r('app.string.verify_code'));
                  Text('*')
                    .fontColor(Color.Red);
                }
                .width(80);

                TextInput({ placeholder: $r('app.string.verify_code'), text: this.verifyCode })
                  .textBgColorStyle()
                  .layoutWeight(1)
                  .onChange((value: string) => {
                    this.verifyCode = value;
                  });
              }
              .listItemStyle()
              .justifyContent(FlexAlign.SpaceBetween);
            }
            .width(AccountCommonConstants.FULL_WIDTH);

            //密码
            ListItem() {
              Row() {
                Row() {
                  Text('密码');
                  Text('*')
                    .fontColor(Color.Red);
                }
                .width(80);

                TextInput({ placeholder: '字母大小写数字混合8-16位', text: this.password })
                  .textBgColorStyle()
                  .layoutWeight(1)
                  .type(InputType.Password)
                  .onChange((value: string) => {
                    this.password = value;
                  });
              }
              .listItemStyle()
              .justifyContent(FlexAlign.SpaceBetween);
            }
            .width(AccountCommonConstants.FULL_WIDTH);

            //确认密码
            ListItem() {
              Row() {
                Row() {
                  Text('密码');
                  Text('*')
                    .fontColor(Color.Red);
                }
                .width(80);

                TextInput({ placeholder: '字母大小写数字混合8-16位', text: this.confirmPassword })
                  .textBgColorStyle()
                  .layoutWeight(1)
                  .type(InputType.Password)
                  .onChange((value: string) => {
                    this.confirmPassword = value;
                  });
              }
              .listItemStyle()
              .justifyContent(FlexAlign.SpaceBetween);
            }
            .width(AccountCommonConstants.FULL_WIDTH);


            //姓名
            ListItem() {
              Row() {
                Row() {
                  Text('姓名');
                  Text('*')
                    .fontColor(Color.Red);
                }
                .width(80);

                TextInput({ placeholder: '姓名', text: this.name })
                  .textBgColorStyle()
                  .layoutWeight(1)
                  .onChange((value: string) => {
                    this.name = value;
                  });
              }
              .listItemStyle()
              .justifyContent(FlexAlign.SpaceBetween);
            }
            .width(AccountCommonConstants.FULL_WIDTH);


            //身份证号
            ListItem() {
              Row() {
                Row() {
                  Text('身份证号');
                  Text('*')
                    .fontColor(Color.Red);
                }
                .width(80);

                TextInput({ placeholder: '身份证号', text: this.idCard })
                  .textBgColorStyle()
                  .layoutWeight(1)
                  .onChange((value: string) => {
                    this.idCard = value;
                  });
              }
              .listItemStyle()
              .justifyContent(FlexAlign.SpaceBetween);
            }
            .width(AccountCommonConstants.FULL_WIDTH)
            .margin({
              top: 10
            });


            //性别
            ListItem() {
              Row() {
                Row() {
                  Text('性别');
                  Text('*')
                    .fontColor(Color.Red);
                }
                .width(80);

                Row() {
                  Row() {
                    Radio({ value: 'Radio1', group: 'radioGroup' }).checked(true)
                      .onChange((isChecked: boolean) => {
                        if (isChecked) {
                          this.sex = 0;
                        }
                      });
                    Text('男');
                  }
                  .margin({
                    right: 10
                  });

                  Row() {
                    Radio({ value: 'Radio2', group: 'radioGroup' }).checked(false)
                      .onChange((isChecked: boolean) => {
                        if (isChecked) {
                          this.sex = 1;
                        }
                      });
                    Text('女');
                  };

                }
                .layoutWeight(1);

              }
              .listItemStyle()
              .justifyContent(FlexAlign.SpaceBetween);
            }
            .width(AccountCommonConstants.FULL_WIDTH);


            //所在区镇
            ListItem() {
              Row() {
                Row() {
                  Text('所在区镇');
                  Text('*')
                    .fontColor(Color.Red);
                }
                .width(80);

                Text(this.districtTown)
                  .layoutWeight(1)
                  .height(32);
                Row() {
                  Text('请选择')
                    .fontColor($r('app.color.font_gray_color'));
                  Image($r('app.media.more'))
                    .width(16)
                    .height(16)
                    .fillColor($r('app.color.arrow_color'));
                }
                .onClick(() => {
                  this.dialogController.open();
                });
              }
              .listItemStyle()
              .justifyContent(FlexAlign.SpaceBetween);
            }
            .width(AccountCommonConstants.FULL_WIDTH);


            //单位名称
            ListItem() {
              Row() {
                Row() {
                  Text('单位名称');
                  Text('*')
                    .fontColor(Color.Red);
                }
                .width(80);

                TextInput({ placeholder: '单位名称', text: this.company })
                  .textBgColorStyle()
                  .layoutWeight(1)
                  .onChange((value: string) => {
                    this.company = value;
                  });
              }
              .listItemStyle()
              .justifyContent(FlexAlign.SpaceBetween);
            }
            .width(AccountCommonConstants.FULL_WIDTH);


            //行业类别
            ListItem() {
              Row() {
                Row() {
                  Text('行业类别');
                  Text('*')
                    .fontColor(Color.Red);
                }
                .width(80);

                Text(this.industryType)
                  .layoutWeight(1)
                  .height(32);
                Row() {
                  Text('请选择')
                    .fontColor($r('app.color.font_gray_color'));
                  Image($r('app.media.more'))
                    .width(16)
                    .height(16)
                    .fillColor($r('app.color.arrow_color'));
                }
                .onClick(() => {
                  this.getUIContext().showTextPickerDialog({
                    range: industryTypeList,
                    selected: [],
                    textStyle: { color: Color.Black, font: { size: 18, weight: FontWeight.Normal } },
                    selectedTextStyle: { color: Color.Blue, font: { size: 24, weight: FontWeight.Bolder } },
                    onAccept: (value: TextPickerResult) => {
                      // 点击确定后，被选到的文本数据展示到页面
                      this.industryType = value.value as string;
                    },
                    onCancel: () => {
                    },
                    onChange: () => {

                    }
                  });
                });
              }
              .listItemStyle()
              .justifyContent(FlexAlign.SpaceBetween);
            }
            .width(AccountCommonConstants.FULL_WIDTH);
          }
          .width(AccountCommonConstants.FULL_WIDTH)
          .layoutWeight(1);


          Row() {
            Checkbox()
              .select(this.isAgree)
              .width(16)
              .height(16)
              .shape(CheckBoxShape.ROUNDED_SQUARE)
              .onChange((value: boolean) => {
                this.isAgree = value;
              });
            Text('我已阅读并同意')
              .fontSize(14);
            Text($r('app.string.user_agreement'))
              .blueTextStyle()
              .fontSize(14)
              .onClick(() => {
                this.pathStack.pushPathByName('PolicyAgreement', null);
              });
            Text('和')
              .fontSize(14);
            Text($r('app.string.privacy_policy'))
              .blueTextStyle()
              .fontSize(14)
              .onClick(() => {
                this.pathStack.pushPathByName('PolicyAgreement', null);
              });

          }
          .width('92%')
          .height(56)
          .justifyContent(FlexAlign.Start);

          Button($r('app.string.register_title'))
            .width('92%')
            .enabled(isRegisterClickable(this.phone, this.verifyCode, this.password, this.confirmPassword, this.name,
              this.idCard, this.districtTown, this.company, this.industryType, this.isAgree) && !this.isRegister)
            .onClick(() => {
              //判断验证码是否正确
              if (this.verifyCode !== this.returnCode) {
                this.getUIContext().getPromptAction().showToast({
                  message: '请输入正确的验证码！',
                  duration: AccountCommonConstants.TOAST_INTERVAL_TIME
                });
                return;
              }
              //密码是否符合规则  密码和确认密码相同
              let pattern = /^(?=.*\d)(?=.*[a-z])(?=.*[A-Z])[a-zA-Z0-9]{8,16}$/;
              if (!pattern.test(this.password)) {
                this.getUIContext().getPromptAction().showToast({
                  message: '密码不符合要求！',
                  duration: AccountCommonConstants.TOAST_INTERVAL_TIME
                });
                return;
              }
              if (this.password !== this.confirmPassword) {
                this.getUIContext().getPromptAction().showToast({
                  message: '密码和确认密码不相等！',
                  duration: AccountCommonConstants.TOAST_INTERVAL_TIME
                });
                return;
              }

              this.getUIContext().getPromptAction().showToast({
                message: '注册成功',
                duration: AccountCommonConstants.TOAST_INTERVAL_TIME
              });
              this.pathStack.pop();
            });
        }
        .width(AccountCommonConstants.FULL_WIDTH)
        .height(AccountCommonConstants.FULL_HEIGHT);
      }
      .size({ width: AccountCommonConstants.FULL_WIDTH, height: AccountCommonConstants.FULL_HEIGHT })
      .title($r('app.string.register_title'))
      .padding({
        top: this.getUIContext().px2vp(this.topRectHeight),
        bottom: this.getUIContext().px2vp(this.bottomRectHeight)
      });
    }
    .width(AccountCommonConstants.FULL_WIDTH)
    .height(AccountCommonConstants.FULL_HEIGHT)
    .backgroundColor('#f7f7f7');
  }
}

@Extend(TextInput)
function textBgColorStyle() {
  .backgroundColor(Color.White);
}

@Extend(Row)
function listItemStyle() {
  .padding({
    top: 5,
    right: 10,
    bottom: 5,
    left: 10
  })
  .backgroundColor(Color.White)
  .border({
    width: { bottom: 1 },
    color: { bottom: '#eeeeee' },
    style: {
      bottom: BorderStyle.Solid
    }
  });
}

@Extend(Text)
function blueTextStyle() {
  .fontColor($r('app.color.login_blue_text_color'));
}

function isRegisterClickable(phone: string, verifyCode: string, password: string, confirmPassword: string, name: string,
  idCard: string, districtTown: string, company: string, industryType: string, isAggree: boolean): boolean {
  return phone !== '' && verifyCode !== '' && password !== '' && confirmPassword !== '' && name !== '' &&
    idCard !== '' && districtTown !== '' && company !== '' && industryType !== '' && isAggree;
}

@Builder
export function RegisterViewBuilder() {
  RegisterView();
}
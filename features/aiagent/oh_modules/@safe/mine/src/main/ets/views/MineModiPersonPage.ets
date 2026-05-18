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

@Component
export struct MineModiPersonPage {
  districtTownSelected: number[] = []; //所在区镇所选索引
  @State phone: string = '';
  @State name: string = '';
  @State idCard: string = '';
  @State sex: number = 0;
  districtTown: string = '';
  @State company: string = '';
  @State industryType: string = '';
  @State documentCompany: string = '';
  @StorageProp('topRectHeight') topRectHeight: number = 0;
  industryTypeList: string[] = ['化工', '矿业', '烟花爆竹', '冶金行业', '商贸行业', '其他'];
  documentCompanyList: string[] = ['应急管理部门', '住建部门', '市场监督部门', '其他'];
  districtTownList: string[] = ['杭州市', '宁波市', '温州市'];
  pathStack: NavPathStack = AppStorage.get('pathStack') as NavPathStack;

  onConfirm(selectedValues: string[], selectedindexs: number[]) {
    if (selectedValues?.length === 0) {
      let arr = ['辽宁省', '沈阳市', '沈河区'];
      this.districtTown = arr.join(' ');
      this.districtTownSelected = [0, 0, 0];
    } else {
      this.districtTown = (selectedValues as string[])?.join(' ');
      this.districtTownSelected = selectedindexs;
    }
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

            Text('修改信息').alignRules({
              middle: { anchor: '__container__', align: HorizontalAlign.Center },
              center: { anchor: 'back', align: VerticalAlign.Center },
            }).fontWeight(FontWeight.Medium).fontColor('333333').id('text');
          };
        }.width(StyleConstants.FULL_WIDTH).height(this.getUIContext().vp2px(10))
        .backgroundColor(Color.White);

        Column() {
          List() {
            //手机号码
            ListItem() {
              Row() {
                Row() {
                  Text('手机号');
                }.width(80);

                TextInput({ placeholder: '手机号码', text: this.phone })
                  .type(InputType.PhoneNumber)
                  .textBgColorStyle()
                  .textAlign(TextAlign.Center)
                  .enabled(false)
                  .width(100)
                  .height(40)
                  .borderRadius(5);
              }
              .listItemStyle()
              .justifyContent(FlexAlign.SpaceBetween)
              .width(StyleConstants.FULL_WIDTH)
              .height(50);
            }
            .width(StyleConstants.FULL_WIDTH);

            //性别
            ListItem() {
              Row() {
                Row() {
                  Text('性别');
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
                };
              }
              .listItemStyle()
              .height(50)
              .justifyContent(FlexAlign.SpaceBetween)
              .width(StyleConstants.FULL_WIDTH);
            }
            .width(StyleConstants.FULL_WIDTH);

            //姓名
            ListItem() {
              Row() {
                Row() {
                  Text('姓名');
                }
                .width(80);

                TextInput({ placeholder: '姓名', text: this.name })
                  .textBgColorStyle()
                  .width(150)
                  .textAlign(TextAlign.Center)
                  .height(40)
                  .borderRadius(5)
                  .textAlign(TextAlign.Center)
                  .onChange((value: string) => {
                    this.name = value;
                  });
              }
              .listItemStyle()
              .justifyContent(FlexAlign.SpaceBetween)
              .width(StyleConstants.FULL_WIDTH);
            }
            .width(StyleConstants.FULL_WIDTH)
            .height(50);

            ListItem() {
              Divider().color('f5f5f5').strokeWidth(5);
            }.width(StyleConstants.FULL_WIDTH);

            //身份证号
            ListItem() {
              Row() {
                Row() {
                  Text('身份证号');
                }
                .width(80);

                TextInput({ placeholder: '身份证号', text: this.idCard })
                  .layoutWeight(1)
                  .textAlign(TextAlign.End)
                  .backgroundColor(Color.White)
                  .onChange((value: string) => {
                    this.idCard = value;
                  });
              }
              .listItemStyle()
              .height(50)
              .justifyContent(FlexAlign.SpaceBetween);
            }
            .width(StyleConstants.FULL_WIDTH)
            .height(50)
            .margin({
              top: 10
            });


            //行业类别
            ListItem() {
              Row() {
                Row() {
                  Text('行业类别');
                }
                .width(80);

                Text(this.industryType)
                  .layoutWeight(1)
                  .height(32);
                Row() {
                  Text('请选择')
                    .fontColor(Color.Gray);
                  Image($r('app.media.more'))
                    .width(16)
                    .height(16)
                    .fillColor('666666');
                }
                .onClick(() => {
                  this.getUIContext().showTextPickerDialog({
                    range: this.industryTypeList,
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
              }.height(50)

              .listItemStyle()
              .justifyContent(FlexAlign.SpaceBetween);
            }
            .width(StyleConstants.FULL_WIDTH)
            .height(50);

            //制证单位
            ListItem() {
              Row() {
                Row() {
                  Text('制证单位');
                }
                .width(80);

                Text(this.documentCompany)
                  .layoutWeight(1)
                  .height(32);
                Row() {
                  Text('请选择')
                    .fontColor('666666');
                  Image($r('app.media.more'))
                    .width(14)
                    .height(14)
                    .fillColor('666666');
                }
                .onClick(() => {
                  this.getUIContext().showTextPickerDialog({
                    range: this.documentCompanyList,
                    selected: [],
                    textStyle: { color: Color.Black, font: { size: 18, weight: FontWeight.Normal } },
                    selectedTextStyle: { color: Color.Blue, font: { size: 24, weight: FontWeight.Bolder } },
                    onAccept: (value: TextPickerResult) => {
                      // 点击确定后，被选到的文本数据展示到页面
                      this.documentCompany = value.value as string;
                    },
                    onCancel: () => {
                    },
                    onChange: () => {
                    }
                  });
                });
              }.height(50)
              .listItemStyle()
              .justifyContent(FlexAlign.SpaceBetween);
            }
            .width(StyleConstants.FULL_WIDTH);

            //单位名称
            ListItem() {
              Row() {
                Row() {
                  Text('所属区县');
                }
                .width(80);

                Text('动态获取的属性').height(40);
              }
              .listItemStyle()
              .height(50)
              .justifyContent(FlexAlign.SpaceBetween).width(StyleConstants.FULL_WIDTH);
            }
            .width(StyleConstants.FULL_WIDTH);


            //单位名称
            ListItem() {
              Row() {
                Row() {
                  Text('单位名称');
                }
                .width(80);

                TextInput({ placeholder: '单位名称', text: this.company })
                  .textBgColorStyle()
                  .backgroundColor(Color.White)
                  .layoutWeight(1)
                  .textAlign(TextAlign.End)
                  .onChange((value: string) => {
                    this.company = value;
                  });
              }
              .listItemStyle()
              .height(50)
              .justifyContent(FlexAlign.SpaceBetween).width(StyleConstants.FULL_WIDTH);
            }
            .width(StyleConstants.FULL_WIDTH);

          };

        }
        .width(StyleConstants.FULL_WIDTH)
        .height(StyleConstants.FULL_HEIGHT)
        .backgroundColor('#f7f7f7');

      };
    }
    .hideTitleBar(true)
    .padding({ top: this.getUIContext().px2vp(this.topRectHeight) });
  }
}


@Extend(TextInput)
function textBgColorStyle() {
  .backgroundColor('eeeeeeee');
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

@Builder
export function MineModiPersonPageBuilder() {
  MineModiPersonPage();
}
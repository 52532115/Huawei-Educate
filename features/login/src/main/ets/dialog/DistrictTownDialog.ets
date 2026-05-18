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

import { AccountCommonConstants } from '../common/constants/AccountConstants';

@Preview
@CustomDialog
export default struct DistrictTownDialog {
  controller: CustomDialogController = new CustomDialogController({ 'builder': '' });
  @State selectedValues: string[] = [];
  @Prop selected: number[];
  @State currentSelected: number[] = [];
  private cascade: TextCascadePickerRangeContent[] = [
    {
      text: '辽宁省',
      children: [
        { text: '沈阳市', children: [{ text: '沈河区' }, { text: '和平区' }, { text: '浑南区' }] },
        { text: '大连市', children: [{ text: '中山区' }, { text: '金州区' }, { text: '长海县' }] }
      ]
    },
    {
      text: '吉林省',
      children: [
        { text: '长春市', children: [{ text: '南关区' }, { text: '宽城区' }, { text: '朝阳区' }] },
        { text: '四平市', children: [{ text: '铁西区' }, { text: '铁东区' }, { text: '梨树县' }] }
      ]
    },
    {
      text: '黑龙江省',
      children: [
        { text: '哈尔滨市', children: [{ text: '道里区' }, { text: '道外区' }, { text: '南岗区' }] },
        { text: '牡丹江市', children: [{ text: '东安区' }, { text: '西安区' }, { text: '爱民区' }] }
      ]
    }
  ];
  cancel: Function = () => {
  };
  confirm: Function = () => {
  };

  build() {
    Column() {
      TextPicker({
        range: this.cascade,
        selected: $$this.selected
      })
        .onChange((value: string | string[], index: number | number[]) => {
          this.selectedValues = value as string[];
          this.currentSelected = index as number[];
        })
        .width(AccountCommonConstants.FULL_WIDTH)
        .padding(10);

      Row() {
        Text('取消')
          .width('50%')
          .fontColor($r('app.color.login_blue_text_color'))
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.controller.close();
          });

        Text('确定')
          .width('50%')
          .fontColor($r('app.color.login_blue_text_color'))
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.confirm(this.selectedValues, this.currentSelected);
          });
      }
      .justifyContent(FlexAlign.SpaceBetween)
      .width(AccountCommonConstants.FULL_WIDTH)
      .padding({
        top: 20,
        right: 10,
        bottom: 15,
        left: 10
      });
    }
    .justifyContent(FlexAlign.Center)
    .width(AccountCommonConstants.FULL_WIDTH)
    .alignItems(HorizontalAlign.End)
    .backgroundColor(Color.White);
  }
}

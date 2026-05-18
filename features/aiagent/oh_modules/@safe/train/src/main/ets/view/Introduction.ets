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

import TrainConstants from '../common/constants/TrainConstants';
import { IntroInfoEnum, IntroObj } from '../viewmodel/TrainInfoModel';

interface ListItemType {
  name: string,
  value: string,
  code: string,
}

@Component
export struct IntroductionComponent {
  @State list: ListItemType[] = [];

  aboutToAppear(): void {
    for (const key of Object.keys(IntroObj)) {
      if (key !== 'startTime' && key !== 'endTime') {
        let obj: ListItemType = {
          name: IntroInfoEnum[key],
          value: Reflect.get(IntroObj, key),
          code: key
        };
        this.list.push(obj);
      }
    }
    let timeObj: ListItemType = {
      name: '起止时间',
      value: `${IntroObj.startTime}至${IntroObj.endTime}`,
      code: 'time'
    };
    this.list.push(timeObj);
  }

  build() {
    Column() {
      Text('基本信息')
        .fontSize(20)
        .fontWeight(700)
        .fontFamily('HarmonyHeiTi')
        .fontWeight(FontWeight.Bold)
        .margin({
          top: 16,
          bottom: 10
        });

      List() {
        ForEach(this.list, (item: ListItemType) => {
          ListItem() {
            Row() {
              Text(`${item.name}`)
                .fontSize(16)
                .fontWeight(500)
                .fontFamily('HarmonyHeiTi')
                .margin(10);
              Text(item.value)
                .fontColor($r('app.color.blue_text_color'))
                .fontSize(14)
                .fontWeight(400)
                .fontFamily('HarmonyHeiTi')
                .margin(10)
                .width(this.getUIContext().px2vp(160 * 3.5))
                .textAlign(TextAlign.End)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis });
            }
            .width(this.getUIContext().px2vp(328 * 3.5))
            .justifyContent(FlexAlign.SpaceBetween);
          }
          .margin({
            top: 5,
            bottom: 5
          });
        }, (item: ListItemType) => JSON.stringify(item));
      }
      .scrollBar(BarState.Off)
      .margin({
        top: 8,
        bottom: 10
      })
      .borderRadius(16)
      .backgroundColor(Color.White)
      .layoutWeight(1);

      Text('学识证明')
        .margin({
          top: 10
        })
        .fontColor(Color.White)
        .fontSize(this.getUIContext().px2vp(16 * 3.5))
        .fontWeight(500)
        .backgroundColor('#0A59F7')
        .alignSelf(ItemAlign.Center)
        .textAlign(TextAlign.Center)
        .borderRadius(this.getUIContext().px2vp(20 * 3.5))
        .width(this.getUIContext().px2vp(328 * 3.5))
        .height(this.getUIContext().px2vp(40 * 3.5));
    }
    .width(TrainConstants.FULL_WIDTH)
    .height('90%')
    .alignItems(HorizontalAlign.Start)
    .borderRadius(15);
  }
}
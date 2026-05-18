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
import { ExaminationInfo, ExaminationList } from '../viewmodel/TrainInfoModel';
import { ItemRestriction, SegmentButton, SegmentButtonOptions, SegmentButtonTextItem } from '@kit.ArkUI';

@Component
export struct ExaminationComponent {
  list: ExaminationInfo[] = [];
  @State @Watch('getList') tabSelectedIndexes: number[] = [0];
  @State tabOptions: SegmentButtonOptions = SegmentButtonOptions.tab({
    buttons: [{ text: '全部' }, { text: '未完成' }, {
      text: '已完成'
    }] as ItemRestriction<SegmentButtonTextItem>,
    backgroundColor: '#E5E5E5',
    selectedBackgroundColor: '#FFFFFF',
    textPadding: {
      top: 10,
      right: 10,
      bottom: 10,
      left: 10
    }
  });

  aboutToAppear(): void {
    this.getList();
  }

  getList() {
    if (this.tabSelectedIndexes[0] === 0) {
      this.list = ExaminationList;
    } else if (this.tabSelectedIndexes[0] === 1) {
      this.list = ExaminationList.filter(v => v.finished === 1); //未完成
    } else if (this.tabSelectedIndexes[0] === 2) {
      this.list = ExaminationList.filter(v => v.finished === 0); //已完成
    }
  }

  build() {
    Column() {
      SegmentButton({ options: this.tabOptions, selectedIndexes: $tabSelectedIndexes })
        .borderRadius(this.getUIContext().px2vp(20 * 3.5))
        .width('100%')
        .margin({
          top: this.getUIContext().px2vp(8 * 3.5),
          bottom: this.getUIContext().px2vp(8 * 3.5)
        });
      List() {
        ForEach(ExaminationList, (item: ExaminationInfo) => {
          ListItem() {
            Row() {
              Row({ space: 10 }) {
                Image($r('app.media.course'))
                  .width(this.getUIContext().px2vp(24 * 3.5))
                  .height(this.getUIContext().px2vp(24 * 3.5));
                Column() {
                  Text(item.title)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width(TrainConstants.FULL_WIDTH)
                    .fontSize(this.getUIContext().px2vp(16 * 3.5))
                    .fontWeight(500);
                  Row() {
                    Text(`时长：${item.hour}秒 `)
                      .fontColor($r('app.color.gray_color'))
                      .fontSize(this.getUIContext().px2vp(14 * 3.5))
                      .fontWeight(400);
                  }
                  .width(TrainConstants.FULL_WIDTH)
                  .justifyContent(FlexAlign.SpaceBetween)
                  .margin({ top: 5 });

                };
              }
              .width(191);

              Button(item.text)
                .fontSize(this.getUIContext().px2vp(14 * 3.5))
                .fontWeight(500)
                .fontColor('#0A59F7')
                .width(this.getUIContext().px2vp(84 * 3.5))
                .height(this.getUIContext().px2vp(28 * 3.5))
                .borderRadius(this.getUIContext().px2vp(14 * 3.5))
                .backgroundColor('rgba(0, 0, 0, 0.05)')
                .onClick(() => {
                  if (this.onClickItem !== undefined) {
                    this.onClickItem();
                  }
                });

            }
            .width('100%')
            .height(this.getUIContext().px2vp(72 * 3.5))
            .justifyContent(FlexAlign.SpaceBetween)
            .padding(16);
          }
          .width('100%');
        }, (item: ExaminationInfo) => JSON.stringify(item));
      }
      .divider({
        strokeWidth: 2,
        startMargin: 50,
        endMargin: 16
      })
      .borderRadius(20)
      .backgroundColor(Color.White);
    }
    .width('100%')
    .borderRadius(this.getUIContext().px2vp(12 * 3.5));
  }

  private onClickItem = () => {
  };
}
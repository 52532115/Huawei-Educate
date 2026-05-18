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
import { CourseInfo, CourseList } from '../viewmodel/TrainInfoModel';
import { CourseListComponent } from './CourseList';
import { ItemRestriction, SegmentButton, SegmentButtonOptions, SegmentButtonTextItem } from '@kit.ArkUI';

@Component
export struct CourseComponent {
  @State list: CourseInfo[] = [];
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
      this.list = CourseList;
    } else if (this.tabSelectedIndexes[0] === 1) {
      this.list = CourseList.filter(v => v.finished === 1); //未完成
    } else if (this.tabSelectedIndexes[0] === 2) {
      this.list = CourseList.filter(v => v.finished === 0); //已完成
    }
  }

  build() {
    Column() {
      SegmentButton({ options: this.tabOptions, selectedIndexes: $tabSelectedIndexes })
        .borderRadius(this.getUIContext().px2vp(20 * 3.5))
        .width('100%')
        .margin({ top: this.getUIContext().px2vp(8 * 3.5) });
      CourseListComponent({
        courseList: this.list
      })
        .width('100%')
        .margin({
          top: 10
        });
    }
    .backgroundColor('#F1F3F5')
    .width(TrainConstants.FULL_WIDTH)
    .height(TrainConstants.FULL_HEIGHT);
  }
}
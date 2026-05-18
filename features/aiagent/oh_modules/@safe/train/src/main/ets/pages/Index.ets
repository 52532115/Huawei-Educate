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
import { CourseListComponent } from '../view/CourseList';

@Component
export struct TrainPage {
  @StorageProp('topRectHeight') topRectHeight: number = 0;
  @State courseList: CourseInfo[] = CourseList;

  build() {
    NavDestination() {
      Column() {
        Row() {
          Text('我的课程')
            .fontSize(this.getUIContext().px2vp(26 * 3.5))
            .fontWeight(700)
            .textAlign(TextAlign.Start)
            .width(TrainConstants.FULL_WIDTH);
        }
        .margin({
          top: 16,
          right: 16,
          left: 16,
          bottom: 8
        });

        Column() {
          CourseListComponent({
            courseList: $courseList
          });
        }
        .margin({
          top: 16,
          right: 16,
          left: 16
        })
        .layoutWeight(1);
      }
      .width(TrainConstants.FULL_WIDTH)
      .height(TrainConstants.FULL_HEIGHT);
    }
    .hideTitleBar(true)
    .padding({ top: this.getUIContext().px2vp(this.topRectHeight) })
    .backgroundColor('#F1F3F5');
  }
}
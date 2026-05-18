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

@Component
export struct EmptyComponent {
  @Prop message: string;

  build() {
    //缺省图
    Column() {
      Image($r('app.media.empty'))
        .width(160)
        .height(160);
      Text(this.message ?? '暂无数据')
        .fontColor('#aaaaaa')
        .margin({
          top: 15
        });
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .width(TrainConstants.FULL_WIDTH)
    .height(TrainConstants.FULL_HEIGHT);
  }
}
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

import { StyleConstants } from '@safe/basic';
import { OnlineDetailParam } from '../viewmodel/OnlineListModel';

@Component
export struct OnlineDetail {
  @StorageProp('topRectHeight') topRectHeight: number = 0;
  @State title: string = '学习通知';
  @State content: string = '加载中...';
  pathStack: NavPathStack = AppStorage.get('pathStack') as NavPathStack;

  build() {
    NavDestination() {
      Column() {
        Text(this.content)
          .fontSize(16)
          .fontColor('#333333')
          .margin({ top: 32, left: 16, right: 16 })
          .width(StyleConstants.FULL_WIDTH);

        Blank();
      }
      .width(StyleConstants.FULL_WIDTH)
      .height(StyleConstants.FULL_HEIGHT)
      .backgroundColor('#f5f5f5');
    }
    .title(this.title)
    .onReady((ctx: NavDestinationContext) => {
      let p = ctx?.pathInfo?.param as OnlineDetailParam;
      if (p?.type === 'checkin') {
        this.title = '签到提醒';
        this.content = '请及时完成今日签到，签到截止时间为 09:00。';
      } else if (p?.type === 'exam') {
        this.title = '考试通知';
        this.content = '您有一场考试即将开始，请提前做好准备，准时参加考试。';
      } else if (p?.type === 'grade') {
        this.title = '成绩通知';
        this.content = '您的考试成绩已发布，请及时查看各科成绩详情。';
      }
    })
    .padding({ top: this.getUIContext().px2vp(this.topRectHeight) });
  }
}

@Builder
export function OnlineDetailBuilder() {
  OnlineDetail();
}

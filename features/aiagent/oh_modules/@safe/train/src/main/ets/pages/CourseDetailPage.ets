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
import { CourseIntroduce } from '../view/CourseIntroduce';
import { CourseEvaluate } from '../view/CourseEvaluate';
import { IdInfo, NavInfo } from '../viewmodel/NavInfoModel';
import { AVPlayerDemo } from '../view/AVPlayerDemo';

interface TabBarInfo {
  title: string;
  index: number;
}

@Component
export struct CourseDetailPage {
  @State detailInfo: CourseInfo = new CourseInfo();
  @State currentIndex: number = 0;
  @State params: NavInfo = new NavInfo('课程', '');
  @State title: string = '课程';
  @StorageProp('topRectHeight') topRectHeight: number = 0;
  private tabsController: TabsController = new TabsController();
  private tabBarList: TabBarInfo[] = [
    {
      title: '介绍',
      index: 0
    },
    {
      title: '评论',
      index: 1
    }
  ];

  @Builder
  TabBarBuilder(title: string, targetIndex: number) {
    Text(title)
      .fontWeight(targetIndex === this.currentIndex ? FontWeight.Bold : FontWeight.Normal)
      .padding(5)
      .padding(5)
      .border(targetIndex === this.currentIndex ? {
        width: { bottom: 2 },
        color: { bottom: $r('app.color.blue_text_color') },
        style: {
          bottom: BorderStyle.Solid
        }
      } : {
        width: { bottom: 0 },
      })
      .onClick(() => {
        this.tabsController.changeIndex(targetIndex);
      });
  }

  build() {
    NavDestination() {
      Column() {
        AVPlayerDemo()
          .height(220)
          .width('100%');
        Tabs({ controller: this.tabsController, index: this.currentIndex }) {
          ForEach(this.tabBarList, (item: TabBarInfo) => {
            TabContent() {
              if (item.index === 0) {
                CourseIntroduce({
                  info: this.detailInfo
                });
              } else {
                CourseEvaluate();
              }
            }
            .backgroundColor(item.index === 0 ? Color.Brown : Color.Pink)
            .tabBar(this.TabBarBuilder(item.title, item.index));
          }, (item: TabBarInfo) => JSON.stringify(item));
        }

        .onChange((index: number) => {
          this.currentIndex = index;
        }

        );
      }
      .width(TrainConstants.FULL_WIDTH)
      .height(TrainConstants.FULL_HEIGHT);
    }
    .title(this.detailInfo.title)
    .onReady((ctx: NavDestinationContext) => {
      this.params = (ctx?.pathInfo?.param as NavInfo);
      this.title = this.params.title;
      let id = (JSON.parse(this.params.params) as IdInfo).id;
      this.detailInfo = CourseList.find(v => v.id === id) as CourseInfo;
      this.title = this.detailInfo.title as string;
    })
    .padding({ top: this.getUIContext().px2vp(this.topRectHeight) });

  }
}

@Builder
export function CourseDetailPageBuilder() {
  CourseDetailPage();
}
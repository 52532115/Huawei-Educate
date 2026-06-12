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

import { TrainPage } from '@safe/train';
import { MinePage } from '@safe/mine';
import { OnlineIndexView } from '@safe/online';
import { HomeView } from '@safe/home';
import { AiChatView, History } from '@safe/aiagent';
import { CustomTabBar } from './Tab';

@Entry
@Component
struct Index {
  @StorageProp('bottomRectHeight') bottomRectHeight: number = 0;
  @StorageLink('currentTabIndex') currentTabIndex: number = 0;
  pathStack: NavPathStack = new NavPathStack();
  private controller: TabsController = new TabsController();

  aboutToAppear() {
    AppStorage.setOrCreate('pathStack', this.pathStack);
    AppStorage.setOrCreate('currentTabIndex', 0);
  }

  build() {
    Navigation(this.pathStack) {
      Column() {
        Tabs({
          index: this.currentTabIndex,
          controller: this.controller
        }) {
          TabContent() {
            Column() {
              HomeView();
            };
          };

          TabContent() {
            TrainPage();
          };

          TabContent() {
            AiChatView();
          };

          TabContent() {
            OnlineIndexView();
          };

          TabContent() {
            MinePage();
          };
        }
        .clip(false)
        .layoutWeight(1)
        .barHeight(0)
        .scrollable(false)
        .onChange((index: number) => {
          this.currentTabIndex = index;
        });

        CustomTabBar({ currentTabIndex: $currentTabIndex })
          .padding({ bottom: this.getUIContext().px2vp(this.bottomRectHeight) });
      }
      .backgroundColor('#F1F3F5');
    }
    .navDestination(this.mapNavDestination)
    .hideTitleBar(true)
    .hideToolBar(true);
  }

  @Builder
  mapNavDestination(name: string) {
    if (name === 'History') {
      History();
    }
  }
}
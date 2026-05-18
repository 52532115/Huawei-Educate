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

export class TabBarDataType {
  id: number;
  defaultIcon: ResourceStr;
  selectedIcon: ResourceStr;
  title: string;

  constructor(id: number, defaultIcon: ResourceStr, selectedIcon: ResourceStr, title: string) {
    this.id = id;
    this.defaultIcon = defaultIcon;
    this.selectedIcon = selectedIcon;
    this.title = title;
  }
}

export const tabInfo: TabBarDataType[] = [
  new TabBarDataType(0, $r('app.media.ic_public_home_filled'), $r('app.media.home_selected'), '首页'),
  new TabBarDataType(1, $r('app.media.ic_public_appstore_filled'), $r('app.media.appstore_selected'), '课程'),
  new TabBarDataType(2, $r('app.media.ic_public_cards_filled'), $r('app.media.ic_public_cards_filled_1'), 'AI助教'),
  new TabBarDataType(3, $r('app.media.ic_public_comments_filled'), $r('app.media.comments_selected'), '消息'),
  new TabBarDataType(4, $r('app.media.mine'), $r('app.media.mine_selected'), '我的'),
];

@Component
export struct CustomTabBar {
  @Link currentTabIndex: number;

  build() {
    Flex({ direction: FlexDirection.Row, justifyContent: FlexAlign.SpaceAround, alignItems: ItemAlign.Center }) {
      ForEach(tabInfo, (item: TabBarDataType, tabIndex: number) => {
        // 单独一个TabBar组件
        TabItem({
          tabBarIndex: tabIndex,
          currentTabIndex: $currentTabIndex,
        });
      });
    }
    .height(48);
  }
}

@Component
export struct TabItem {
  @Prop tabBarIndex: number; // tabBar下标
  @Link currentTabIndex: number; // 初始化被选定的tabBar下标

  build() {
    Column({ space: 2 }) {
      Image(this.currentTabIndex === this.tabBarIndex ? tabInfo[this.tabBarIndex].selectedIcon :
        tabInfo[this.tabBarIndex].defaultIcon)
        .interpolation(ImageInterpolation.High)
        .width(24)
        .height(24);
      Text(tabInfo[this.tabBarIndex].title)
        .fontSize(10)
        .fontWeight(500)
        .fontColor(this.currentTabIndex === this.tabBarIndex ? $r('app.color.tab_choose_image') :
          'rgba(0, 0, 0, 0.6)')
        .height(14);
    }
    .height(48)
    .padding({ top: 6 })
    .onClick(() => {
      // 更新被选中的tabBar下标
      this.currentTabIndex = this.tabBarIndex;
    });
  }
}
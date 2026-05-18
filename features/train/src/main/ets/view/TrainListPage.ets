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
import { TrainInfo, TrainList } from '../viewmodel/TrainInfoModel';
import { EmptyComponent } from './Empty';
import { IdInfo, NavInfo } from '../viewmodel/NavInfoModel';
import { hilog } from '@kit.PerformanceAnalysisKit';

@Component
export struct TrainListPage {
  @Prop dataList: TrainInfo[] = TrainList;
  pathStack: NavPathStack = AppStorage.get('pathStack') as NavPathStack;

  //跳转详情页
  goToDetail(id: number) {
    let obj: IdInfo = new IdInfo(id);
    let params = new NavInfo('课程', JSON.stringify(obj));
    this.pathStack.pushPathByName('TrainDetailPage', params);
  }

  build() {
    NavDestination() {
      Column() {
        if (this.dataList.length > 0) {
          List({
            space: 8
          }) {
            ForEach(this.dataList, (item: TrainInfo, index: number) => {
              ListItem() {
                Column() {
                  Stack({
                    alignContent: Alignment.TopEnd
                  }) {
                    Image(item.img)
                      .width('160vp')
                      .height('180vp')
                      .borderRadius({
                        topRight: 12,
                        topLeft: 12
                      });
                    // .objectFit(ImageFit.Cover);
                    Text(`${item.count}`)
                      .width(36)
                      .height(22)
                      .textAlign(TextAlign.Center)
                      .opacity(0.8)
                      .fontColor(Color.White)
                      .fontSize(10)
                      .linearGradient({
                        direction: GradientDirection.RightTop,
                        colors: [
                          ['#00c6ff', 0.0],
                          ['#0072ff', 1.0]
                        ]
                      })
                      .borderRadius({
                        topRight: 12,
                        bottomLeft: 12
                      })
                      .padding({
                        top: 2,
                        right: 8,
                        bottom: 2,
                        left: 8
                      });
                  };

                  Text(item.title)
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .fontFamily('HarmonyHeiTi')
                    .fontSize(14)
                    .fontWeight(500)
                    .margin({
                      top: 8,
                      bottom: 4,
                      right: 10,
                      left: 4
                    })
                    .lineHeight(19);
                  Text(`${item.startTime} - ${item.startTime}`)
                    .wordBreak(WordBreak.BREAK_ALL)
                    .width(TrainConstants.FULL_WIDTH)
                    .fontSize(12)
                    .fontFamily('HarmonyHeiTi')
                    .margin({
                      top: 8,
                      bottom: 4,
                      left: 14
                    });
                  Text(`已有${item.applyNum}人报名`)
                    .fontColor('#aaaaaa')
                    .fontFamily('HarmonyHeiTi')
                    .width(TrainConstants.FULL_WIDTH)
                    .margin({
                      top: 4,
                      bottom: 8,
                      left: 14
                    })
                    .fontSize(12);
                }
                .width('160vp')
                .height('286vp')
                .backgroundColor(Color.White)
                .borderRadius(12);
              }
              .onClick(() => {
                this.goToDetail(item.id);
                hilog.info(0x0001, '[Scan CPSample]', 'Promise scan result: %{public}s', JSON.stringify(index));
                ;
              });

            }, (item: TrainInfo) => JSON.stringify(item));
          }
          .scrollBar(BarState.Off)
          .lanes(TrainConstants.LIST_LANES_NUM, 10)
          .alignListItem(ListItemAlign.Center)
          .edgeEffect(EdgeEffect.None);
        } else {
          //缺省图
          EmptyComponent({
            message: '暂无数据'
          });
        }
      }
      .width(TrainConstants.FULL_WIDTH)
      .height(TrainConstants.FULL_HEIGHT)
      .backgroundColor('#F1F3F5');
    }
    .hideTitleBar(true);
  }
}
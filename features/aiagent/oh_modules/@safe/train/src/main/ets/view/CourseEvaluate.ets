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
import { CourseEvaluateInfo, CourseEvaluateList } from '../viewmodel/TrainInfoModel';

@Component
export struct CourseEvaluate {
  @State count: number = 4;
  totalNum: number = 1029;

  build() {
    Column() {
      Column() {
        Text('评价该课程')
          .margin({
            bottom: 5
          });
        Rating({ rating: this.count, indicator: false })
          .stars(5)
          .stepSize(0.5)
          .width(120)
          .margin({
            right: 5
          });
      }
      .backgroundColor(Color.White)
      .width(TrainConstants.FULL_WIDTH)
      .padding({
        top: 10,
        bottom: 10
      });


      Column() {
        Text(`评价详情(${this.totalNum}个评价)`)
          .width(TrainConstants.FULL_WIDTH)
          .margin({
            top: 10,
            bottom: 8
          });
        List() {
          ForEach(CourseEvaluateList, (item: CourseEvaluateInfo) => {
            ListItem() {
              Row() {
                Image(item.img)
                  .width(32)
                  .height(32)
                  .margin({
                    right: 10
                  });
                Column() {
                  Row() {
                    Text(item.name);
                    Rating({ rating: item.starCount, indicator: false })
                      .stars(5)
                      .stepSize(0.5)
                      .width(120)
                      .onChange((value: number) => {
                        item.starCount = value;
                      })
                      .padding({
                        right: 50
                      });
                  }
                  .width(TrainConstants.FULL_WIDTH)
                  .justifyContent(FlexAlign.SpaceBetween);

                  Text(item.time)
                    .fontColor($r('app.color.gray_color'))
                    .margin({
                      top: 6,
                      bottom: 15
                    });
                  Text(item.content)
                    .width(TrainConstants.FULL_WIDTH)
                    .wordBreak(WordBreak.BREAK_ALL)
                    .padding({
                      right: 50
                    });

                }
                .alignItems(HorizontalAlign.Start);
              }
              .width(TrainConstants.FULL_WIDTH)
              .alignItems(VerticalAlign.Top)
              .margin({
                top: 10,
                bottom: 10
              });
            };
          }, (item: CourseEvaluateInfo) => JSON.stringify(item));
        }
        .divider({ strokeWidth: 2, color: '#eeeeee' }); // 每行之间的分界线
      }
      .width(TrainConstants.FULL_WIDTH)
      .layoutWeight(1)
      .backgroundColor(Color.White)
      .padding(10)
      .margin({
        top: 10
      });

    }
    .width(TrainConstants.FULL_WIDTH)
    .height(TrainConstants.FULL_HEIGHT)
    .backgroundColor($r('app.color.page_gray_color'));

  }
}
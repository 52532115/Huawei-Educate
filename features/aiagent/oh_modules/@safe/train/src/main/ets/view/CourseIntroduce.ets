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
import { CourseInfo } from '../viewmodel/TrainInfoModel';

@Component
export struct CourseIntroduce {
  @Prop info: CourseInfo;
  @State count: number = 4;

  build() {
    Column() {
      Column() {
        Text($r('app.string.string_desc'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Start)
          .width(TrainConstants.FULL_WIDTH)
          .fontSize(16)
          .padding({
            top: 5,
            bottom: 5,
            left: 10,
            right: 10
          });

        Row() {
          Row() {
            Rating({ rating: this.count, indicator: false })
              .stars(5)
              .stepSize(0.5)
              .width(90)
              .margin({
                right: 5
              });
            Text($r('app.string.string_nums'))
              .fontSize(14)
              .margin({
                right: 5
              });
            Text($r('app.string.string_desc'))
              .fontSize(14);
          };

          Text($r('app.string.string_desc'))
            .fontSize(14);
        }
        .width(TrainConstants.FULL_WIDTH)
        .justifyContent(FlexAlign.SpaceBetween)
        .padding({
          left: 10,
          right: 10,
          bottom: 5
        })
        .border({
          width: { bottom: 1 },
          color: '#eeeeee',
          style: {
            bottom: BorderStyle.Solid
          }
        });


        Column() {
          Row() {
            Row() {
              Text($r('app.string.string_desc'))
                .fontSize(14)
                .margin({
                  right: 5
                });
              Text($r('app.string.string_desc'))
                .fontSize(14);
            }
            .width(160);
          }
          .width(TrainConstants.FULL_WIDTH);

          Row() {
            Row() {
              Text('时        长：')
                .fontSize(14)
                .margin({
                  right: 5
                });
              Text('18分钟')
                .fontSize(14);
            }
            .width(160);

            Row() {
              Text('进度：')
                .fontSize(14)
                .margin({
                  right: 5
                });
              Text('0.00%')
                .fontSize(14);
            }
            .layoutWeight(1);
          }
          .width(TrainConstants.FULL_WIDTH)
          .justifyContent(FlexAlign.SpaceBetween)
          .margin({
            top: 5,
          });
        }
        .width(TrainConstants.FULL_WIDTH)
        .padding(10);

      }
      .backgroundColor(Color.White);

      Column() {
        Row() {
          Text()
            .width(4)
            .height(14)
            .backgroundColor('#ffab01')
            .margin({
              right: 6
            });
          Text('课程介绍')
            .fontSize(14);
        }
        .width(TrainConstants.FULL_WIDTH)
        .margin({
          bottom: 8
        });

        Row() {
          Text($r('app.string.introduction'))
            .textAlign(TextAlign.Start)
            .fontSize(14)
            .wordBreak(WordBreak.BREAK_ALL)
            .fontColor($r('app.color.gray_color'))
            .lineHeight(18);
        }
        .width(TrainConstants.FULL_WIDTH)
        .justifyContent(FlexAlign.Start)
        .alignItems(VerticalAlign.Top)
        .layoutWeight(1);

      }
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
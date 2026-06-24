/*
 *  Copyright (c) 2025 Huawei Device Co., Ltd.
 *  Licensed under the Apache License, Version 2.0 (the "License");
 *  you may not use this file except in compliance with the License.
 *  You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 *
 */

import { ResManager } from '@safe/basic';
import { getErrorModels, deleteErrorModel } from '../viewmodel/MineLocalData';
import { MineErrorModel } from '../viewmodel/MineErrorModel';
import { promptAction } from '@kit.ArkUI';

@Component
export struct MineErrorPage {
  @StorageProp('topRectHeight') topRectHeight: number = 0;
  pathStack: NavPathStack = AppStorage.get('pathStack') as NavPathStack;
  @State errorList: MineErrorModel[] = [];
  private tagLabels: string[] = ['A', 'B', 'C', 'D', 'E', 'F'];

  aboutToAppear(): void {
    this.refreshList();
  }

  refreshList(): void {
    this.errorList = getErrorModels();
  }

  handleDelete(id: string): void {
    AlertDialog.show({
      title: '确认删除',
      message: '确定要删除这道错题吗？删除后不可恢复。',
      primaryButton: {
        value: '取消',
        action: () => {
        },
      },
      secondaryButton: {
        value: '删除',
        fontColor: '#FF4444',
        action: () => {
          deleteErrorModel(id);
          this.refreshList();
          promptAction.showToast({ message: '已删除', duration: 1500 });
        },
      },
    });
  }

  handleAiAnalysis(): void {
    // Navigate to AI chat tab with error analysis trigger
    AppStorage.setOrCreate('triggerErrorAnalysis', true);
    // Switch to AI tab (index 2)
    const tabIndex = AppStorage.get<number>('currentTabIndex');
    if (tabIndex !== undefined) {
      AppStorage.setOrCreate('currentTabIndex', 2);
    }
    this.pathStack.clear();
  }

  handleAiAttribution(): void {
    AppStorage.setOrCreate('triggerErrorAttribution', true);
    const tabIndex = AppStorage.get<number>('currentTabIndex');
    if (tabIndex !== undefined) {
      AppStorage.setOrCreate('currentTabIndex', 2);
    }
    this.pathStack.clear();
  }

  getOptionLabel(index: number): string {
    return index < this.tagLabels.length ? this.tagLabels[index] : String.fromCharCode(65 + index);
  }

  @Builder
  ErrorListItem(model: MineErrorModel, index: number) {
    Column({ space: 0 }) {
      // Header: knowledge tag + delete
      Flex({ direction: FlexDirection.Row, justifyContent: FlexAlign.SpaceBetween }) {
        Row({ space: 4 }) {
          if (model.knowledgeTag) {
            Text(model.knowledgeTag)
              .fontSize(11)
              .fontColor('#409eff')
              .backgroundColor('#ECF5FF')
              .borderRadius(4)
              .padding({ left: 8, right: 8, top: 2, bottom: 2 });
          }
          Text(`#${index + 1}`)
            .fontSize(11)
            .fontColor('#999999');
        };

        Image($r('app.media.delete'))
          .objectFit(ImageFit.Cover)
          .height($r('app.float.list_icon_height'))
          .width($r('app.float.list_icon_height'))
          .onClick(() => {
            this.handleDelete(model.id);
          });
      }
      .margin({ bottom: 8 });

      // Question title
      Text(model.title)
        .fontWeight(FontWeight.Medium)
        .fontSize(15)
        .fontColor('#333333')
        .lineHeight(22);

      // Options list
      Column({ space: 4 }) {
        ForEach(model.option, (opt: string, optIndex: number) => {
          Row() {
            Text(`${this.getOptionLabel(optIndex)}. ${opt}`)
              .fontSize(13)
              .fontColor(optIndex === model.rightQues ? '#67C23A' :
                (optIndex === model.answer ? '#F56C6C' : '#666666'))
              .fontWeight(optIndex === model.rightQues || optIndex === model.answer ?
                FontWeight.Bold : FontWeight.Normal);
          }
          .width('100%')
          .padding({ left: 8, right: 8, top: 6, bottom: 6 })
          .backgroundColor(optIndex === model.rightQues ? '#F0F9EB' :
            (optIndex === model.answer ? '#FEF0F0' : '#F5F5F5'))
          .borderRadius(4);
        });
      }
      .margin({ top: 8 });

      // Answer comparison
      Row({ space: 16 }) {
        Text() {
          Span('正确: ')
            .fontSize(12)
            .fontColor('#999999');
          Span(this.getOptionLabel(model.rightQues))
            .fontSize(12)
            .fontColor('#67C23A')
            .fontWeight(FontWeight.Bold);
        };

        if (model.answer !== undefined && model.answer >= 0) {
          Text() {
            Span('我的: ')
              .fontSize(12)
              .fontColor('#999999');
            Span(this.getOptionLabel(model.answer))
              .fontSize(12)
              .fontColor('#F56C6C')
              .fontWeight(FontWeight.Bold);
          };
        }
      }
      .margin({ top: 8 });

      // User note section
      if (model.userNote) {
        Row() {
          Column({ space: 2 }) {
            Text('📝 学习笔记')
              .fontSize(11)
              .fontColor('#E6A23C')
              .fontWeight(FontWeight.Medium);
            Text(model.userNote)
              .fontSize(13)
              .fontColor('#555555')
              .lineHeight(18)
              .maxLines(4)
              .textOverflow({ overflow: TextOverflow.Ellipsis });
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1);
        }
        .width('100%')
        .padding(10)
        .backgroundColor('#FDF6EC')
        .borderRadius(6)
        .margin({ top: 8 });
      }

      // Mistake reasoning section
      if (model.mistakeReason) {
        Row() {
          Column({ space: 2 }) {
            Text('❌ 错误思路')
              .fontSize(11)
              .fontColor('#F56C6C')
              .fontWeight(FontWeight.Medium);
            Text(model.mistakeReason)
              .fontSize(13)
              .fontColor('#555555')
              .lineHeight(18)
              .maxLines(4)
              .textOverflow({ overflow: TextOverflow.Ellipsis });
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1);
        }
        .width('100%')
        .padding(10)
        .backgroundColor('#FEF0F0')
        .borderRadius(6)
        .margin({ top: 4 });
      }

      // AI analysis badge
      if (model.analysis) {
        Row() {
          Column({ space: 2 }) {
            Text('🤖 AI分析')
              .fontSize(11)
              .fontColor('#409eff')
              .fontWeight(FontWeight.Medium);
            Text(model.analysis)
              .fontSize(12)
              .fontColor('#555555')
              .lineHeight(17)
              .maxLines(3)
              .textOverflow({ overflow: TextOverflow.Ellipsis });
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1);
        }
        .width('100%')
        .padding(10)
        .backgroundColor('#ECF5FF')
        .borderRadius(6)
        .margin({ top: 4 });
      }

      // Time
      if (model.createTime > 0) {
        Text(this.formatTime(model.createTime))
          .fontSize(10)
          .fontColor('#C0C4CC')
          .margin({ top: 8 });
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor(Color.White)
    .borderRadius(10)
    .margin({ left: 12, right: 12 });
  }

  formatTime(timestamp: number): string {
    const d = new Date(timestamp);
    const year = d.getFullYear();
    const month = (d.getMonth() + 1).toString().padStart(2, '0');
    const day = d.getDate().toString().padStart(2, '0');
    const hour = d.getHours().toString().padStart(2, '0');
    const min = d.getMinutes().toString().padStart(2, '0');
    return `添加于 ${year}-${month}-${day} ${hour}:${min}`;
  }

  @Builder
  EmptyView() {
    Column({ space: 12 }) {
      Text('📋')
        .fontSize(48);
      Text('暂无错题记录')
        .fontSize(16)
        .fontColor('#999999')
        .fontWeight(FontWeight.Medium);
      Text('点击右上角 "+" 添加错题')
        .fontSize(13)
        .fontColor('#C0C4CC');
      Button('添加第一道错题')
        .fontSize(14)
        .fontColor(Color.White)
        .backgroundColor('#409eff')
        .borderRadius(20)
        .onClick(() => {
          this.pathStack.pushPathByName('MineAddErrorPage', null);
        });
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center);
  }

  @Builder
  BottomActions() {
    Row({ space: 8 }) {
      Button() {
        Row({ space: 4 }) {
          Text('🤖')
            .fontSize(14);
          Text('AI 分析错题')
            .fontSize(12)
            .fontColor(Color.White);
        };
      }
      .layoutWeight(1)
      .height(42)
      .backgroundColor('#1A56DB')
      .borderRadius(8)
      .onClick(() => {
        this.handleAiAnalysis();
      });

      Button() {
        Row({ space: 4 }) {
          Text('🔎')
            .fontSize(14);
          Text('智能归因')
            .fontSize(12)
            .fontColor(Color.White);
        };
      }
      .layoutWeight(1)
      .height(42)
      .backgroundColor('#D97706')
      .borderRadius(8)
      .onClick(() => {
        this.handleAiAttribution();
      });

      Button() {
        Row({ space: 4 }) {
          Text('+')
            .fontSize(18)
            .fontColor('#409eff');
          Text('添加错题')
            .fontSize(12)
            .fontColor('#409eff');
        };
      }
      .layoutWeight(1)
      .height(42)
      .backgroundColor(Color.White)
      .borderRadius(8)
      .border({ width: 1, color: '#409eff' })
      .onClick(() => {
        this.pathStack.pushPathByName('MineAddErrorPage', null);
      });
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor('#FAFAFA')
    .border({ width: { top: 1 }, color: '#EBEBEB' });
  }

  build() {
    NavDestination() {
      Column() {
        // Header
        Row() {
          RelativeContainer() {
            Image(ResManager.getBackIcon())
              .width(ResManager.getVp_twenty())
              .height(ResManager.getVp_twenty())
              .alignRules({
                center: { anchor: '__container__', align: VerticalAlign.Center },
                left: { anchor: '__container__', align: HorizontalAlign.Start }
              })
              .id('back')
              .margin({ left: this.getUIContext().vp2px(5) })
              .onClick(() => {
                this.pathStack.pop();
              });

            Text('错题集')
              .fontWeight(FontWeight.Medium)
              .fontColor('#333333')
              .fontSize(17)
              .alignRules({
                middle: { anchor: '__container__', align: HorizontalAlign.Center },
                center: { anchor: 'back', align: VerticalAlign.Center }
              })
              .id('text');

            Text('+ 添加')
              .fontColor('#409eff')
              .fontSize(14)
              .alignRules({
                center: { anchor: '__container__', align: VerticalAlign.Center },
                right: { anchor: '__container__', align: HorizontalAlign.End }
              })
              .id('addBtn')
              .margin({ right: 16 })
              .onClick(() => {
                this.pathStack.pushPathByName('MineAddErrorPage', null);
              });
          };
        }
        .width('100%')
        .height(44)
        .backgroundColor(Color.White);

        // Error question count
        if (this.errorList.length > 0) {
          Row() {
            Text(`共 ${this.errorList.length} 道错题`)
              .fontSize(13)
              .fontColor('#999999');
          }
          .width('100%')
          .padding({ left: 16, top: 8, bottom: 4 });
        }

        // Error list
        if (this.errorList.length === 0) {
          this.EmptyView();
        } else {
          List({ space: 10 }) {
            ForEach(this.errorList, (item: MineErrorModel, index: number) => {
              ListItem() {
                this.ErrorListItem(item, index);
              };
            }, (item: MineErrorModel) => item.id);
          }
          .layoutWeight(1)
          .padding({ top: 4, bottom: 8 });
        }

        // Bottom action bar
        if (this.errorList.length > 0) {
          this.BottomActions();
        }
      };
    }
    .hideTitleBar(true)
    .onShown(() => {
      this.refreshList();
    })
    .padding({ top: this.getUIContext().px2vp(this.topRectHeight) });
  }
}

@Builder
export function MineErrorPageBuilder() {
  MineErrorPage();
}

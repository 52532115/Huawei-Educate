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

import { MineSetListModel } from '../viewmodel/MineSetListModel';
import { setListModels } from '../viewmodel/MineLocalData';
import { Logger, ResManager, StyleConstants } from '@safe/basic';
import { BusinessError } from '@kit.BasicServicesKit';
import { LogoutDialog } from './LogoutDialog';
import fs from '@ohos.file.fs';
import { Context } from '@kit.AbilityKit';

const TAG = 'MineSetPage';

@Component
export struct MineSetPage {
  @StorageProp('topRectHeight') topRectHeight: number = 0;
  pathStack: NavPathStack = AppStorage.get('pathStack') as NavPathStack;
  context: Context = this.getUIContext().getHostContext() as Context;
  dialog: CustomDialogController = new CustomDialogController({
    builder: LogoutDialog({
      confirm: this.onConfirm
    }),
    autoCancel: true,
    gridCount: 4,
    customStyle: false
  });
  cacheDialog: CustomDialogController = new CustomDialogController({
    builder: LogoutDialog({
      confirm: this.clearCache,
      message: '是否清除缓存?'
    }),
    autoCancel: true,
    gridCount: 4,
    customStyle: false
  });

  onCancel() {
  }

  onConfirm() {
  }

  @Builder
  MineListItem(model: MineSetListModel) {
    Flex({
      direction: FlexDirection.Row,
      justifyContent: FlexAlign.SpaceBetween,
      alignItems: ItemAlign.Center
    }) {
      Text(model.text).fontSize(16).fontColor('333333').margin({ left: $r('app.float.list_left_margin') });
      Image($r('app.media.ic_right_arrow'))
        .objectFit(ImageFit.Contain)
        .height($r('app.float.list_icon_height'))
        .width($r('app.float.list_icon_height')).margin({ right: $r('app.float.list_left_margin') });
    }
    .height($r('app.float.icon_person_size'))
    .margin({ left: $r('app.float.list_left_margin'), right: $r('app.float.list_left_margin') })
    .width(StyleConstants.FULL_WIDTH).onClick(() => {
      let routerUrl = model.url;
      if (routerUrl === '/logout') {
        this.dialog.open();
      } else if (routerUrl === '/clear') {
        this.cacheDialog.open();
      } else {
        this.pathStack.pushPathByName(model.url, null);
      }
    });
  }

  clearCache() {
    let cacheDir = this.context.cacheDir;
    fs.listFile(cacheDir).then((filenames) => {
      for (let i = 0; i < filenames.length; i++) {
        let dirPath = cacheDir + filenames[i];
        try {
          // 判断是否文件夹
          let isDirectory = fs.statSync(dirPath).isDirectory();
          if (isDirectory) {
            fs.rmdirSync(dirPath);
          } else {
            fs.unlink(dirPath).then(() => {
            }).catch((err: BusinessError) => {
              Logger.error(TAG, `failed to clear cache,message is ${err.message}`);
            });
          }
        } catch (e) {
          Logger.error(TAG, `failed to clear cache,message is ${(e as BusinessError).message}`);
        }
      }
    });
  }

  @Builder
  itemHead(index: number) {
    Row().backgroundColor('#f5f5f5').width(StyleConstants.FULL_WIDTH)
      .height(index === 0 ? 0 : 10);
  }

  build() {
    NavDestination() {
      Column() {
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
            Text('设置').alignRules({
              middle: { anchor: '__container__', align: HorizontalAlign.Center },
              center: { anchor: 'back', align: VerticalAlign.Center },
            }).fontWeight(FontWeight.Medium).fontColor('333333').id('text');
          };
        }
        .width(StyleConstants.FULL_WIDTH).backgroundColor(Color.White).height(this.getUIContext().vp2px(10));

        List({ space: 10 }) {
          ForEach(setListModels, (item: [], index: number) => {
            ListItemGroup({ space: 10, header: this.itemHead(index) }) {
              ForEach(item, (project: MineSetListModel) => {
                this.MineListItem(project);
              }, (item: MineSetListModel) => item.key);
            }
            .divider({ strokeWidth: 1, color: 'f5f5f5' }); // 每行之间的分界线
          });
        }
        .width('100%')
        .sticky(StickyStyle.Header | StickyStyle.Footer)
        .scrollBar(BarState.Off);
      }
      .width(StyleConstants.FULL_WIDTH)
      .height(StyleConstants.FIFTY_HEIGHT)
      .backgroundColor(0xffffff)
      .padding({ top: 5 });
    }
    .hideTitleBar(true)
    .padding({ top: this.getUIContext().px2vp(this.topRectHeight) });
  }
}

@Builder
export function MineSetPageBuilder() {
  MineSetPage();
}
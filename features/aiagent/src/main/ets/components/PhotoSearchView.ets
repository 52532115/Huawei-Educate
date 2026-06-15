import { http } from '@kit.NetworkKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { promptAction } from '@kit.ArkUI';
import util from '@ohos.util';

interface ApiResponse {
  code: number;
  data: AnswerData;
  msg: string;
}

interface AnswerData {
  answer: string;
}

interface TestResponse {
  message: string;
}

@Component
export struct PhotoSearchView {
  @State questionText: string = '';
  @State selectedImageUri: string = '';
  @State aiAnswer: string = '';
  @State isLoading: boolean = false;
  @State imageFd: number = -1;
  pathStack: NavPathStack = AppStorage.get('pathStack') as NavPathStack;

  build() {
    NavDestination() {
      Column() {
        Row() {
          Button('←')
            .fontSize(18)
            .fontColor('#333333')
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              this.pathStack.pop();
            });

          Text('🔍')
            .fontSize(24)
            .margin({ right: 8 });
          Text('AI 搜题')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1A1A1A');
          Text('Pro')
            .fontSize(12)
            .fontColor('#007DFF')
            .fontWeight(FontWeight.Medium)
            .margin({ left: 4, top: 2 })
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor('#E6F4FF')
            .borderRadius(4);
          Blank();
          Button('📋')
            .fontSize(22)
            .width(44)
            .height(44)
            .backgroundColor('#E6F4FF')
            .borderRadius(22)
            .onClick(() => {
              this.pathStack.pushPathByName('PhotoSearchHistoryView', null);
            });
        }
        .width('100%')
        .padding({ top: 50, bottom: 20, left: 20, right: 20 })
        .backgroundColor(Color.White)
        .shadow({ radius: 8, color: '#0A000000', offsetY: 4 });

        Scroll() {
          Column({ space: 20 }) {
            Column() {
              Row() {
                Text('📝')
                  .fontSize(20)
                  .margin({ right: 8 });
                Text('题目输入')
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#1A1A1A');
              }
              .width('100%')
              .margin({ bottom: 12 });

              TextArea({ placeholder: '请输入题目内容，支持数学、物理、化学等多学科题目...', text: this.questionText })
                .height(160)
                .fontSize(16)
                .fontColor('#333333')
                .placeholderColor('#AAB0BF')
                .onChange((value: string) => {
                  this.questionText = value;
                })
                .backgroundColor('#F7F9FC')
                .borderRadius(16)
                .padding(16);

              Row() {
                Text('添加图片')
                  .fontSize(14)
                  .fontColor('#666666')
                  .fontWeight(FontWeight.Medium);
                Blank();
              }
              .width('100%')
              .margin({ top: 16, bottom: 12 });

              Row({ space: 12 }) {
                if (this.selectedImageUri) {
                  Stack({ alignContent: Alignment.TopEnd }) {
                    Image(this.selectedImageUri)
                      .width(120)
                      .height(120)
                      .borderRadius(12)
                      .objectFit(ImageFit.Cover);

                    Button() {
                      Text('✕')
                        .fontSize(14)
                        .fontColor('#FFFFFF');
                    }
                    .width(28)
                    .height(28)
                    .backgroundColor('#FF4D4F')
                    .borderRadius(14)
                    .shadow({ radius: 4, color: '#1AFF4D4F', offsetY: 2 })
                    .offset({ x: 8, y: -8 })
                    .onClick(() => {
                      this.selectedImageUri = '';
                      this.imageFd = -1;
                    });
                  };
                }

                if (!this.selectedImageUri) {
                  Column() {
                    Text('📷')
                      .fontSize(36);
                    Text('拍照搜题')
                      .fontSize(14)
                      .fontColor('#007DFF')
                      .fontWeight(FontWeight.Medium)
                      .margin({ top: 8 });
                    Text('支持相册选择')
                      .fontSize(12)
                      .fontColor('#AAB0BF')
                      .margin({ top: 2 });
                  }
                  .width(140)
                  .height(140)
                  .justifyContent(FlexAlign.Center)
                  .backgroundColor('#E6F4FF')
                  .borderRadius(16)
                  .border({ width: 2, color: '#007DFF', style: BorderStyle.Dashed })
                  .onClick(() => this.selectImage());
                }

                Column() {
                  Text('🖼️')
                    .fontSize(36);
                  Text('选择相册')
                    .fontSize(14)
                    .fontColor('#909399')
                    .fontWeight(FontWeight.Medium)
                    .margin({ top: 8 });
                  Text('上传截图')
                    .fontSize(12)
                    .fontColor('#AAB0BF')
                    .margin({ top: 2 });
                }
                .width(140)
                .height(140)
                .justifyContent(FlexAlign.Center)
                .backgroundColor('#F7F9FC')
                .borderRadius(16)
                .onClick(() => this.selectImage());
              }
              .width('100%')
              .justifyContent(FlexAlign.Start);
            }
            .width('92%')
            .padding(20)
            .backgroundColor(Color.White)
            .borderRadius(20)
            .margin({ top: 16 })
            .shadow({ radius: 16, color: '#08000000', offsetY: 4 });

            Column() {
              Button() {
                Row() {
                  if (this.isLoading) {
                    LoadingProgress()
                      .width(22)
                      .height(22)
                      .color(Color.White)
                      .margin({ right: 10 });
                  } else {
                    Text('⚡')
                      .fontSize(22)
                      .margin({ right: 10 });
                  }
                  Text(this.isLoading ? 'AI 正在分析...' : '智能搜索')
                    .fontSize(18)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(Color.White);
                };
              }
              .width('100%')
              .height(56)
              .backgroundColor(this.isLoading ? '#A0AEC0' : '#007DFF')
              .borderRadius(28)
              .shadow({ radius: 12, color: this.isLoading ? '#00000000' : '#33007DFF', offsetY: 6 })
              .enabled(!this.isLoading)
              .onClick(() => this.startSearch());
            }
            .width('92%')
            .margin({ top: 8 });

            if (this.aiAnswer || this.isLoading) {
              Column() {
                Row() {
                  Column() {
                    Text('✨')
                      .fontSize(20);
                  }
                  .width(40)
                  .height(40)
                  .justifyContent(FlexAlign.Center)
                  .backgroundColor('#E6F4FF')
                  .borderRadius(20)
                  .margin({ right: 12 });

                  Column() {
                    Text('AI 智能解析')
                      .fontSize(16)
                      .fontWeight(FontWeight.Bold)
                      .fontColor('#1A1A1A');
                    Text('由深度学习模型提供')
                      .fontSize(12)
                      .fontColor('#909399')
                      .margin({ top: 2 });
                  }
                  .alignItems(HorizontalAlign.Start);

                  Blank();

                  if (!this.isLoading && this.aiAnswer) {
                    Button() {
                      Row() {
                        Text('📋')
                          .fontSize(14)
                          .margin({ right: 4 });
                        Text('复制')
                          .fontSize(13)
                          .fontColor('#007DFF');
                      };
                    }
                    .height(32)
                    .backgroundColor('#E6F4FF')
                    .borderRadius(16)
                    .onClick(() => {
                      promptAction.showToast({ message: '已复制到剪贴板' });
                    });
                  }
                }
                .width('100%')
                .margin({ bottom: 16 });

                if (this.isLoading) {
                  Column() {
                    Row({ space: 8 }) {
                      Text('●')
                        .fontSize(8)
                        .fontColor('#007DFF');
                      Text('●')
                        .fontSize(8)
                        .fontColor('#007DFF')
                        .opacity(0.6);
                      Text('●')
                        .fontSize(8)
                        .fontColor('#007DFF')
                        .opacity(0.3);
                    };
                    Text('正在调用 AI 模型...')
                      .fontSize(14)
                      .fontColor('#909399')
                      .margin({ top: 12 });
                  }
                  .width('100%')
                  .padding({ top: 30, bottom: 30 })
                  .alignItems(HorizontalAlign.Center);
                } else {
                  Column() {
                    Text(this.aiAnswer)
                      .fontSize(15)
                      .fontColor('#2D3748')
                      .lineHeight(28)
                      .width('100%')
                      .copyOption(CopyOptions.InApp);
                  }
                  .width('100%')
                  .padding(16)
                  .backgroundColor('#F7F9FC')
                  .borderRadius(12);
                }
              }
              .width('92%')
              .padding(20)
              .backgroundColor(Color.White)
              .borderRadius(20)
              .margin({ top: 8, bottom: 40 })
              .shadow({ radius: 16, color: '#08000000', offsetY: 4 });
            }
          }
          .width('100%')
          .padding({ bottom: 20 });
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off);
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#F0F4F8');
    }
    .hideTitleBar(true);
  }

  async selectImage() {
    try {
      let photoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
      photoSelectOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      photoSelectOptions.maxSelectNumber = 1;
      let photoPicker = new photoAccessHelper.PhotoViewPicker();
      let photoSelectResult = await photoPicker.select(photoSelectOptions);
      if (photoSelectResult && photoSelectResult.photoUris.length > 0) {
        this.selectedImageUri = photoSelectResult.photoUris[0];
        let file = fs.openSync(this.selectedImageUri, fs.OpenMode.READ_ONLY);
        this.imageFd = file.fd;
      }
    } catch (err) {
      console.error('PhotoViewPicker.select failed: ' + JSON.stringify(err));
    }
  }

  async testConnection() {
    try {
      let httpRequest = http.createHttp();
      let url = 'http://10.0.2.2:8000/api/test';
      let response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.OBJECT
      });
      if (response.responseCode === 200) {
        let res = response.result as TestResponse;
        this.getUIContext().getPromptAction().showDialog({
          title: '连接测试成功',
          message: res.message || '后端响应正常'
        });
      } else {
        this.getUIContext().getPromptAction().showToast({ message: '连接失败: ' + response.responseCode });
      }
    } catch (err) {
      this.getUIContext().getPromptAction().showDialog({
        title: '连接异常',
        message: '请检查后端是否启动及网络配置。\n错误码: ' + JSON.stringify(err)
      });
    }
  }

  async startSearch() {
    if (!this.questionText.trim() && !this.selectedImageUri) {
      promptAction.showToast({ message: '请输入题目内容或上传图片' });
      return;
    }

    this.isLoading = true;
    this.aiAnswer = '';

    try {
      let httpRequest = http.createHttp();
      let url = 'http://10.0.2.2:8000/api/ai/qa';

      let headers: Record<string, string> = {
        'Accept': 'application/json'
      };

      let extraData: string | ArrayBuffer = '';

      if (!this.selectedImageUri) {
        headers['Content-Type'] = 'application/x-www-form-urlencoded';
        extraData = `question=${encodeURIComponent(this.questionText.trim())}`;
      } else {
        let boundary = 'Boundary' + Date.now();
        headers['Content-Type'] = `multipart/form-data; boundary=${boundary}`;

        let bodyPrefix = `--${boundary}\r\n`;
        if (this.questionText.trim()) {
          bodyPrefix += `Content-Disposition: form-data; name="question"\r\n\r\n`;
          bodyPrefix += `${this.questionText.trim()}\r\n`;
          bodyPrefix += `--${boundary}\r\n`;
        }
        bodyPrefix += `Content-Disposition: form-data; name="image"; filename="image.jpg"\r\n`;
        bodyPrefix += `Content-Type: image/jpeg\r\n\r\n`;

        let bodySuffix = `\r\n--${boundary}--\r\n`;

        let textEncoder = new util.TextEncoder();
        let prefixUint8 = textEncoder.encode(bodyPrefix);
        let suffixUint8 = textEncoder.encode(bodySuffix);

        let fileData = new ArrayBuffer(0);
        if (this.imageFd !== -1) {
          let stat = fs.statSync(this.imageFd);
          fileData = new ArrayBuffer(stat.size);
          fs.readSync(this.imageFd, fileData);
        }

        let combined = new Uint8Array(prefixUint8.length + fileData.byteLength + suffixUint8.length);
        combined.set(prefixUint8, 0);
        combined.set(new Uint8Array(fileData), prefixUint8.length);
        combined.set(suffixUint8, prefixUint8.length + fileData.byteLength);

        extraData = combined.buffer;
        headers['Content-Length'] = combined.length.toString();
      }

      let options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: extraData,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 30000,
        readTimeout: 30000
      };

      console.info('Sending search request to: ' + url);
      let response = await httpRequest.request(url, options);

      if (response.responseCode === 200) {
        let resultStr = response.result as string;
        let result = JSON.parse(resultStr) as ApiResponse;
        if (result.code === 200) {
          this.aiAnswer = result.data.answer;
        } else {
          this.aiAnswer = '服务提示: ' + (result.msg || '解析失败');
        }
      } else {
        this.aiAnswer = `请求失败\n状态码: ${response.responseCode}\n响应: ${response.result}`;
      }
    } catch (err) {
      this.aiAnswer = '请求异常: ' + JSON.stringify(err);
    } finally {
      this.isLoading = false;
    }
  }
}

@Builder
export function PhotoSearchViewBuilder() {
  PhotoSearchView();
}

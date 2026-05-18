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

import media from '@ohos.multimedia.media';
import { BusinessError } from '@ohos.base';
import { Logger } from '@safe/basic';

const TAG = '[VideoPlayer]';

@Component
export struct AVPlayerDemo {
  @State popupShow: boolean = false;
  @State isOpacity: boolean = false;
  @State isPlay: boolean = false;
  @State currentTime: number = 0;
  @State durationTime: number = 0;
  @State curSpeedIdx: number = 1;
  @State durationStringTime: string = '00:00';
  @State currentStringTime: string = '00:00';
  @State flag: boolean = false;
  @State sourceFiles: media.AVFileDescriptor[] = [];
  @State currentIndex: number = 0;
  private avPlayer: media.AVPlayer | undefined = undefined;
  private xComponentController = new XComponentController();
  private surfaceID: string = '';
  private readonly OPERATE_STATE: Array<string> = ['prepared', 'playing', 'paused', 'completed'];
  private popupArr: [string, media.PlaybackSpeed][] = [
    ['0.75x', media.PlaybackSpeed.SPEED_FORWARD_0_75_X],
    ['1x', media.PlaybackSpeed.SPEED_FORWARD_1_00_X],
    ['1.25x', media.PlaybackSpeed.SPEED_FORWARD_1_25_X],
    ['1.75x', media.PlaybackSpeed.SPEED_FORWARD_1_75_X],
    ['2x', media.PlaybackSpeed.SPEED_FORWARD_2_00_X]
  ];

  aboutToAppear(): void {
    // 初始化AVPlayer
    this.createAVPlayer();
    this.reset();
  }

  aboutToDisappear(): void {
    if (this.avPlayer) {
      this.avPlayer.off('timeUpdate');
      this.avPlayer.off('seekDone');
      this.avPlayer.off('error');
      this.avPlayer.off('stateChange');
      this.avPlayer.release();
    }
  }

  build() {
    Column() {
      Flex({
        direction: FlexDirection.Column,
        justifyContent: FlexAlign.Center
      }) {
        this.VideoPlayer();
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Black);

    }
    .width('100%')
    .height('100%');
  }

  @Builder
  VideoPlayer() {
    Stack({
      alignContent: Alignment.Bottom
    }) {
      Stack() {
        if (!this.isPlay) {
          Image($r('app.media.ic_public_play'))
            .width(50)
            .height(50)
            .zIndex(2)
            .onClick(() => {
              this.play();
            });
        }

        Column() {
          Stack({ alignContent: Alignment.TopStart }) {
            XComponent({
              id: '',
              type: XComponentType.SURFACE,
              libraryname: '',
              controller: this.xComponentController
            })
              .onLoad(() => {
                this.xComponentController.setXComponentSurfaceRect({
                  surfaceWidth: 1920,
                  surfaceHeight: 1080
                });
                this.surfaceID = this.xComponentController.getXComponentSurfaceId();
              })
              .width('100%')
              .height('100%')
              .onClick(() => {
                this.iconOnclick();
              });
          };
        }
        .zIndex(1)
        .onClick(() => {
          this.playOrPause();
        });
      }
      .width('100%')
      .height('100%');

      this.PlayControl();
    }
    .height(220)
    .backgroundColor(Color.Black)
    .width('100%');
  }

  @Builder
  PlayControl() { //控制栏
    Flex({ direction: FlexDirection.Row, justifyContent: FlexAlign.Center, alignItems: ItemAlign.Center }) {
      Flex({ direction: FlexDirection.Column, justifyContent: FlexAlign.Center, alignItems: ItemAlign.Center }) {
        Flex({ direction: FlexDirection.Row, justifyContent: FlexAlign.Center, alignItems: ItemAlign.Center }) {
          Text(this.currentStringTime)
            .fontSize('10vp')
            .fontColor(Color.White)
            .margin({ left: '2vp' });
          Slider({
            value: this.currentTime,
            step: 1,
            min: 0,
            max: this.durationTime,
            style: SliderStyle.OutSet
          })
            .blockColor(Color.White)
            .width('80%')
            .trackColor(Color.Gray)
            .selectedColor(Color.White)
            .showSteps(false)
            .showTips(false)
            .trackThickness(this.isOpacity ? 2 : 4)
            .margin({ left: '2vp' })
            .onChange((value: number, mode: SliderChangeMode) => {
              this.sliderOnchange(value, mode);
            });
          Text(this.durationStringTime)
            .fontSize('10vp')
            .fontColor(Color.White)
            .margin({ left: '2vp' });
        }
        .height(25);


        Flex({ direction: FlexDirection.Row, justifyContent: FlexAlign.SpaceBetween, alignItems: ItemAlign.Center }) {
          Row() {
            Image($r('app.media.ic_previous'))
              .width('20vp')
              .height('20vp')
              .margin({ left: '2vp' })
              .onClick(() => {
                this.goToNextOrPre(-1);
              });
            Image(this.isPlay ? $r('app.media.ic_pause') : $r('app.media.ic_play'))
              .width('20vp')
              .height('20vp')
              .margin({ left: '2vp' })
              .onClick(() => {
                this.iconOnclick();
              });
            Image($r('app.media.ic_next'))
              .width('20vp')
              .height('20vp')
              .margin({ left: '2vp' })
              .onClick(() => {
                this.goToNextOrPre(1);
              });
          };

          Row() {
            Text('倍速')
              .fontSize('12vp')
              .fontColor(Color.White)
              .onClick(() => {
                this.popupShow = !this.popupShow;
              })
              .bindPopup(this.popupShow && this.flag, {
                builder: this.popupBuilder,
                targetSpace: 10,
                width: 50,
                radius: 10,
                enableArrow: false, // 气泡弹出时不显示箭头
                popupColor: Color.Black,
                placement: Placement.Top,
                onStateChange: (e) => {
                  if (!e.isVisible) {
                    this.popupShow = false;
                  }
                }
              });
          };
        }
        .height(25);
      };
    }
    .zIndex(2)
    .padding({ right: '2vp', left: '2vp' })
    .opacity(this.isOpacity ? 0.7 : 1)
    .width('100%')
    .height(50)
    .offset({ x: 0, y: 0 })
    .backgroundBlurStyle(BlurStyle.Thin, { colorMode: ThemeColorMode.DARK });
  }

  // popup构造器定义气泡内容
  @Builder
  popupBuilder() {
    Column({ space: 5 }) {
      ForEach(this.popupArr, (item: [string, media.PlaybackSpeed], index: number) => {
        Column() {
          Text(item[0])
            .fontSize(12)
            .fontColor(this.curSpeedIdx === index ? Color.Pink : Color.Black)
            .fontWeight(this.curSpeedIdx === index ? FontWeight.Bold : FontWeight.Normal);
          Divider().width('90%');
        }
        .onTouch(() => {
          this.curSpeedIdx = index;
        })
        .onClick(() => {
          this.setSpeed(item[1]);
          this.popupShow = false;
          this.curSpeedIdx = index;
        });
      }, (item: [string, media.PlaybackSpeed]) => JSON.stringify(item));
    }
    .margin({ top: 5, bottom: 5 });
  }

  // 注册avplayer回调函数
  setAVPlayerCallback(avPlayer: media.AVPlayer) {
    avPlayer.on('timeUpdate', (time: number) => {
      this.currentTime = Math.floor(time * this.durationTime / avPlayer.duration);
      this.currentStringTime = this.secondToTime(Math.floor(time / 1000));
    });

    // seek操作结果回调函数
    avPlayer.on('seekDone', () => {
    });

    // 监听setSpeed生效的事件
    avPlayer.on('speedDone', () => {
    });

    // error回调监听函数,当avPlayer在操作过程中出现错误时调用 reset接口触发重置流程
    avPlayer.on('error', () => {
      avPlayer.reset(); // 调用reset重置资源，触发idle状态
    });

    // 状态机变化回调函数
    avPlayer.on('stateChange', async (state: string) => {
      switch (state) {
        case 'idle': // 成功调用reset接口后触发该状态机上报
          if (avPlayer) {
            // 网络视频使用avPlayer.url赋值
            avPlayer.url =
              `https://www-file.huawei.com/-/media/corporate/minisite/hc2024/v4/videos/highlights/huawei-connect-2024-summary-cn-1080p.mp4`;
          }
          break;
        case 'initialized': // avplayer 设置播放源后触发该状态上报
          this.reset();
          avPlayer.surfaceId = this.surfaceID;
          avPlayer.prepare();
          break;
        case 'prepared': // prepare调用成功后上报该状态机
          this.flag = true;
          this.durationTime = Math.floor(avPlayer.duration / 1000);
          this.durationStringTime = this.secondToTime(this.durationTime);
          avPlayer.setSpeed(media.PlaybackSpeed.SPEED_FORWARD_1_00_X);
          avPlayer.seek(1, media.SeekMode.SEEK_PREV_SYNC);
          avPlayer.videoScaleType = media.VideoScaleType.VIDEO_SCALE_TYPE_FIT;
          this.curSpeedIdx = 1;
          avPlayer.play();
          break;
        case 'playing': // play成功调用后触发该状态机上报
          this.isPlay = true;
          break;
        case 'paused': // pause成功调用后触发该状态机上报
          this.isPlay = false;
          break;
        case 'stopped': // stop接口成功调用后触发该状态机上报
          this.isPlay = false;
          break;
        case 'completed': // prepare调用成功后上报该状态机
          this.isPlay = false;
          break;
        case 'released':
          break;
        default:
          break;
      }
    });
  }

  reset() {
    this.isPlay = false;
    this.currentTime = 0;
    this.durationTime = 0;
    this.durationStringTime = '00:00';
    this.currentStringTime = '00:00';
    this.flag = false;
  }

  setSpeed(playSpeed: number) {
    if (!this.avPlayer || this.OPERATE_STATE.indexOf(this.avPlayer.state) === -1) {
      return;
    }
    this.avPlayer.setSpeed(playSpeed);
  }

  async play() {
    if (!this.avPlayer || this.OPERATE_STATE.indexOf(this.avPlayer.state) === -1 ||
      this.OPERATE_STATE.indexOf(this.avPlayer.state) === 1) {
      return;
    }
    this.isPlay = true;
    if (this.avPlayer.state === 'completed') {
      this.currentTime = 0;
      this.currentStringTime = '00:00';
      this.avPlayer.seek(1, media.SeekMode.SEEK_PREV_SYNC);
    }
    this.avPlayer.play();
  }

  iconOnclick() {
    if (this.isPlay === true) {
      this.avPlayer?.pause();
      this.isPlay = false;
      this.isOpacity = false;
      return;
    }
    if (this.flag === true) {
      this.avPlayer?.play();
      this.isPlay = true;
      this.isOpacity = true;
    } else {
      // The scheduled task determines whether the video loading is complete.
      let intervalFlag = setInterval(() => {
        if (this.flag === true) {
          this.avPlayer?.play();
          this.isPlay = true;
          this.isOpacity = true;
          clearInterval(intervalFlag);
        }
      }, 100);
    }
  }

  sliderOnchange(value: number, mode: SliderChangeMode) {
    if (!this.avPlayer) {
      return;
    }
    this.currentTime = value;
    if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
      this.isOpacity = false;
    }
    if (mode === SliderChangeMode.End && this.avPlayer) {
      let seekTime: number = value * this.avPlayer.duration / this.durationTime;
      this.currentStringTime = this.secondToTime(Math.floor(seekTime / 1000));
      this.avPlayer.seek(seekTime, media.SeekMode.SEEK_PREV_SYNC);
      this.isOpacity = true;
    }
  }

  /**
   * Seconds converted to HH:mm:ss.
   *
   * @param seconds Maximum video duration (seconds).
   * @return Time after conversion.
   */
  secondToTime(seconds: number): string {
    let hourUnit = 60 * 60;
    let hour: number = Math.floor(seconds / hourUnit);
    let minute: number = Math.floor((seconds - hour * hourUnit) / 60);
    let second: number = seconds - hour * hourUnit - minute * 60;
    let hourStr: string = hour < 10 ? `0${hour.toString()}` : `${hour.toString()}`;
    let minuteStr: string = minute < 10 ? `0${minute.toString()}` : `${minute.toString()}`;
    let secondStr: string = second < 10 ? `0${second.toString()}` : `${second.toString()}`;
    if (hour > 0) {
      return `${hourStr}:${minuteStr}:${secondStr}`;
    }
    if (minute > 0) {
      return `${minuteStr}:${secondStr}`;
    } else {
      return `00:${secondStr}`;
    }
  }

  playOrPause() {
    if (this.avPlayer) {
      if (this.isPlay) {
        this.isPlay = false;
        this.avPlayer.pause();
      } else {
        this.play();
      }
    }
  }

  //创建AVPlayer
  createAVPlayer() {
    media.createAVPlayer().then((video: media.AVPlayer) => {
      if (video != null) {
        this.avPlayer = video;
        this.setAVPlayerCallback(this.avPlayer);
        if (this.avPlayer) {
          //当前链接为参考链接
          this.avPlayer.url =
            `https://www-file.huawei.com/-/media/corporate/minisite/hc2024/v4/videos/highlights/huawei-connect-2024-summary-cn-1080p.mp4`; //设置播放源
        }
      } else {
      }
    }).catch((error: BusinessError) => {
      Logger.error(TAG, `Failed to create avplayer.Cause:${error.message}`);
    });
  }

  setSeek(addSecond: number, curTime?: number) {
    if (!this.avPlayer || this.OPERATE_STATE.indexOf(this.avPlayer.state) === -1) {
      return;
    }
    if (!curTime) {
      curTime = this.avPlayer.currentTime;
    }
    let curMillSeconds: number = curTime + addSecond * 1000;
    curMillSeconds = Math.min(Math.max(curMillSeconds, 0), this.avPlayer.duration);
    this.currentTime = curMillSeconds * this.durationTime / this.avPlayer.duration;
    this.currentStringTime = this.secondToTime(Math.floor(curMillSeconds / 1000));
    this.avPlayer.seek(curMillSeconds, media.SeekMode.SEEK_PREV_SYNC);
  }

  goToNextOrPre(num: number) {
    this.currentIndex += num;
    if (this.currentIndex < 0) {
      this.currentIndex = this.sourceFiles.length - 1;
    } else if (this.currentIndex > this.sourceFiles.length - 1) {
      this.currentIndex = 0;
    }
    if (this.avPlayer) {
      this.avPlayer.reset();
    }
  }

  stopPlay() {
    if (this.avPlayer) {
      this.avPlayer.stop();
      this.reset();
      this.avPlayer.reset();
      this.avPlayer.seek(1, media.SeekMode.SEEK_NEXT_SYNC);
    }
  }
}

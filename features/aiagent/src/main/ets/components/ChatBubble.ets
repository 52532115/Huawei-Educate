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

import { ChatMessage, MessageRole, MessageStatus } from '../viewmodel/ChatModels';

@Component
export struct ChatBubble {
  @Prop message: ChatMessage;

  build() {
    Row() {
      if (this.message.role === MessageRole.USER) {
        Blank();
      }

      Column() {
        if (this.message.role === MessageRole.AI || this.message.role === MessageRole.ANALYSIS) {
          Text('🤖')
            .fontSize(14)
            .margin({ bottom: 2 });
        }

        if (this.message.content) {
          Text(this.message.content)
            .fontSize(14)
            .fontColor(this.message.role === MessageRole.USER ? '#FFFFFF' : '#333333')
            .lineHeight(22)
            .textOverflow({ overflow: TextOverflow.None })
            .maxLines(999);
        } else if (this.message.status === MessageStatus.SENDING) {
          LoadingProgress()
            .width(20)
            .height(20)
            .color('#1A56DB');
        } else {
          Text(this.message.content)
            .fontSize(14)
            .fontColor(this.message.role === MessageRole.USER ? '#FFFFFF' : '#333333')
            .lineHeight(22)
            .textOverflow({ overflow: TextOverflow.None })
            .maxLines(999);
        }

        Text(this.formatTime(this.message.timestamp))
          .fontSize(10)
          .fontColor(this.message.role === MessageRole.USER ? 'rgba(255,255,255,0.7)' : '#AAAAAA')
          .margin({ top: 4 });
      }
      .padding(12)
      .borderRadius(12)
      .backgroundColor(this.getBubbleColor())
      .border({
        width: this.message.role === MessageRole.USER ? 0 : 1,
        color: this.message.role === MessageRole.USER ? '' : '#E5E7EB',
      })
      .constraintSize({ maxWidth: '75%' });

      if (this.message.role !== MessageRole.USER) {
        Blank();
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 6, bottom: 6 });
  }

  private getBubbleColor(): string {
    switch (this.message.role) {
      case MessageRole.USER:
        return '#1A56DB';
      case MessageRole.ANALYSIS:
        return '#F0F9FF';
      case MessageRole.AI:
        return '#FFFFFF';
      default:
        return '#F3F4F6';
    }
  }

  private formatTime(timestamp: number): string {
    const date = new Date(timestamp);
    const hours = date.getHours().toString().padStart(2, '0');
    const minutes = date.getMinutes().toString().padStart(2, '0');
    return `${hours}:${minutes}`;
  }
}

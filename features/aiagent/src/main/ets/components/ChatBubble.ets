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

import { display } from '@kit.ArkUI';
import { ChatMessage, MessageRole, MessageStatus } from '../viewmodel/ChatModels';
import { MarkdownText } from './MarkdownText';

/** Padding of the Row that hosts every bubble, plus this bubble's own padding. */
const BUBBLE_OUTER_PADDING: number = 12 + 12;
const BUBBLE_INNER_PADDING: number = 12 + 12;

/**
 * Width available to the bubble's *content* (inside its own padding), as a
 * concrete vp number.
 *
 * The percentage form this replaced (`constraintSize({ maxWidth: '75%' })`) was
 * only ever a hint: the engine kept measuring the children against the width the
 * Row handed down, so the markdown column came out ~20% wider than the bubble and
 * — the bubble centres its children — spilled past the right edge into the page.
 * A measured screenshot settled it: the white background stopped at x=353 while
 * the text ran to x=424.
 *
 * The fix is to stop resolving percentages altogether and let both the bubble and
 * its content be sized from this same number. See ChatBubble.build().
 */
function resolveBubbleContentWidth(uiContext: UIContext): number {
  let displayWidthVp = 0;
  try {
    displayWidthVp = uiContext.px2vp(display.getDefaultDisplaySync().width);
  } catch (e) {
    // No display available: fall back to the previous 75%-of-360vp estimate.
    displayWidthVp = 0;
  }
  if (displayWidthVp <= 0) {
    return 264 - BUBBLE_INNER_PADDING;
  }
  const budget = displayWidthVp - BUBBLE_OUTER_PADDING - BUBBLE_INNER_PADDING;
  const capped = displayWidthVp * 0.75;
  const contentWidth = budget < capped ? budget : capped;
  // Rounded so the value stays readable in logs; the floor only keeps a
  // degenerate report (a display narrower than the padding) from going negative.
  return Math.round(contentWidth > 96 ? contentWidth : 96);
}

@Component
export struct ChatBubble {
  @Prop message: ChatMessage;
  /**
   * Computed once: the app locks its window to portrait, so the display width
   * cannot change while a bubble is alive. Add a windowSizeChange listener here
   * if free-form resizing is ever enabled.
   */
  @State contentWidth: number = resolveBubbleContentWidth(this.getUIContext());

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

        if (this.message.role === MessageRole.STEP) {
          Row({ space: 6 }) {
            if (this.message.stepDone) {
              Text('✓')
                .fontSize(12)
                .fontColor('#10B981');
            } else {
              LoadingProgress()
                .width(12)
                .height(12)
                .color('#6B7280');
            }
            Text(this.message.content)
              .fontSize(12)
              .fontColor(this.message.stepDone ? '#10B981' : '#6B7280');
          }
          .padding(8);
        } else if (this.message.content && this.message.role === MessageRole.USER) {
          Text(this.message.content)
            .fontSize(14)
            .fontColor('#FFFFFF')
            .lineHeight(22)
            // An intrinsic-width text can out-measure the bubble; pinning it to
            // the bubble's own content width keeps the two in lockstep.
            .width(this.contentWidth)
            .textOverflow({ overflow: TextOverflow.None })
            .maxLines(999);
        } else if (this.message.content) {
          // AI and analysis replies go through the Markdown renderer, wrapped in
          // a *definite* width. `constraintSize({ maxWidth })` on the bubble only
          // caps the bubble itself — the markdown root's `.width('100%')` was
          // still resolved against the Row's available width, so long replies
          // came out wider than their bubble and rendered past its right edge.
          // Declaring the width here is what actually bounds the text.
          Column() {
            MarkdownText({ content: this.message.content, contentWidth: this.contentWidth })
          }
          .width(this.contentWidth)
          // The markdown column is the widest child, so pushing it to the start
          // lines every AI reply up with the 🤖 avatar above it.
          .alignItems(HorizontalAlign.Start);
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
            .width(this.contentWidth)
            .textOverflow({ overflow: TextOverflow.None })
            .maxLines(999);
        }

        if (this.message.role !== MessageRole.STEP) {
          Text(this.formatTime(this.message.timestamp))
            .fontSize(10)
            .fontColor(this.message.role === MessageRole.USER ? 'rgba(255,255,255,0.7)' : '#AAAAAA')
            .margin({ top: 4 });
        }
      }
      .padding(this.message.role === MessageRole.STEP ? 0 : 12)
      .borderRadius(12)
      .backgroundColor(this.getBubbleColor())
      .border({
        width: this.message.role === MessageRole.USER || this.message.role === MessageRole.STEP ? 0 : 1,
        color: this.message.role === MessageRole.USER ? '' : '#E5E7EB',
      })
      // Absolute vp, never a percentage: see resolveBubbleContentWidth. The
      // content it wraps is pinned to the same number, so the cap and the text
      // can no longer disagree.
      .constraintSize({ maxWidth: this.contentWidth + BUBBLE_INNER_PADDING })
      .alignItems(this.getContentAlign());

      if (this.message.role !== MessageRole.USER) {
        Blank();
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 6, bottom: 6 });
  }

  private getContentAlign(): HorizontalAlign {
    // Markdown replies read left-aligned; the plain-text bubbles keep the
    // centred look they already had.
    return this.message.role === MessageRole.AI || this.message.role === MessageRole.ANALYSIS
      ? HorizontalAlign.Start
      : HorizontalAlign.Center;
  }

  private getBubbleColor(): string {
    switch (this.message.role) {
      case MessageRole.USER:
        return '#1A56DB';
      case MessageRole.ANALYSIS:
        return '#F0F9FF';
      case MessageRole.AI:
        return '#FFFFFF';
      case MessageRole.STEP:
        return 'transparent';
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

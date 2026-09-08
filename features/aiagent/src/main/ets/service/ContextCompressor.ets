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

import { ChatMessage, MessageRole } from '../viewmodel/ChatModels';

const SUMMARY_MAX_ITEMS = 10;
const ITEM_MAX_LENGTH = 30;

/**
 * Compresses older conversation turns into a deterministic local summary so
 * early context survives the history window without extra API calls.
 */
export class ContextCompressor {
  buildHistorySummary(olderMessages: ChatMessage[]): string {
    const points: string[] = [];
    for (const message of olderMessages) {
      if (message.role !== MessageRole.USER) {
        continue;
      }
      const text = message.content.trim();
      if (text.length === 0) {
        continue;
      }
      points.push(text.length > ITEM_MAX_LENGTH ? text.substring(0, ITEM_MAX_LENGTH) + '…' : text);
      if (points.length >= SUMMARY_MAX_ITEMS) {
        break;
      }
    }
    if (points.length === 0) {
      return '';
    }

    let summary = '【早前对话要点】以下是更早对话中用户问过的问题摘要，供你参考背景：\n';
    for (const point of points) {
      summary += `- ${point}\n`;
    }
    return summary;
  }
}

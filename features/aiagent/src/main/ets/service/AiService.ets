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

import { http } from '@kit.NetworkKit';
import { AiConstants } from '../utils/AiConstants';
import { AiMessage, AiApiRequest } from '../viewmodel/ChatModels';
import { Logger } from '@safe/basic';

export class AiService {
  private isCancelled: boolean = false;
  private httpRequest: http.HttpRequest | null = null;

  async sendChatMessage(
    messages: AiMessage[],
    onChunk: (chunk: string) => void,
  ): Promise<string> {
    this.isCancelled = false;
    const requestBody: AiApiRequest = new AiApiRequest(
      AiConstants.AI_MODEL,
      messages,
      false,
    );
    requestBody.temperature = 0.7;
    requestBody.max_tokens = 4096;

    const request = http.createHttp();
    this.httpRequest = request;
    let fullContent = '';

    try {
      const response = await request.request(
        AiConstants.AI_API_URL,
        {
          method: http.RequestMethod.POST,
          header: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${AiConstants.API_KEY}`,
          },
          extraData: JSON.stringify(requestBody),
          expectDataType: http.HttpDataType.STRING,
          connectTimeout: AiConstants.REQUEST_TIMEOUT,
          readTimeout: AiConstants.REQUEST_TIMEOUT,
        },
      );

      if (this.isCancelled) {
        return '';
      }

      if (response.responseCode === 200) {
        const result = JSON.parse(response.result as string) as Record<string, Object>;
        const choices = result['choices'] as Array<Record<string, Object>>;
        if (choices && choices.length > 0) {
          const messageObj = choices[0]['message'] as Record<string, Object>;
          fullContent = messageObj['content'] as string;
          onChunk(fullContent);
        }
      } else {
        const errorBody = response.result as string;
        Logger.error(`AI API error: ${response.responseCode}, body: ${errorBody}`);
        throw new Error(`AI API request failed with code ${response.responseCode}`);
      }
    } catch (error) {
      if (this.isCancelled) {
        return '';
      }
      const errMsg = error instanceof Error ? error.message : 'Unknown error';
      Logger.error(`AI Service error: ${errMsg}`);
      throw new Error(errMsg);
    } finally {
      request.destroy();
      this.httpRequest = null;
    }

    return fullContent;
  }

  cancelRequest(): void {
    this.isCancelled = true;
    if (this.httpRequest) {
      try {
        this.httpRequest.destroy();
      } catch (e) {
        // ignore
      }
      this.httpRequest = null;
    }
  }
}

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
import { util } from '@kit.ArkTS';
import { AiConstants } from '../utils/AiConstants';
import { AiMessage, AiApiRequest, AiToolCall, AiResponseResult, ApiToolSchema } from '../viewmodel/ChatModels';
import { Logger } from '@safe/basic';

const RESPONSE_CODE_OK = 200;

export class AiService {
  private isCancelled: boolean = false;
  private httpRequest: http.HttpRequest | null = null;
  /** Carries the tail of a split SSE line across dataReceive callbacks. */
  private sseBuffer: string = '';

  /**
   * Non-streaming chat completion. Returns the final assistant content and,
   * when the model requested tool invocations, the parsed tool calls.
   */
  async chat(
    messages: AiMessage[],
    tools?: ApiToolSchema[],
    maxTokens: number = 4096,
  ): Promise<AiResponseResult> {
    const result = new AiResponseResult();
    const body = this.buildRequestBody(messages, false);
    body.max_tokens = maxTokens;
    if (tools && tools.length > 0) {
      body.tools = tools;
    }

    const response = await this.doRequest(body);
    if (response.responseCode === RESPONSE_CODE_OK) {
      const parsed = JSON.parse(response.result as string) as Record<string, Object>;
      const choices = parsed['choices'] as Array<Record<string, Object>>;
      if (choices && choices.length > 0) {
        const messageObj = choices[0]['message'] as Record<string, Object>;
        result.content = (messageObj['content'] as string) || '';
        const rawCalls = messageObj['tool_calls'] as Array<Record<string, Object>>;
        if (rawCalls) {
          result.toolCalls = this.parseToolCalls(rawCalls);
        }
      }
      Logger.info(`[AiService] chat: ${result.toolCalls.length} tool calls, ${result.content.length} content chars`);
    } else {
      this.throwApiError(response);
    }
    return result;
  }

  /**
   * Streaming chat completion over SSE. Deltas are pushed through onChunk as
   * soon as they arrive via the dataReceive event. On platforms where that
   * event never fires (the response is only available through the resolved
   * promise), the whole SSE body is parsed after the request completes, so
   * no content is ever lost. Does NOT accumulate tool calls.
   */
  async chatStream(
    messages: AiMessage[],
    onChunk: (chunk: string) => void,
  ): Promise<number> {
    const body = this.buildRequestBody(messages, true);
    const request = this.createRequest();
    this.sseBuffer = '';
    let charCount = 0;
    let receivedViaEvent = false;

    request.on('dataReceive', (data: ArrayBuffer) => {
      if (this.isCancelled) {
        return;
      }
      receivedViaEvent = true;
      const text = this.decodeChunk(data);
      this.handleSseChunk(text, (chunk: string) => {
        charCount += chunk.length;
        onChunk(chunk);
      });
    });

    try {
      const response = await request.request(
        AiConstants.AI_API_URL,
        {
          method: http.RequestMethod.POST,
          header: this.buildHeaders(),
          extraData: JSON.stringify(body),
          expectDataType: http.HttpDataType.STRING,
          connectTimeout: AiConstants.REQUEST_TIMEOUT,
          readTimeout: AiConstants.REQUEST_TIMEOUT,
        },
      );
      if (this.isCancelled) {
        return charCount;
      }
      if (response.responseCode !== RESPONSE_CODE_OK) {
        this.throwApiError(response);
      }

      // Some HarmonyOS http configurations never fire dataReceive; in that
      // case the full SSE body arrives via the promise result. Parse it
      // through the same handler instead of losing the answer.
      if (!receivedViaEvent) {
        const bodyText = response.result as string;
        if (bodyText && bodyText.length > 0) {
          this.handleSseChunk(bodyText, (chunk: string) => {
            charCount += chunk.length;
            onChunk(chunk);
          });
        }
        if (this.sseBuffer.trim().length > 0) {
          const tail = this.sseBuffer;
          this.sseBuffer = '';
          this.handleSseChunk(tail + '\n', (chunk: string) => {
            charCount += chunk.length;
            onChunk(chunk);
          });
        }
      }
      Logger.info(`[AiService] stream done: ${charCount} chars (event=${receivedViaEvent})`);
    } catch (error) {
      if (this.isCancelled) {
        return charCount;
      }
      const errMsg = error instanceof Error ? error.message : 'Unknown error';
      Logger.error(`AI stream error: ${errMsg}`);
      throw new Error(errMsg);
    } finally {
      request.off('dataReceive');
      request.destroy();
      this.httpRequest = null;
    }
    return charCount;
  }

  /**
   * Delivers a reply to onChunk, preferring SSE streaming and falling back
   * to a plain non-streaming call when streaming fails or yields nothing.
   * Returns the number of characters delivered.
   */
  async chatWithFallback(
    messages: AiMessage[],
    onChunk: (chunk: string) => void,
  ): Promise<number> {
    let streamedChars = 0;
    try {
      streamedChars = await this.chatStream(messages, onChunk);
    } catch (err) {
      Logger.error(`[AiService] stream failed, falling back to non-streaming: ${err}`);
    }
    if (streamedChars > 0) {
      return streamedChars;
    }
    const plain = await this.chat(messages);
    if (plain.content.length > 0) {
      onChunk(plain.content);
      return plain.content.length;
    }
    return 0;
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

  /** Returns true if a request is currently in flight. */
  isBusy(): boolean {
    return this.httpRequest !== null;
  }

  private buildRequestBody(messages: AiMessage[], stream: boolean): AiApiRequest {
    const body = new AiApiRequest(AiConstants.AI_MODEL, messages, stream);
    body.temperature = 0.7;
    body.max_tokens = 4096;
    return body;
  }

  private buildHeaders(): Record<string, string> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${AiConstants.API_KEY}`,
    };
    return headers;
  }

  private createRequest(): http.HttpRequest {
    this.isCancelled = false;
    const request = http.createHttp();
    this.httpRequest = request;
    return request;
  }

  private async doRequest(body: AiApiRequest): Promise<http.HttpResponse> {
    const request = this.createRequest();
    try {
      const response = await request.request(
        AiConstants.AI_API_URL,
        {
          method: http.RequestMethod.POST,
          header: this.buildHeaders(),
          extraData: JSON.stringify(body),
          expectDataType: http.HttpDataType.STRING,
          connectTimeout: AiConstants.REQUEST_TIMEOUT,
          readTimeout: AiConstants.REQUEST_TIMEOUT,
        },
      );
      if (this.isCancelled) {
        throw new Error('Request cancelled');
      }
      return response;
    } catch (error) {
      if (this.isCancelled) {
        throw new Error('Request cancelled');
      }
      const errMsg = error instanceof Error ? error.message : 'Unknown error';
      Logger.error(`AI Service error: ${errMsg}`);
      throw new Error(errMsg);
    } finally {
      request.destroy();
      this.httpRequest = null;
    }
  }

  private throwApiError(response: http.HttpResponse): void {
    const errorBody = response.result as string;
    Logger.error(`AI API error: ${response.responseCode}, body: ${errorBody}`);
    throw new Error(`AI API request failed with code ${response.responseCode}`);
  }

  private parseToolCalls(rawCalls: Array<Record<string, Object>>): AiToolCall[] {
    const calls: AiToolCall[] = [];
    for (const raw of rawCalls) {
      const call = new AiToolCall();
      call.id = (raw['id'] as string) || '';
      call.type = (raw['type'] as string) || 'function';
      const fn = raw['function'] as Record<string, Object>;
      if (fn) {
        call.function.name = (fn['name'] as string) || '';
        call.function.arguments = (fn['arguments'] as string) || '{}';
      }
      calls.push(call);
    }
    return calls;
  }

  /**
   * Feeds raw SSE text into a line buffer and parses only complete
   * `data:` lines, so payloads split across dataReceive callbacks are
   * reassembled correctly.
   */
  private handleSseChunk(buffer: string, onChunk: (chunk: string) => void): void {
    this.sseBuffer += buffer;
    const lines = this.sseBuffer.split('\n');
    // The last element is either an incomplete line or an empty tail.
    this.sseBuffer = lines.length > 0 ? lines[lines.length - 1] : '';

    for (let i = 0; i < lines.length - 1; i++) {
      const trimmed = lines[i].trim();
      if (trimmed.length === 0 || !trimmed.startsWith('data:')) {
        continue;
      }
      const payload = trimmed.substring(5).trim();
      if (payload === '[DONE]') {
        this.sseBuffer = '';
        return;
      }
      try {
        const parsed = JSON.parse(payload) as Record<string, Object>;
        const choices = parsed['choices'] as Array<Record<string, Object>>;
        if (!choices || choices.length === 0) {
          continue;
        }
        const delta = choices[0]['delta'] as Record<string, Object>;
        if (!delta) {
          continue;
        }
        const content = delta['content'] as string;
        if (content) {
          onChunk(content);
        }
      } catch (e) {
        // Non-data payloads are skipped silently.
      }
    }
  }

  private decodeChunk(data: ArrayBuffer): string {
    const decoder = util.TextDecoder.create('utf-8');
    return decoder.decodeToString(new Uint8Array(data));
  }
}

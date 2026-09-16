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
import { ApiKeyStore } from './ApiKeyStore';
import { AiMessage, AiApiRequest, AiToolCall, AiResponseResult, ApiToolSchema } from '../viewmodel/ChatModels';
import { Logger } from '@safe/basic';

const RESPONSE_CODE_OK = 200;
/** How long to wait for the first dataReceive event before giving up on true streaming. */
const STREAM_EVENT_TIMEOUT_MS = 15000;
/** Base backoff between retry attempts (attempt * base ms). */
const RETRY_BASE_DELAY_MS = 600;

/** Thrown when no API key has been configured at runtime; message is user-facing. */
export class ApiKeyMissingError extends Error {
  constructor() {
    super('尚未配置 API Key。请点击聊天页右上角 ⚙️，填写 API Key 后重试。');
  }
}

/** Outcome of a tier-1 (requestInStream) streaming attempt. */
class StreamOutcome {
  chars: number;
  /** True when the watchdog killed the request because no event ever arrived. */
  watchdogFired: boolean;

  constructor(chars: number, watchdogFired: boolean) {
    this.chars = chars;
    this.watchdogFired = watchdogFired;
  }
}

export class AiService {
  /**
   * True once the device has proven it never fires dataReceive via
   * requestInStream; tier 1 is then skipped for the rest of the app run.
   */
  private static streamEventsBroken: boolean = false;
  private isCancelled: boolean = false;
  private httpRequest: http.HttpRequest | null = null;
  private keyStore: ApiKeyStore = new ApiKeyStore();
  /** Carries the tail of a split SSE line across dataReceive callbacks. */
  private sseBuffer: string = '';
  /** Watchdog duration, overridable for tests. */
  private streamEventTimeoutMs: number;
  /** Retry backoff base, overridable for tests. */
  private retryBaseDelayMs: number;

  constructor(streamEventTimeoutMs: number = STREAM_EVENT_TIMEOUT_MS, retryBaseDelayMs: number = RETRY_BASE_DELAY_MS) {
    this.streamEventTimeoutMs = streamEventTimeoutMs;
    this.retryBaseDelayMs = retryBaseDelayMs;
  }

  /** Fails fast with a friendly error when the user has not configured a key. */
  private ensureKeyConfigured(): void {
    if (!this.keyStore.isConfigured()) {
      throw new ApiKeyMissingError();
    }
  }

  /**
   * Non-streaming chat completion. Returns the final assistant content and,
   * when the model requested tool invocations, the parsed tool calls.
   */
  async chat(
    messages: AiMessage[],
    tools?: ApiToolSchema[],
    maxTokens: number = 4096,
  ): Promise<AiResponseResult> {
    this.ensureKeyConfigured();
    const result = new AiResponseResult();
    const body = this.buildPlainRequestBody(messages);
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
   * Streaming chat completion. Tier 1 tries requestInStream for true
   * token-by-token delivery; when the device never fires dataReceive events
   * (watchdog), it falls back to tier 2, which parses the whole SSE body
   * from the buffered response. chatWithFallback adds a third,
   * non-streaming tier. Does NOT accumulate tool calls.
   */
  async chatStream(
    messages: AiMessage[],
    onChunk: (chunk: string) => void,
  ): Promise<number> {
    this.ensureKeyConfigured();
    if (!AiService.streamEventsBroken) {
      const outcome = await this.streamViaRequestInStream(messages, onChunk);
      if (this.isCancelled) {
        return 0;
      }
      if (outcome.chars > 0) {
        return outcome.chars;
      }
      if (outcome.watchdogFired) {
        // The device never fired dataReceive — remember it so tier 1 is
        // skipped for the rest of this app run instead of stalling again.
        AiService.streamEventsBroken = true;
        Logger.info('[AiService] requestInStream fired no events; using buffered stream from now on');
      }
    }
    return await this.streamViaBufferedRequest(messages, onChunk);
  }

  /** Tier 1: true streaming via requestInStream + dataReceive events. */
  private async streamViaRequestInStream(
    messages: AiMessage[],
    onChunk: (chunk: string) => void,
  ): Promise<StreamOutcome> {
    const body = this.buildStreamRequestBody(messages);
    const request = this.createRequest();
    this.sseBuffer = '';
    let charCount = 0;
    let watchdogFired = false;
    let settled = false;
    let watchdog: number = -1;
    let cancelPoll: number = -1;

    const done = new Promise<void>((resolve) => {
      request.on('dataReceive', (data: ArrayBuffer) => {
        if (this.isCancelled || settled) {
          return;
        }
        const text = this.decodeChunk(data);
        this.handleSseChunk(text, (chunk: string) => {
          charCount += chunk.length;
          onChunk(chunk);
        });
      });
      request.on('dataEnd', () => {
        if (settled) {
          return;
        }
        settled = true;
        resolve();
      });
      // Some devices never fire dataReceive. Give up after the watchdog and
      // let the caller fall back to the buffered tier instead of hanging.
      watchdog = setTimeout(() => {
        if (!settled) {
          settled = true;
          watchdogFired = true;
          try {
            request.destroy();
          } catch (e) {
            // ignore
          }
          resolve();
        }
      }, this.streamEventTimeoutMs);
    });

    // Resolves promptly when the user cancels, so a destroyed request never
    // lingers until the watchdog fires.
    const cancelled = new Promise<void>((resolve) => {
      cancelPoll = setInterval(() => {
        if (this.isCancelled) {
          resolve();
        }
      }, 100);
    });

    try {
      const responseCode = await request.requestInStream(
        AiConstants.AI_API_URL,
        {
          method: http.RequestMethod.POST,
          header: this.buildHeaders(),
          extraData: JSON.stringify(body),
          connectTimeout: AiConstants.REQUEST_TIMEOUT,
          readTimeout: AiConstants.REQUEST_TIMEOUT,
        },
      );
      if (this.isCancelled) {
        return new StreamOutcome(0, false);
      }
      if (responseCode !== RESPONSE_CODE_OK) {
        throw new Error(`AI API request failed with code ${responseCode}`);
      }

      await Promise.race([done, cancelled]);
      if (this.isCancelled) {
        return new StreamOutcome(0, false);
      }

      // Flush any tail left in the line buffer.
      if (this.sseBuffer.trim().length > 0) {
        const tail = this.sseBuffer;
        this.sseBuffer = '';
        this.handleSseChunk(tail + '\n', (chunk: string) => {
          charCount += chunk.length;
          onChunk(chunk);
        });
      }
      Logger.info(`[AiService] stream done: ${charCount} chars (event=true)`);
      return new StreamOutcome(charCount, watchdogFired);
    } catch (error) {
      if (this.isCancelled) {
        return new StreamOutcome(0, false);
      }
      const errMsg = error instanceof Error ? error.message : 'Unknown error';
      Logger.error(`AI stream error: ${errMsg}`);
      throw new Error(errMsg);
    } finally {
      if (watchdog >= 0) {
        clearTimeout(watchdog);
      }
      if (cancelPoll >= 0) {
        clearInterval(cancelPoll);
      }
      request.off('dataReceive');
      request.off('dataEnd');
      request.destroy();
      this.httpRequest = null;
    }
  }

  /**
   * Tier 2: buffered request. The dataReceive event may still fire on some
   * devices; when it never does, the full SSE body is parsed from the
   * resolved response instead of being lost.
   */
  private async streamViaBufferedRequest(
    messages: AiMessage[],
    onChunk: (chunk: string) => void,
  ): Promise<number> {
    const body = this.buildStreamRequestBody(messages);
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
    if (this.isCancelled) {
      // The user pressed stop: never fire a fresh request as a "fallback".
      return 0;
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

  /** Stream request body — the SSE path always sends stream=true. */
  private buildStreamRequestBody(messages: AiMessage[]): AiApiRequest {
    const body = new AiApiRequest(AiConstants.AI_MODEL, messages, true);
    body.temperature = 0.7;
    body.max_tokens = 4096;
    return body;
  }

  /** Plain request body for the non-streaming path. */
  private buildPlainRequestBody(messages: AiMessage[]): AiApiRequest {
    const body = new AiApiRequest(AiConstants.AI_MODEL, messages, false);
    body.temperature = 0.7;
    body.max_tokens = 4096;
    return body;
  }

  private buildHeaders(): Record<string, string> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${this.keyStore.getKey()}`,
    };
    return headers;
  }

  private createRequest(): http.HttpRequest {
    this.isCancelled = false;
    const request = http.createHttp();
    this.httpRequest = request;
    return request;
  }

  /**
   * Non-streaming request with retries (MAX_RETRY_COUNT attempts, linear
   * backoff). Cancellation aborts immediately — no retry, no new request.
   */
  private async doRequest(body: AiApiRequest): Promise<http.HttpResponse> {
    let lastError: Error = new Error('AI Service error');
    for (let attempt = 0; attempt <= AiConstants.MAX_RETRY_COUNT; attempt++) {
      if (this.isCancelled) {
        throw new Error('Request cancelled');
      }
      if (attempt > 0) {
        await this.sleep(this.retryBaseDelayMs * attempt);
      }
      if (this.isCancelled) {
        throw new Error('Request cancelled');
      }

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
        if (response.responseCode === RESPONSE_CODE_OK) {
          return response;
        }
        // A transport-level answer is not retried; surface it immediately.
        throw new Error(`AI API request failed with code ${response.responseCode}`);
      } catch (error) {
        if (this.isCancelled) {
          throw new Error('Request cancelled');
        }
        const errMsg = error instanceof Error ? error.message : 'Unknown error';
        lastError = new Error(errMsg);
        Logger.error(`AI Service error (attempt ${attempt + 1}/${AiConstants.MAX_RETRY_COUNT + 1}): ${errMsg}`);
      } finally {
        request.destroy();
        this.httpRequest = null;
      }
    }
    throw lastError;
  }

  private async sleep(ms: number): Promise<void> {
    await new Promise<void>((resolve) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
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

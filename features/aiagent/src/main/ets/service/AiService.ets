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
import { AiBackend, BackendProbeResult, describeBackendProbe, PROBE_NOT_CONFIGURED, PROBE_TOKEN_NOT_RUN } from './AiBackend';
import { AiMessage, AiApiRequest, AiToolCall, AiResponseResult, ApiToolSchema } from '../viewmodel/ChatModels';
import { Logger } from '@safe/basic';

const RESPONSE_CODE_OK = 200;
/** How long to wait for the first dataReceive event before giving up on true streaming. */
const STREAM_EVENT_TIMEOUT_MS = 15000;
/** Base backoff between retry attempts (attempt * base ms). */
const RETRY_BASE_DELAY_MS = 600;
/**
 * Timeout for the settings-sheet probe. Much shorter than a chat request: the
 * whole point is to answer "is this reachable" quickly, not to wait as long as
 * a real answer might take.
 */
const PROBE_TIMEOUT_MS = 8000;

/** Thrown when no API key has been configured at runtime; message is user-facing. */
export class ApiKeyMissingError extends Error {
  constructor() {
    super('尚未配置 API Key。请点击聊天页右上角 ⚙️，填写 API Key 后重试。');
  }
}

/**
 * A non-200 answer from whichever endpoint was called.
 *
 * The status is kept as a field instead of being baked into the text because
 * one answer needs two different readings: the learner needs a sentence they
 * can act on, and the log needs the number. Gluing them together is what put
 * the string `AI API request failed with code 402` in front of a student, who
 * could only respond by asking a human what it meant.
 *
 * The same wording covers both modes on purpose — with a backend configured the
 * rejection comes from the team's server, without one it comes straight from the
 * vendor, but the learner's situation is identical either way.
 */
export class ApiHttpError extends Error {
  code: number;

  constructor(code: number) {
    super(friendlyApiMessage(code));
    this.code = code;
  }
}

/**
 * Statuses a second attempt could plausibly answer differently.
 *
 * Everything else is a statement about the request or the account, and asking
 * again only spends the caller's time to receive the same refusal. That is not
 * hypothetical: the retry loop used to re-send a 402 four times over 3.6
 * seconds, which is the opposite of what DeepSeek's own troubleshooting page
 * says to do with it.
 */
export function isRetryableStatus(code: number): boolean {
  if (code === 408 || code === 429) {
    return true;
  }
  return code >= 500;
}

/** The sentence a learner sees. Never a bare status code. */
export function friendlyApiMessage(code: number): string {
  if (code === 0) {
    return '网络连接失败，请检查网络后重试。';
  }
  if (code === 400) {
    return '请求格式有误，请换一种问法再试。';
  }
  if (code === 401 || code === 403) {
    return '鉴权失败：API Key 或后端应用令牌无效。请点击聊天页右上角 ⚙️ 检查配置。';
  }
  if (code === 402) {
    return 'AI 服务账户余额不足，请联系管理员充值后再试。';
  }
  if (code === 404) {
    return '接口地址不存在，请检查后端地址或 API 地址是否填写正确。';
  }
  if (code === 408) {
    return 'AI 服务响应超时，请稍后再试。';
  }
  if (code === 429) {
    return '请求过于频繁，请稍等一会儿再试。';
  }
  if (code >= 500) {
    return 'AI 服务暂时不可用，请稍后再试。';
  }
  return `AI 服务返回了错误（${code}），请稍后再试。`;
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
  /**
   * Decides which endpoint is called and which credential goes with it.
   *
   * Resolved per request rather than once per instance, unless a caller
   * injected one explicitly. This mirrors how the direct-mode key already
   * behaves — ApiKeyStore reads storage on every `getKey()` — and it matters
   * for the same reason: a learner who switches modes in the settings sheet
   * should not have to leave the chat page and come back before the switch
   * takes effect.
   */
  private injectedBackend: AiBackend | null = null;
  /** Carries the tail of a split SSE line across dataReceive callbacks. */
  private sseBuffer: string = '';
  /** Watchdog duration, overridable for tests. */
  private streamEventTimeoutMs: number;
  /** Retry backoff base, overridable for tests. */
  private retryBaseDelayMs: number;

  constructor(
    streamEventTimeoutMs: number = STREAM_EVENT_TIMEOUT_MS,
    retryBaseDelayMs: number = RETRY_BASE_DELAY_MS,
    backend: AiBackend | null = null,
  ) {
    this.streamEventTimeoutMs = streamEventTimeoutMs;
    this.retryBaseDelayMs = retryBaseDelayMs;
    this.injectedBackend = backend;
  }

  /**
   * The backend in force right now: the injected one when a caller supplied it
   * (tests, and any caller that wants to pin a mode), otherwise whatever is
   * currently configured.
   */
  private currentBackend(): AiBackend {
    if (this.injectedBackend !== null) {
      return this.injectedBackend;
    }
    return AiBackend.current();
  }

  /**
   * Where this call goes.
   *
   * With a backend configured the app never contacts a vendor, so a shipped
   * build contains no vendor endpoint at all and changing model or provider
   * becomes a server-side change. Without one it falls back to the direct
   * endpoint the app has always used.
   */
  private requestUrl(): string {
    const backend = this.currentBackend();
    return backend.isConfigured() ? backend.chatUrl() : AiConstants.AI_API_URL;
  }

  /** Which mode this instance runs in; for diagnostics and tests. */
  getMode(): string {
    return this.currentBackend().mode();
  }

  /**
   * Fails fast with a friendly error when the app has no way to authenticate.
   *
   * In backend mode there is nothing for the user to configure here: the keys
   * live on the server and the app's own session token is optional, so a missing
   * key is not a failure. Demanding one would make backend mode unusable, and
   * would be asking a learner for a vendor credential they should never need.
   */
  private ensureKeyConfigured(): void {
    if (this.currentBackend().isConfigured()) {
      return;
    }
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

    // doRequest only resolves on a 200 — every other answer has already been
    // turned into an ApiHttpError by the time it returns or throws, so there is
    // no failure branch to write here.
    const response = await this.doRequest(body);
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
        this.requestUrl(),
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
        throw new ApiHttpError(responseCode);
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
      // Re-throw the original when there is one: wrapping it in a fresh Error
      // would drop the status code the UI needs in order to explain the failure.
      if (error instanceof Error) {
        throw error;
      }
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
        this.requestUrl(),
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
        Logger.error(`AI API error: ${response.responseCode}, body: ${response.result as string}`);
        throw new ApiHttpError(response.responseCode);
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
      if (error instanceof Error) {
        throw error;
      }
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

  /**
   * Probes the configured backend so the settings sheet can say whether the
   * address and the token actually work, instead of making the user send a
   * message and read the failure.
   *
   * Two steps, because neither one answers both questions:
   *
   * 1. `GET /health` is unauthenticated, so it proves the address is right and
   *    reports what the server has configured — but says nothing about the token.
   * 2. A deliberately invalid `POST` to the chat path then separates "token
   *    rejected" (401) from "token accepted, body rejected". The server checks
   *    auth before it validates the body, so this costs nothing: no model call
   *    is made just to find out whether a token works.
   *
   * The probe deliberately does **not** touch `this.httpRequest` — it is not a
   * chat request, so it must not make the UI think something is in flight, and
   * ⏹ must not be able to cancel it.
   */
  async probeBackend(target: AiBackend | null = null): Promise<BackendProbeResult> {
    // `target` lets the settings sheet probe what the user has just typed,
    // before it is saved. Without it the probe would test the previous
    // configuration and report success for values that were never applied.
    const backend = target !== null ? target : this.currentBackend();
    if (!backend.isConfigured()) {
      // The wording lives in the pure verdict function along with every other
      // branch, so it is covered by the same offline tests.
      return describeBackendProbe(PROBE_NOT_CONFIGURED, '', PROBE_TOKEN_NOT_RUN);
    }

    let statusCode = 0;
    let bodyText = '';
    try {
      const request = http.createHttp();
      const response = await request.request(backend.healthUrl(), {
        method: http.RequestMethod.GET,
        header: this.probeHeaders(backend),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: PROBE_TIMEOUT_MS,
        readTimeout: PROBE_TIMEOUT_MS,
      });
      request.destroy();
      statusCode = response.responseCode;
      bodyText = typeof response.result === 'string' ? response.result : '';
    } catch (e) {
      // Transport failure is the common case — wrong host, nothing listening,
      // TLS refused. describeBackendProbe reads 0 as exactly that.
      statusCode = 0;
    }

    let tokenStatusCode = PROBE_TOKEN_NOT_RUN;
    if (statusCode === RESPONSE_CODE_OK && backend.hasToken()) {
      tokenStatusCode = await this.probeToken(backend);
    }
    return describeBackendProbe(statusCode, bodyText, tokenStatusCode);
  }

  /**
   * Headers for a probe, built here rather than through `buildHeaders()`.
   * That path falls back to the user's vendor key, and a probe must never be
   * able to carry a vendor credential anywhere.
   */
  private probeHeaders(backend: AiBackend): Record<string, string> {
    const headers: Record<string, string> = { 'Content-Type': 'application/json' };
    const token = backend.getToken();
    if (token.length > 0) {
      headers['Authorization'] = `Bearer ${token}`;
    }
    return headers;
  }

  /** Returns the status code, or 0 when the request never got an answer. */
  private async probeToken(backend: AiBackend): Promise<number> {
    try {
      const request = http.createHttp();
      const response = await request.request(backend.chatUrl(), {
        method: http.RequestMethod.POST,
        header: this.probeHeaders(backend),
        // An empty body on purpose: the server checks auth before it validates
        // the body, so 401 vs anything-else answers "is this token accepted"
        // without ever reaching the model.
        extraData: '{}',
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: PROBE_TIMEOUT_MS,
        readTimeout: PROBE_TIMEOUT_MS,
      });
      request.destroy();
      return response.responseCode;
    } catch (e) {
      return 0;
    }
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

  /**
   * The credential this request may carry — and never more than one.
   *
   * Which one is not a style choice. In backend mode the vendor key is not
   * present on the device at all, and sending it would leak a credential the
   * user never handed to this app; in direct mode the app has no backend token
   * to send. So the mode selects the header, and an absent credential means the
   * header is omitted entirely rather than sent as an empty `Bearer `.
   */
  private buildHeaders(): Record<string, string> {
    const headers: Record<string, string> = {};
    headers['Content-Type'] = 'application/json';
    const backend = this.currentBackend();
    if (backend.isConfigured()) {
      const token = backend.getToken();
      if (token.length > 0) {
        headers['Authorization'] = `Bearer ${token}`;
      }
      return headers;
    }
    const key = this.keyStore.getKey();
    if (key.length > 0) {
      headers['Authorization'] = `Bearer ${key}`;
    }
    return headers;
  }

  private createRequest(): http.HttpRequest {
    this.isCancelled = false;
    const request = http.createHttp();
    this.httpRequest = request;
    return request;
  }

  /**
   * Non-streaming request with retries.
   *
   * Only transient failures are retried — transport errors, 408/429/5xx. A 4xx
   * is a statement about the request or the account, so it ends the loop on the
   * first answer: re-sending a 402 four times over 3.6 seconds, as this loop
   * used to, only delays the explanation the user is waiting for. Cancellation
   * aborts immediately — no retry, no new request.
   */
  private async doRequest(body: AiApiRequest): Promise<http.HttpResponse> {
    // ArkTS forbids assigning a class instance to a variable typed as the
    // built-in `Error` (structural typing is not supported), so the HTTP
    // failure and the transport failure live in separate slots instead of
    // sharing one `Error`-typed variable.
    let lastFailure: ApiHttpError | null = null;
    let terminalFailure: ApiHttpError | null = null;
    let lastMessage: string = 'AI Service error';
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
          this.requestUrl(),
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
        Logger.error(`AI API error: ${response.responseCode}, body: ${response.result as string}`);
        const failure = new ApiHttpError(response.responseCode);
        if (!isRetryableStatus(response.responseCode)) {
          // Leave the loop rather than throwing from inside `try` — the catch
          // below would file this away as just another failed attempt, which is
          // exactly how a hard stop became four retries.
          terminalFailure = failure;
          break;
        }
        lastFailure = failure;
      } catch (error) {
        if (this.isCancelled) {
          throw new Error('Request cancelled');
        }
        const errMsg = error instanceof Error ? error.message : 'Unknown error';
        lastMessage = errMsg;
        lastFailure = null;
        Logger.error(`AI Service error (attempt ${attempt + 1}/${AiConstants.MAX_RETRY_COUNT + 1}): ${errMsg}`);
      } finally {
        request.destroy();
        this.httpRequest = null;
      }
    }
    if (terminalFailure !== null) {
      throw terminalFailure;
    }
    if (lastFailure !== null) {
      throw lastFailure;
    }
    throw new Error(lastMessage);
  }

  private async sleep(ms: number): Promise<void> {
    await new Promise<void>((resolve) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
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

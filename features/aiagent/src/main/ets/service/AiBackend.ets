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

import fileIo from '@ohos.file.fs';

/**
 * Base URL of the team's own AI backend, e.g. `https://ai.example.edu`.
 * When set, every model call the app makes goes here instead of to a vendor.
 */
export const BACKEND_URL_KEY = 'aiBackendUrl';
/** The app's own session token. Revocable server-side; not a vendor key. */
export const BACKEND_TOKEN_KEY = 'aiBackendToken';

export const BACKEND_EMBED_PATH = '/embed';
export const BACKEND_CHAT_PATH = '/v1/chat/completions';
/** Unauthenticated capability endpoint; used by the settings sheet's probe. */
export const BACKEND_HEALTH_PATH = '/health';

/** Talking to the team's backend; the app carries no vendor credential. */
export const MODE_BACKEND = 'backend';
/** Talking to the vendor directly with a key the user typed in. */
export const MODE_DIRECT = 'direct';

const BACKEND_FILE = '/aiBackend.txt';

/**
 * Which endpoint the app should call, and which credential it is allowed to
 * need.
 *
 * This exists because the project has two operating modes and the difference
 * is not cosmetic:
 *
 * - **backend** — the deployment of AI-SEC-001's recommendation. The vendor key
 *   lives on a server the team operates; the app holds only its own session
 *   token, which the server may require or ignore. Nothing about the vendor is
 *   baked into a shipped build, so switching model or provider is a server-side
 *   change.
 * - **direct** — the pre-existing behaviour, kept because a learner running the
 *   app without a team backend must still get an assistant. The key is typed in
 *   at runtime and never compiled in, which was the *other* half of the same
 *   recommendation.
 *
 * Both modes are first-class; neither silently falls back into the other. The
 * app must never end up sending a vendor key to the team's backend, or the
 * team's token to a vendor, so the choice is made in exactly one place — here.
 *
 * This class is a pure value object. Reading storage is confined to
 * `current()` and writing to `AiBackendStore`, so the routing rules above stay
 * testable without any app state.
 */
export class AiBackend {
  private baseUrl: string = '';
  private token: string = '';

  constructor(baseUrl: string = '', token: string = '') {
    this.baseUrl = AiBackend.normalize(baseUrl);
    this.token = typeof token === 'string' ? token.trim() : '';
  }

  /** Trailing slashes are dropped so `base + '/embed'` never doubles up. */
  static normalize(url: string): string {
    const trimmed = typeof url === 'string' ? url.trim() : '';
    if (trimmed.length === 0) {
      return '';
    }
    return trimmed.charAt(trimmed.length - 1) === '/'
      ? trimmed.substring(0, trimmed.length - 1)
      : trimmed;
  }

  /**
   * The configuration in force right now: AppStorage first, the sandbox file
   * second.
   *
   * Named `current` rather than `fromAppStorage` deliberately — the old name
   * described where the value came from, and that is precisely why nobody
   * noticed it never consulted the file. AppStorage is per-process, so after a
   * restart it is empty while the saved settings are still on disk; the app
   * then fell silently back into direct mode and demanded a vendor key the
   * learner had never entered. The settings were being written all along —
   * nothing ever read them back.
   *
   * Separate from the constructor for the same reason the embedding proxy keeps
   * it separate: storage is the one impure thing here, and the routing rules
   * should be reachable without it.
   */
  static current(): AiBackend {
    return new AiBackendStore().load();
  }

  isConfigured(): boolean {
    return this.baseUrl.length > 0;
  }

  /** MODE_BACKEND when a base URL is set, otherwise MODE_DIRECT. */
  mode(): string {
    return this.isConfigured() ? MODE_BACKEND : MODE_DIRECT;
  }

  /** True only in backend mode: the app needs no vendor key. */
  usesBackend(): boolean {
    return this.isConfigured();
  }

  getBaseUrl(): string {
    return this.baseUrl;
  }

  getToken(): string {
    return this.token;
  }

  hasToken(): boolean {
    return this.token.length > 0;
  }

  urlFor(path: string): string {
    return this.baseUrl + path;
  }

  embedUrl(): string {
    return this.urlFor(BACKEND_EMBED_PATH);
  }

  chatUrl(): string {
    return this.urlFor(BACKEND_CHAT_PATH);
  }

  healthUrl(): string {
    return this.urlFor(BACKEND_HEALTH_PATH);
  }

  /** The Authorization header value, or '' when there is nothing to send. */
  authHeader(): string {
    return this.token.length > 0 ? `Bearer ${this.token}` : '';
  }
}

/**
 * Outcome of a connectivity probe, phrased for whoever is staring at the
 * settings sheet: a short verdict plus one sentence they can act on.
 *
 * This exists because the settings sheet used to give no feedback at all — the
 * only way to find out whether the URL and token were right was to send a
 * message and read the failure, which conflates "wrong address", "wrong token"
 * and "the model refused" into one unhelpful error.
 */
export class BackendProbeResult {
  ok: boolean = false;
  title: string = '';
  detail: string = '';

  constructor(ok: boolean, title: string, detail: string) {
    this.ok = ok;
    this.title = title;
    this.detail = detail;
  }
}

/** Shape of `GET /health` as served by this project's backend. */
interface ProbeCapability {
  configured: boolean;
  model: string;
}

interface ProbeHealth {
  ok: boolean;
  authRequired: boolean;
  chat: ProbeCapability;
  embedding: ProbeCapability;
}

/** Marker meaning "the token was not probed" — no token was available to send. */
export const PROBE_TOKEN_NOT_RUN: number = -1;

/**
 * Marker meaning "there is nothing to probe": no base URL is configured, so
 * the app is in direct mode. Kept as a status code rather than a verdict built
 * by the caller so the wording stays testable alongside the others.
 */
export const PROBE_NOT_CONFIGURED: number = -2;

function parseHealth(text: string): ProbeHealth | null {
  if (typeof text !== 'string' || text.trim().length === 0) {
    return null;
  }
  try {
    const parsed = JSON.parse(text) as ProbeHealth;
    if (parsed === null) {
      return null;
    }
    return parsed;
  } catch (e) {
    return null;
  }
}

function capabilityText(name: string, capability: ProbeCapability | null): string {
  if (capability === null || capability === undefined) {
    return `${name}状态未知`;
  }
  return `${name}${capability.configured === true ? '已配置' : '未配置'}`;
}

/**
 * Turns the two probe answers into one verdict.
 *
 * Pure on purpose: every branch below is a real situation an operator hits
 * (wrong address, wrong token, missing token, backend down, a proxy swallowing
 * the request), and keeping it free of HTTP means all of them are unit-testable.
 *
 * `tokenStatusCode` contract: pass `PROBE_TOKEN_NOT_RUN` when no token was
 * available to send. Together with `authRequired === true` that means the token
 * is missing, which this reports as a failure rather than a pass.
 */
export function describeBackendProbe(
  statusCode: number,
  bodyText: string,
  tokenStatusCode: number = PROBE_TOKEN_NOT_RUN,
): BackendProbeResult {
  if (statusCode === PROBE_NOT_CONFIGURED) {
    return new BackendProbeResult(false, '当前是直连模式',
      '没有填后端地址，请求会直接发往厂商（需要自己填 API Key）。填上自有后端地址即可切换到后端模式。');
  }
  if (statusCode === 0) {
    return new BackendProbeResult(false, '连不上后端',
      '地址或网络不通，逐项检查：① 后端是否真的启动了（跑凭据体检只验证厂商密钥，不会启动服务）；'
        + '② 连局域网服务要填 http://电脑的局域网IP:端口，不能填 127.0.0.1（那在手机上指手机自己）；'
        + '③ 手机与电脑是否连同一个 Wi-Fi；'
        + '④ 连外网部署的服务则确认域名拼写正确且是 https://（自签证书可能被系统直接拒绝）；'
        + '⑤ 上次能用、这次不能？局域网 IP 会随 DHCP 变，在电脑上跑 server\\scripts\\'
        + 'manage-autostart.ps1 -Action Status，它会打印当前该填的那一行。');
  }
  if (statusCode === 200) {
    const health = parseHealth(bodyText);
    if (health === null || health.ok !== true) {
      return new BackendProbeResult(false, '地址可能填错了',
        `${BACKEND_HEALTH_PATH} 返回了 200，但不是本服务的应答。`
          + 'Base URL 只填到域名（可带反向代理的路径前缀），不要填具体接口路径。');
    }
    const parts: string[] = [];
    parts.push(health.authRequired === true ? '鉴权已开启' : '鉴权已关闭');
    parts.push(capabilityText('聊天', health.chat));
    parts.push(capabilityText('嵌入', health.embedding));
    if (tokenStatusCode === 401 || tokenStatusCode === 403) {
      return new BackendProbeResult(false, '令牌被拒',
        '地址是对的，但后端不认这个令牌。请与部署时的 APP_TOKEN 逐字核对（注意首尾空格）。');
    }
    if (health.authRequired === true && tokenStatusCode === PROBE_TOKEN_NOT_RUN) {
      return new BackendProbeResult(false, '缺少令牌',
        '后端开启了鉴权，但这里没有填令牌，对话会被拒绝。把部署时的 APP_TOKEN 填进上面的输入框。');
    }
    if (tokenStatusCode > 0) {
      parts.push('令牌已接受');
    } else if (tokenStatusCode === 0) {
      // 地址通了，但单独这次令牌探测没拿到应答（连接被中断之类）。
      // 不当失败处理：地址已经确认可用，只是令牌这一项没验成。
      parts.push('令牌状态未知');
    }
    return new BackendProbeResult(true, '连接正常', parts.join(' · '));
  }
  if (statusCode === 401 || statusCode === 403) {
    return new BackendProbeResult(false, '令牌被拒',
      '请求被拒。请与部署时的 APP_TOKEN 逐字核对（注意首尾空格）；'
        + '若前置网关也做鉴权，确认它放行了本服务。');
  }
  if (statusCode === 404) {
    return new BackendProbeResult(false, '路径不对',
      `后端没有 ${BACKEND_HEALTH_PATH}。Base URL 只填到域名，`
        + '不要带 /embed 或 /v1/chat/completions 这类接口路径。');
  }
  if (statusCode >= 500) {
    return new BackendProbeResult(false, `后端出错（${statusCode}）`,
      '进程在，但这个请求失败了。请查看服务端日志。');
  }
  return new BackendProbeResult(false, `未预期的应答（${statusCode}）`,
    '可能是反向代理或登录门户截住了这个请求。检查反代是否把 /health 也转发了。');
}

/**
 * Persists the backend settings.
 *
 * Same template as ApiKeyStore — AppStorage for the running process, a file in
 * the app sandbox so the setting survives a restart — because these two are the
 * app's only configuration and they should behave identically.
 *
 * The token is stored in plaintext inside the app sandbox, exactly as the
 * direct-mode key already is. That is a deliberate trade: the sandbox is
 * per-app, and unlike a vendor key this token is scoped to this project's own
 * server and can be rotated there at any time without shipping a new build.
 */
export class AiBackendStore {
  /**
   * AppStorage first — it is the fast path, and the same store the settings
   * sheet writes to — then the sandbox file.
   *
   * The values recovered from the file are written back into AppStorage. That
   * is not a micro-optimisation: it is what makes "restored after a restart"
   * indistinguishable from "never went away" for every later reader, including
   * the settings sheet, which prefills its inputs from the same accessor. Skip
   * it and the sheet shows blank fields for a configuration that is in force.
   */
  load(): AiBackend {
    const url = this.readSetting(BACKEND_URL_KEY);
    const token = this.readSetting(BACKEND_TOKEN_KEY);
    if (url.length > 0 || token.length > 0) {
      return new AiBackend(url, token);
    }
    const persisted = this.readFile();
    this.writeSetting(BACKEND_URL_KEY, persisted.getBaseUrl());
    this.writeSetting(BACKEND_TOKEN_KEY, persisted.getToken());
    return persisted;
  }

  save(backend: AiBackend): void {
    const url = backend.getBaseUrl();
    const token = backend.getToken();
    this.writeSetting(BACKEND_URL_KEY, url);
    this.writeSetting(BACKEND_TOKEN_KEY, token);

    const filePath = this.getFilePath();
    if (filePath === null) {
      return;
    }
    try {
      const file: fileIo.File = fileIo.openSync(filePath, 0o2 | 0o100 | 0o1000);
      fileIo.writeSync(file.fd, `${url}\n${token}`);
      fileIo.closeSync(file);
    } catch (e) {
      // Failing to persist must not interrupt the chat that follows.
    }
  }

  clear(): void {
    this.save(new AiBackend('', ''));
  }

  isConfigured(): boolean {
    return this.load().isConfigured();
  }

  /** First line is the URL, everything after it is the token. */
  parse(raw: string): AiBackend {
    const text = typeof raw === 'string' ? raw : '';
    const breakAt = text.indexOf('\n');
    if (breakAt < 0) {
      return new AiBackend(text, '');
    }
    return new AiBackend(text.substring(0, breakAt), text.substring(breakAt + 1));
  }

  private readSetting(key: string): string {
    try {
      return AppStorage.get<string>(key) || '';
    } catch (e) {
      return '';
    }
  }

  private writeSetting(key: string, value: string): void {
    try {
      AppStorage.setOrCreate(key, value);
    } catch (e) {
      // AppStorage may be unavailable; the file write still persists it.
    }
  }

  private readFile(): AiBackend {
    const filePath = this.getFilePath();
    if (filePath === null) {
      return new AiBackend('', '');
    }
    try {
      return this.parse(fileIo.readTextSync(filePath));
    } catch (e) {
      return new AiBackend('', '');
    }
  }

  private getFilePath(): string | null {
    let filesDir = '';
    try {
      filesDir = AppStorage.get<string>('filesDir') || '';
    } catch (e) {
      return null;
    }
    if (filesDir.length === 0) {
      return null;
    }
    return filesDir + BACKEND_FILE;
  }
}

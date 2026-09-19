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
 * This class is a pure value object. Reading AppStorage is confined to
 * `fromAppStorage()` and writing to `AiBackendStore`, so the routing rules
 * above stay testable without any app state.
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
   * Reads the configured backend from AppStorage.
   *
   * Separate from the constructor for the same reason the embedding proxy keeps
   * it separate: AppStorage is the one impure thing here, and the routing rules
   * should be reachable without it.
   */
  static fromAppStorage(): AiBackend {
    let url = '';
    let token = '';
    try {
      url = AppStorage.get<string>(BACKEND_URL_KEY) || '';
      token = AppStorage.get<string>(BACKEND_TOKEN_KEY) || '';
    } catch (e) {
      // AppStorage is absent in offline tests and during preview.
      url = '';
      token = '';
    }
    return new AiBackend(url, token);
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

  /** The Authorization header value, or '' when there is nothing to send. */
  authHeader(): string {
    return this.token.length > 0 ? `Bearer ${this.token}` : '';
  }
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
  load(): AiBackend {
    const url = this.readSetting(BACKEND_URL_KEY);
    const token = this.readSetting(BACKEND_TOKEN_KEY);
    if (url.length > 0 || token.length > 0) {
      return new AiBackend(url, token);
    }
    return this.readFile();
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

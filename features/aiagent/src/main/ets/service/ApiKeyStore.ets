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

const API_KEY_STORE_KEY = 'AiApiKey';
const API_KEY_FILE = '/aiApiKey.txt';

/**
 * Runtime API key storage. The key is entered by the user at runtime
 * (⚙️ on the chat page) and persisted in the app sandbox only — it is
 * never compiled into the installation package.
 */
export class ApiKeyStore {
  getKey(): string {
    let key = '';
    try {
      key = AppStorage.get<string>(API_KEY_STORE_KEY) || '';
    } catch (e) {
      // AppStorage may not be initialized during preview or unit tests.
    }

    if (key.length === 0) {
      const filePath = this.getFilePath();
      if (filePath) {
        try {
          key = fileIo.readTextSync(filePath).trim();
        } catch (e) {
          // No key configured yet.
        }
      }
    }
    return key;
  }

  saveKey(key: string): void {
    const trimmed = key.trim();
    try {
      AppStorage.setOrCreate(API_KEY_STORE_KEY, trimmed);
    } catch (e) {
      // AppStorage may not be available; the file write below still persists.
    }

    const filePath = this.getFilePath();
    if (!filePath) {
      return;
    }
    try {
      const file: fileIo.File = fileIo.openSync(filePath, 0o2 | 0o100 | 0o1000);
      fileIo.writeSync(file.fd, trimmed);
      fileIo.closeSync(file);
    } catch (e) {
      // Persist failure must not interrupt the chat.
    }
  }

  clearKey(): void {
    this.saveKey('');
  }

  isConfigured(): boolean {
    return this.getKey().length > 0;
  }

  private getFilePath(): string | null {
    const filesDir = AppStorage.get<string>('filesDir');
    if (!filesDir) {
      return null;
    }
    return filesDir + API_KEY_FILE;
  }
}

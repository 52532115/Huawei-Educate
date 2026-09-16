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
import { Logger } from '@safe/basic';

const TRACE_FILE = '/agentTrace.log';
/** Once the log exceeds this size it is truncated on the next write. */
const MAX_TRACE_FILE_BYTES = 256 * 1024;

/**
 * Appends one line per agent event (tool name / duration / round) to a local
 * file so agent runs can be debugged on-device without extra API calls.
 * Failures are swallowed: tracing must never break the chat.
 */
export class AgentTraceLogger {
  log(line: string): void {
    const filePath = this.getTraceFilePath();
    if (!filePath) {
      return;
    }
    try {
      const file: fileIo.File = this.openTraceFile(filePath);
      fileIo.writeSync(file.fd, `[${this.formatNow()}] ${line}\n`);
      fileIo.closeSync(file);
    } catch (e) {
      Logger.error(`[AgentTrace] write failed: ${e instanceof Error ? e.message : 'Unknown error'}`);
    }
  }

  /** Opens for append, truncating first when the file has grown too large. */
  private openTraceFile(filePath: string): fileIo.File {
    try {
      const stat = fileIo.statSync(filePath);
      if (stat.size > MAX_TRACE_FILE_BYTES) {
        return fileIo.openSync(filePath, 0o2 | 0o100 | 0o1000); // create + truncate
      }
    } catch (e) {
      // First write: the file does not exist yet.
    }
    return fileIo.openSync(filePath, 0o2 | 0o100 | 0o2000); // create + append
  }

  private formatNow(): string {
    const date = new Date();
    const month = (date.getMonth() + 1).toString().padStart(2, '0');
    const day = date.getDate().toString().padStart(2, '0');
    const hours = date.getHours().toString().padStart(2, '0');
    const minutes = date.getMinutes().toString().padStart(2, '0');
    const seconds = date.getSeconds().toString().padStart(2, '0');
    return `${date.getFullYear()}-${month}-${day} ${hours}:${minutes}:${seconds}`;
  }

  private getTraceFilePath(): string | null {
    const filesDir = AppStorage.get<string>('filesDir');
    if (!filesDir) {
      return null;
    }
    return filesDir + TRACE_FILE;
  }
}

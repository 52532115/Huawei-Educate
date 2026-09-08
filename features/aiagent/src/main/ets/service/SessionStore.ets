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
import {
  ChatMessage,
  ChatSession,
  MessageRole,
  MessageStatus,
} from '../viewmodel/ChatModels';
import { Logger } from '@safe/basic';

const SESSION_STORE_KEY = 'AiChatSessions';
const SESSION_FILE = '/aiChatSessions.json';
const MAX_PERSISTED_SESSIONS = 20;

interface PersistedMessageRecord {
  id: string;
  role: string;
  content: string;
  timestamp: number;
  status: string;
  /** UI action hint (e.g. 'start_practice') so the tap-through survives restarts. */
  action?: string;
}

interface PersistedSessionRecord {
  id: string;
  title: string;
  messages: PersistedMessageRecord[];
  createTime: number;
  updateTime: number;
}

/**
 * Persists AI tutor chat sessions to the app files directory, following the
 * same AppStorage + JSON file pattern used by the error book.
 */
export class SessionStore {
  saveSessions(sessions: ChatSession[]): void {
    const trimmed = sessions.slice(0, MAX_PERSISTED_SESSIONS);
    const records: PersistedSessionRecord[] = [];
    for (const session of trimmed) {
      records.push(this.sessionToRecord(session));
    }
    const json = JSON.stringify(records);
    AppStorage.setOrCreate(SESSION_STORE_KEY, json);

    const filePath = this.getSessionFilePath();
    if (!filePath) {
      return;
    }
    try {
      const file: fileIo.File = fileIo.openSync(filePath, 0o2 | 0o100 | 0o1000);
      fileIo.writeSync(file.fd, json);
      fileIo.closeSync(file);
    } catch (e) {
      // Persist failure must not interrupt the chat.
    }
  }

  loadSessions(): ChatSession[] {
    let json = '';
    try {
      json = AppStorage.get<string>(SESSION_STORE_KEY) || '';
    } catch (e) {
      // AppStorage may not be initialized during preview or unit tests.
    }

    if (json.length === 0) {
      const filePath = this.getSessionFilePath();
      if (filePath) {
        try {
          json = fileIo.readTextSync(filePath);
        } catch (e) {
          // No persisted sessions yet.
        }
      }
    }

    if (json.length === 0) {
      return [];
    }

    try {
      const parsed = JSON.parse(json) as PersistedSessionRecord[];
      const sessions: ChatSession[] = [];
      for (const record of parsed) {
        const session = this.recordToSession(record);
        if (session) {
          sessions.push(session);
        }
      }
      return sessions;
    } catch (e) {
      Logger.error(`Failed to parse persisted sessions: ${json.length}`);
      return [];
    }
  }

  private sessionToRecord(session: ChatSession): PersistedSessionRecord {
    const messages: PersistedMessageRecord[] = [];
    for (const message of session.messages) {
      if (message.role === MessageRole.STEP) {
        // Transient progress messages are not part of the conversation.
        continue;
      }
      const msg: PersistedMessageRecord = {
        id: message.id,
        role: message.role,
        content: message.content,
        timestamp: message.timestamp,
        status: message.status,
        action: message.action,
      };
      messages.push(msg);
    }
    const record: PersistedSessionRecord = {
      id: session.id,
      title: session.title,
      messages: messages,
      createTime: session.createTime,
      updateTime: session.updateTime,
    };
    return record;
  }

  private recordToSession(record: PersistedSessionRecord): ChatSession | null {
    const id = record.id;
    const title = record.title;
    if (!id || !title) {
      return null;
    }
    const session = new ChatSession(id, title);
    session.createTime = record.createTime || session.createTime;
    session.updateTime = record.updateTime || session.updateTime;

    for (const raw of record.messages) {
      const content = raw.content;
      if (!content) {
        continue;
      }
      const message = new ChatMessage(
        raw.id || `msg_${Date.now()}_${Math.random().toString(36).substring(2, 8)}`,
        this.parseRole(raw.role),
        content,
        this.parseStatus(raw.status),
      );
      message.timestamp = raw.timestamp || message.timestamp;
      if (raw.action) {
        message.action = raw.action;
      }
      session.messages = [...session.messages, message];
    }
    return session;
  }

  /** Converts a persisted role string back to a MessageRole, defaulting to AI. */
  private parseRole(rawRole: string): MessageRole {
    switch (rawRole) {
      case MessageRole.USER:
        return MessageRole.USER;
      case MessageRole.ANALYSIS:
        return MessageRole.ANALYSIS;
      case MessageRole.AI:
        return MessageRole.AI;
      default:
        return MessageRole.AI;
    }
  }

  /** Converts a persisted status string back to a MessageStatus, defaulting to SUCCESS. */
  private parseStatus(rawStatus: string): MessageStatus {
    if (rawStatus === MessageStatus.FAILED) {
      return MessageStatus.FAILED;
    }
    if (rawStatus === MessageStatus.SENDING) {
      return MessageStatus.SUCCESS;
    }
    return MessageStatus.SUCCESS;
  }

  private getSessionFilePath(): string | null {
    const filesDir = AppStorage.get<string>('filesDir');
    if (!filesDir) {
      return null;
    }
    return filesDir + SESSION_FILE;
  }
}

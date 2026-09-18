/*
 * Copyright (c) 2025 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 */

import fileIo from '@ohos.file.fs';
import { KnowledgeSnapshot } from '../viewmodel/KnowledgeModels';
import { decodeSnapshot, encodeSnapshot } from './KnowledgeSnapshotCodec';

/** One file, next to the other `filesDir` payloads (errorBook.json, …). */
const SNAPSHOT_FILE = '/knowledgeIndex.json';
/** Directory holding every per-app data file, published by the app entry. */
const FILES_DIR_KEY = 'filesDir';

/**
 * Reads and writes the retrieval snapshot. This is the only RAG file that
 * touches the file system — the chunker, the index, the snapshot codec and the
 * retriever all stay pure, which is what keeps them testable offline.
 *
 * **The snapshot never goes into AppStorage.** AppStorage is an in-memory value
 * store shared by the whole app (this project already keeps its sessions, error
 * book and course progress there); parking a few hundred KB of postings and
 * embeddings in it would pay the copy cost on every read and grow the app's
 * resident memory for data that is only read once per launch. The file is the
 * cache; memory holds one decoded copy inside the `KnowledgeStore` singleton.
 *
 * Every failure is non-fatal by design: an unreadable or stale snapshot means
 * "rebuild from the corpus", which costs milliseconds and is always correct.
 */
export class KnowledgeIndexStore {
  /** The path is resolved per call so a late `filesDir` still works. */
  snapshotPath(): string | null {
    let filesDir = '';
    try {
      filesDir = AppStorage.get<string>(FILES_DIR_KEY) || '';
    } catch (e) {
      // AppStorage is absent in unit tests and during preview.
      return null;
    }
    if (filesDir.length === 0) {
      return null;
    }
    return filesDir + SNAPSHOT_FILE;
  }

  /** True when the cache can be used at all — i.e. the app has a data dir. */
  isEnabled(): boolean {
    return this.snapshotPath() !== null;
  }

  /**
   * Returns the snapshot only when it provably belongs to the corpus and the
   * index implementation currently in memory. A fingerprint from a different
   * corpus, or a signature from different tokenizing code, reads as "no cache".
   */
  load(expectedFingerprint: string, expectedSignature: string): KnowledgeSnapshot | null {
    const path = this.snapshotPath();
    if (path === null) {
      return null;
    }
    let json = '';
    try {
      json = fileIo.readTextSync(path);
    } catch (e) {
      // First launch, or the file was cleared.
      return null;
    }
    const snapshot = decodeSnapshot(json);
    if (snapshot === null) {
      return null;
    }
    if (snapshot.fingerprint !== expectedFingerprint ||
      snapshot.signature !== expectedSignature) {
      return null;
    }
    return snapshot;
  }

  /** Best-effort write. Returns false when nothing was persisted. */
  save(snapshot: KnowledgeSnapshot): boolean {
    const path = this.snapshotPath();
    if (path === null) {
      return false;
    }
    const json = encodeSnapshot(snapshot);
    try {
      const file: fileIo.File = fileIo.openSync(path, 0o2 | 0o100 | 0o1000);
      fileIo.writeSync(file.fd, json);
      fileIo.closeSync(file);
      return true;
    } catch (e) {
      // A cache that cannot be written is a slow launch, never a broken one.
      return false;
    }
  }

  /** Drops the cache so the next launch rebuilds it. */
  clear(): void {
    const path = this.snapshotPath();
    if (path === null) {
      return;
    }
    try {
      fileIo.unlinkSync(path);
    } catch (e) {
      // Nothing cached; nothing to do.
    }
  }
}

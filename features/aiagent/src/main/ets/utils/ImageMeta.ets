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

export class ImageFileMeta {
  extension: string;
  mime: string;

  constructor(extension: string, mime: string) {
    this.extension = extension;
    this.mime = mime;
  }
}

/**
 * Detects the real image format from magic bytes so the upload keeps the
 * original type instead of always declaring JPEG.
 */
export function detectImageMeta(data: Uint8Array): ImageFileMeta {
  if (data.length >= 4 &&
    data[0] === 0x89 && data[1] === 0x50 && data[2] === 0x4E && data[3] === 0x47) {
    return new ImageFileMeta('png', 'image/png');
  }
  if (data.length >= 3 && data[0] === 0xFF && data[1] === 0xD8 && data[2] === 0xFF) {
    return new ImageFileMeta('jpg', 'image/jpeg');
  }
  if (data.length >= 6 &&
    data[0] === 0x47 && data[1] === 0x49 && data[2] === 0x46 && data[3] === 0x38 &&
    (data[4] === 0x37 || data[4] === 0x39) && data[5] === 0x61) {
    return new ImageFileMeta('gif', 'image/gif');
  }
  if (data.length >= 12 &&
    data[0] === 0x52 && data[1] === 0x49 && data[2] === 0x46 && data[3] === 0x46 &&
    data[8] === 0x57 && data[9] === 0x45 && data[10] === 0x42 && data[11] === 0x50) {
    return new ImageFileMeta('webp', 'image/webp');
  }
  return new ImageFileMeta('jpg', 'image/jpeg');
}

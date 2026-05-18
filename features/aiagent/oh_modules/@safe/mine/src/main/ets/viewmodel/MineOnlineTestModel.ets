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

export class MineOnlineTestModel {
  status: string = '';
  text: string = '';
  beginTimer: string = '';
  endTimer: string = '';
  nums: string = '';
  key: string = '';

  constructor(status: string, text: string, key: string, beginTimer: string, endTimer: string, nums: string) {
    this.status = status;
    this.text = text;
    this.beginTimer = beginTimer;
    this.endTimer = endTimer;
    this.nums = nums;
    this.key = key;
  }
}
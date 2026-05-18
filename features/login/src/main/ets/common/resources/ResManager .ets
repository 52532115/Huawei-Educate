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

export class ResManager {
  static getBackIcon(): Resource {
    return $r('app.media.back');
  }

  static getDesc(): Resource {
    return $r('app.string.shared_desc');
  }

  static getSmall_font_size(): Resource {
    return $r('app.float.smaller_font_size');
  }

  static getMiddle_font_size(): Resource {
    return $r('app.float.middle_font_size');
  }

  static getHuge_font_size(): Resource {
    return $r('app.float.huge_font_size');
  }

  static getVp_twelve(): Resource {
    return $r('app.float.vp_twelve');
  }

  static getVp_eight(): Resource {
    return $r('app.float.vp_eight');
  }

  static getVp_twenty(): Resource {
    return $r('app.float.vp_twenty');
  }

  static getVp_fifty_six(): Resource {
    return $r('app.float.vp_fifty_six');
  }
}
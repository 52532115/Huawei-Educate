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

/**
 * Common constants for all features.
 */
export class CommonConstants {
  /**
   * Breakpoint sm.
   */
  static readonly BREAK_POINT_SM: string = 'sm';
  /**
   * Breakpoint md.
   */
  static readonly BREAK_POINT_MD: string = 'md';
  /**
   * Breakpoint lg.
   */
  static readonly BREAK_POINT_LG: string = 'lg';
  /**
   * The break point value.
   */
  static readonly BREAK_POINTS_VALUE: Array<string> = ['320vp', '600vp', '840vp'];
  /**
   * The number of columns for SM device.
   */
  static readonly COLUMN_SM: number = 4;
  /**
   * The number of columns for MD device.
   */
  static readonly COLUMN_MD: number = 8;
  /**
   * The number of columns for LG device.
   */
  static readonly COLUMN_LG: number = 12;
  /**
   * The full percentage of component.
   */
  static readonly FULL_WIDTH_PERCENT: string = '100%';
  /**
   * The full percentage of component.
   */
  static readonly FULL_HEIGHT_PERCENT: string = '100%';
  /**
   * Tab bar height.
   */
  static readonly TAB_BAR_HEIGHT_PERCENT: string = '100%';
  /**
   * Tab height.
   */
  static readonly TAB_HEIGHT_PERCENT: string = '50%';
  /**
   * Navigation path key of detail.
   */
  static readonly PATH_DETAIL: string = 'detail';
  /**
   * Navigation path key of comparison.
   */
  static readonly PATH_COMPARISON: string = 'comparison';
  /**
   * Navigation path key of comparisonDetail.
   */
  static readonly PATH_COMPARISON_DETAIL: string = 'comparisonDetail';
  /**
   * Navigation path key of buying.
   */
  static readonly PATH_BUYING: string = 'buying';
  /**
   * Common font weight.
   */
  static readonly FONT_WEIGHT_500: number = 500;
  /**
   * Common font weight.
   */
  static readonly FONT_WEIGHT_700: number = 700;
  /**
   * Common font family.
   */
  static readonly FONT_FAMILY_HEI_TI: string = 'HarmonyHeiTi-Medium';
}
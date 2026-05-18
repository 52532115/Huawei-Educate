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
  static readonly FULL_WIDTH_text: string = '65%';
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
  /**
   * Title row space.
   */
  static readonly TITLE_ROW_SPACE: number = 16;
  /**
   * Gps row space.
   */
  static readonly GPS_ROW_SPACE: number = 4;
  /**
   * List space.
   */
  static readonly LIST_SPACE: number = 12;
  /**
   * Row space.
   */
  static readonly ROW_SPACE: number = 12;
  /**
   * Main business row space.
   */
  static readonly MAIN_ROW_SPACE: number = 8;
  /**
   * Button row space.
   */
  static readonly BUTTON_ROW_SPACE: number = 4;
  /**
   * List sliding offset.
   */
  static readonly LIST_SLIDING_OFFSET: number = -750;
  /**
   * List sliding offset under lg power outage.
   */
  static readonly LIST_SLIDING_OFFSET_LG: number = -450;
  /**
   * Get business data start index.
   */
  static readonly BUSINESS_DATA_COUNT_START: number = 0;
  /**
   * Get business data under sm power outage.
   */
  static readonly BUSINESS_DATA_COUNT_SM: number = 4;
  /**
   * Get business data under md power outage.
   */
  static readonly BUSINESS_DATA_COUNT_MD: number = 6;
  /**
   * Get business data under lg power outage.
   */
  static readonly BUSINESS_DATA_COUNT_LG: number = 8;
  /**
   * Get swiper display count under sm power outage.
   */
  static readonly SWIPER_DISPLAY_COUNT_SM: number = 1;
  /**
   * Get swiper display count under md power outage.
   */
  static readonly SWIPER_DISPLAY_COUNT_MD: number = 2;
  /**
   * Get swiper display count under lg power outage.
   */
  static readonly SWIPER_DISPLAY_COUNT_LG: number = 4;
  /**
   * Get list lanes count under sm power outage.
   */
  static readonly LIST_LANES_COUNT_SM: number = 1;
  /**
   * Get list lanes count under md power outage.
   */
  static readonly LIST_LANES_COUNT_MD: number = 2;
  /**
   * Get list lanes count under lg power outage.
   */
  static readonly LIST_LANES_COUNT_LG: number = 4;
  /**
   * Get swiper item space under sm power outage.
   */
  static readonly SWIPER_SPACE_SM: number = 13;
  /**
   * Get swiper item space under md power outage.
   */
  static readonly SWIPER_SPACE_MD: number = 13;
  /**
   * Get swiper item space under lg power outage.
   */
  static readonly SWIPER_SPACE_LG: number = 16;
  /**
   * Get row space under md power outage.
   */
  static readonly BUSINESS_ROW_SPACE_MD: number = 12;
  /**
   * Get row space under lg power outage.
   */
  static readonly BUSINESS_ROW_SPACE_LG: number = 30;
  /**
   * Get flex height under sm power outage.
   */
  static readonly DEMAND_FLEX_HEIGHT_SM: string = '96vp';
  /**
   * Get flex height.
   */
  static readonly DEMAND_FLEX_HEIGHT: string = '48vp';
  /**
   * Get column width.
   */
  static readonly DEMAND_LG_WIDTH: string = '32%';
  /**
   * Get main business row width.
   */
  static readonly MAIN_BUSINESS_WIDTH: string = '20%';
}
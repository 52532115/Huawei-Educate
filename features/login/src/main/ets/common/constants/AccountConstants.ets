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

import { AccountTable } from '../../viewmodel/ConstantsInterface';
import { relationalStore } from '@kit.ArkData';

/**
 * Common constants for all features.
 */
export class AccountCommonConstants {
  static readonly ENTRY_ABILITY_TAG: string = 'EntryAbility';
  static readonly LAUNCHER_DELAY_TIME: number = 3000;
  static readonly FULL_WIDTH: string = '100%';
  static readonly FULL_HEIGHT: string = '100%';
  static readonly TOAST_INTERVAL_TIME: number = 1000;
  static readonly APP_HOME_PAGE_URL: string = 'pages/Index';
  static readonly APP_LOGIN_PAGE_URL: string = 'pages/LoginPage';
  static readonly APP_REGISTER_PAGE_URL: string = 'pages/RegisterPage';
  static readonly VERIFY_NUMBER: string = '1234';
  static readonly DIALOG_CONTROLLER_DY_OFFSET: number = -24;
  /**
   * Rdb database config.
   */
  static readonly STORE_CONFIG: relationalStore.StoreConfig = {
    name: 'database.db',
    securityLevel: relationalStore.SecurityLevel.S1
  };
  static readonly ACCOUNT_TABLE: AccountTable = {
    tableName: 'accountTable',
    sqlCreate: 'CREATE TABLE IF NOT EXISTS accountTable (id INTEGER PRIMARY KEY AUTOINCREMENT, phone TEXT NOT NULL, password TEXT NOT NULL,name TEXT NOT NULL,idCard TEXT NOT NULL,sex INTEGER NOT NULL,districtTown TEXT NOT NULL,company TEXT NOT NULL,industryType TEXT NOT NULL,documentCompany TEXT )',
    columns: ['id', 'phone', 'password', 'name', 'idCard', 'sex', 'districtTown', 'company', 'industryType',
      'documentCompany']
  };
  /**
   * Log tag.
   */
  static readonly RDB_TAG = '[Debug.Rdb]';
  static readonly TABLE_TAG = '[Debug.AccountTable]';
  static readonly INDEX_TAG = '[Debug.Index]';
}
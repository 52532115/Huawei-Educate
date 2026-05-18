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

// 用户首选项为应用提供Key-Value键值型的数据处理能力，支持应用持久化轻量级数据，并对其修改和查询。
//一个应用内部可以创建多个首选项实例，每个实例都会对应沙箱中的持久化文件
//key是string类型，最大长度限制为80字节
//value为数字型、字符型、布尔型以及这3种类型的数组类型。最大长度为8192个字节

import dataPreferences from '@ohos.data.preferences';
import common from '@ohos.app.ability.common';
import Logger from './Logger';
import { BusinessError } from '@kit.BasicServicesKit';

const TAG = 'PreferencesService';

class PreferencesUtil {
  preMap: Map<string, dataPreferences.Preferences> = new Map();

  //创建Preferences实例
  async loadPreferences(context: common.UIAbilityContext, name: string) {
    try {
      let pref = await dataPreferences.getPreferences(context, name);
      this.preMap.set(name, pref);
    } catch (e) {
      Logger.error(TAG, `failed to load preference,message is ${(e as BusinessError).message}`);
    }
  }

  //写入数据
  async putPreferencesValue(name: string, key: string, value: dataPreferences.ValueType) {
    if (!this.preMap.has(name)) {
      return;
    }
    try {
      let pref = this.preMap.get(name) as dataPreferences.Preferences;
      //写入数据
      await pref.put(key, value);
      //写入文件
      await pref.flush();
    } catch (e) {
      Logger.error(TAG, `failed to write preference,message is ${(e as BusinessError).message}`);
    }
  }

  //删除指定key
  async deletePreferenceskey(name: string, key: string) {
    if (!this.preMap.has(name)) {
      return;
    }
    let pref = this.preMap.get(name) as dataPreferences.Preferences;
    //删除
    pref.deleteSync(key);
    //刷盘
    await pref.flush();
  }
}

export const preferencesUtil = new PreferencesUtil();
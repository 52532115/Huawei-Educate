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

//手机号  密码  姓名  身份证号  性别  所在区镇  单位名称  行业类别  制证单位
export default class AccountInfo {
  id: number = -1;
  //手机号
  phone: string = '';
  //密码
  password: string = '';
  //姓名
  name: string = '';
  //身份证号
  idCard: string = '';
  //性别 0：男 1：女
  sex: number = 0;
  //所在区镇  --选择
  districtTown: string = '';
  //单位名称
  company: string = '';
  //行业类别  --选择
  industryType: string = '';
  //制证单位  --选择
  documentCompany: string = '';
};

//性别枚举
export enum SexOperationStatus {
  MALE = 0,
  FEMALE = 1,
}

//记住密码枚举
export enum RememberPasswordOperationStatus {
  NOTREMEMBER = 0,
  REMEMBER = 1,
}

//行业类别
export const industryTypeList: string[] = ['化工', '矿业', '烟花爆竹', '冶金行业', '商贸行业', '其他'];

//制证单位
export const documentCompanyList: string[] = ['应急管理部门', '住建部门', '市场监督部门', '其他'];

//所在区镇
export const districtTownList: string[] = ['杭州市', '宁波市', '温州市'];
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

export class BusinessInfo {
  icon: Resource;
  text: ResourceStr;
  router?: string;
  iconBig?: Resource;
  bgColor?: string;
  itemId?: number;

  constructor(icon: Resource, text: ResourceStr, iconBig?: Resource, router?: string, bgColor?: string, itemId?: number) {
    this.icon = icon;
    this.text = text;
    this.iconBig = iconBig;
    this.router = router;
    this.bgColor = bgColor;
    this.itemId = itemId;
  }
}

class HomeViewModel {
  getMainBusiness(): BusinessInfo[] {
    let mainBusinessList: BusinessInfo[] = [
      new BusinessInfo($r('app.media.icon1'), $r('app.string.home_account'), $r('app.media.ic_fund_investment'), '',
        '#409eff'),
      new BusinessInfo($r('app.media.icon2'), $r('app.string.home_details'), $r('app.media.ic_precious_metals'), '',
        '#67c23a'),
      new BusinessInfo($r('app.media.icon1'), $r('app.string.home_transfers'), $r('app.media.ic_wealth_products'), '',
        '#e6a23c'),
      new BusinessInfo($r('app.media.icon2'), $r('app.string.home_loans'), $r('app.media.ic_home_more'), '', '#f56c6c')
    ];
    return mainBusinessList;
  }

  getAllBusiness(): BusinessInfo[] {
    let allBusinessList: BusinessInfo[] = [
      new BusinessInfo($r('app.media.ic_fund_investment'), $r('app.string.home_fund_investment')),
      new BusinessInfo($r('app.media.ic_wealth_products'), $r('app.string.home_wealth_products')),
      new BusinessInfo($r('app.media.ic_home_cards'), $r('app.string.home_cards')),
      new BusinessInfo($r('app.media.ic_home_notes'), $r('app.string.home_notes')),
      new BusinessInfo($r('app.media.ic_quick_profit'), $r('app.string.home_quick_profit')),
      new BusinessInfo($r('app.media.ic_precious_metals'), $r('app.string.home_precious_metals')),
      new BusinessInfo($r('app.media.ic_deposits'), $r('app.string.home_deposits')),
      new BusinessInfo($r('app.media.ic_payment'), $r('app.string.home_payment')),
      new BusinessInfo($r('app.media.ic_quick_loan'), $r('app.string.home_quick_loan')),
      new BusinessInfo($r('app.media.ic_quick_loan'), $r('app.string.home_quick_loan')),
      new BusinessInfo($r('app.media.ic_quick_loan'), $r('app.string.home_quick_loan')),
      new BusinessInfo($r('app.media.ic_quick_loan'), $r('app.string.home_quick_loan')),
      new BusinessInfo($r('app.media.ic_quick_loan'), $r('app.string.home_quick_loan')),
      new BusinessInfo($r('app.media.ic_quick_loan'), $r('app.string.home_quick_loan')),
      new BusinessInfo($r('app.media.ic_quick_loan'), $r('app.string.home_quick_loan')),
      new BusinessInfo($r('app.media.ic_quick_loan'), $r('app.string.home_quick_loan')),
      new BusinessInfo($r('app.media.ic_quick_loan'), $r('app.string.home_quick_loan')),
      new BusinessInfo($r('app.media.ic_quick_loan'), $r('app.string.home_quick_loan')),
      new BusinessInfo($r('app.media.ic_quick_loan'), $r('app.string.home_quick_loan')),
      new BusinessInfo($r('app.media.ic_quick_loan'), $r('app.string.home_quick_loan')),
      new BusinessInfo($r('app.media.ic_quick_loan'), $r('app.string.home_quick_loan')),
      new BusinessInfo($r('app.media.ic_quick_loan'), $r('app.string.home_quick_loan')),
      new BusinessInfo($r('app.media.ic_quick_loan'), $r('app.string.home_quick_loan')),
      new BusinessInfo($r('app.media.ic_quick_loan'), $r('app.string.home_quick_loan')),
      new BusinessInfo($r('app.media.ic_quick_loan'), $r('app.string.home_quick_loan')),
      new BusinessInfo($r('app.media.ic_quick_loan'), $r('app.string.home_quick_loan'))
    ];
    return allBusinessList;
  }

  getPhoneBusiness(): BusinessInfo[] {
    let allBusinessInfoList = this.getAllBusiness();
    let phoneBusinessList = allBusinessInfoList.slice(0, 7);
    phoneBusinessList.push(new BusinessInfo($r('app.media.ic_home_more'), $r('app.string.home_more')));
    return phoneBusinessList;
  }

  getFoldBusiness(): BusinessInfo[] {
    let allBusinessInfoList = this.getAllBusiness();
    let phoneBusinessList = allBusinessInfoList.slice(0, 11);
    phoneBusinessList.push(new BusinessInfo($r('app.media.ic_home_more'), $r('app.string.home_more')));
    return phoneBusinessList;
  }

  getTabletBusiness(): BusinessInfo[] {
    let allBusinessInfoList = this.getAllBusiness();
    let phoneBusinessList = allBusinessInfoList.slice(0, 15);
    phoneBusinessList.push(new BusinessInfo($r('app.media.ic_home_more'), $r('app.string.home_more')));
    return phoneBusinessList;
  }

  getListBusiness(): BusinessInfo[] {
    let listBusinessInfoList: BusinessInfo[] = [
      new BusinessInfo($r('app.media.data_structure'), $r('app.string.list1'), undefined, undefined, undefined, 9),
      new BusinessInfo($r('app.media.computing_network'), $r('app.string.list2'), undefined, undefined, undefined, 13),
      new BusinessInfo($r('app.media.operating_system'), $r('app.string.list3'), undefined, undefined, undefined, 12),
      new BusinessInfo($r('app.media.database'), $r('app.string.list4'), undefined, undefined, undefined, 14),
      new BusinessInfo($r('app.media.software'), $r('app.string.list5'), undefined, undefined, undefined, 18),
      new BusinessInfo($r('app.media.organization'), $r('app.string.list6'), undefined, undefined, undefined, 17),
    ];
    return listBusinessInfoList;
  }

  getListHomepage(): BusinessInfo[] {
    let listBusinessInfoList: BusinessInfo[] = [
      new BusinessInfo($r('app.media.ic_list_paper'), $r('app.string.home_list')),
      new BusinessInfo($r('app.media.ic_list_contracts'), $r('app.string.home_list')),
      new BusinessInfo($r('app.media.ic_list_hello'), $r('app.string.home_list_two')),
      new BusinessInfo($r('app.media.ic_list_money'), $r('app.string.home_list')),

    ];
    return listBusinessInfoList;
  }
}

export default new HomeViewModel();
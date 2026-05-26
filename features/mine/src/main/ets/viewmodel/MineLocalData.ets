/*
 *  Copyright (c) 2025 Huawei Device Co., Ltd.
 *  Licensed under the Apache License, Version 2.0 (the "License");
 *  you may not use this file except in compliance with the License.
 *  You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 *
 */

import { MineListModel } from './MineListModel';
import { MineSetListModel } from './MineSetListModel';
import { MineCourseListModel } from './MineCourseListModel';
import { MineOnlineTestModel } from './MineOnlineTestModel';
import { MineErrorModel, createErrorModel } from './MineErrorModel';
import fileIo from '@ohos.file.fs';


const ERROR_STORE_KEY = 'ErrorQuestions';
const ERROR_BOOK_FILE = '/errorBook.json';

function getErrorBookFilePath(): string | null {
  const filesDir = AppStorage.get<string>('filesDir');
  if (!filesDir) {
    return null;
  }
  return filesDir + ERROR_BOOK_FILE;
}

function persistErrorModels(models: MineErrorModel[]): void {
  try {
    const filePath = getErrorBookFilePath();
    if (!filePath) {
      return;
    }
    const file: fileIo.File = fileIo.openSync(filePath, 0o2 | 0o100 | 0o1000);
    fileIo.writeSync(file.fd, JSON.stringify(models));
    fileIo.closeSync(file);
  } catch (e) {
    console.error('persistErrorModels failed: ' + JSON.stringify(e));
  }
}

function loadErrorModelsFromFile(): MineErrorModel[] | null {
  try {
    const filePath = getErrorBookFilePath();
    if (!filePath) {
      return null;
    }
    const text = fileIo.readTextSync(filePath);
    if (text && text.length > 0) {
      const parsed: MineErrorModel[] = JSON.parse(text) as MineErrorModel[];
      return parsed;
    }
  } catch (e) {
    // File doesn't exist or parse error
  }
  return null;
}

export function getErrorModels(): MineErrorModel[] {
  // First check AppStorage cache
  try {
    const stored = AppStorage.get<string>(ERROR_STORE_KEY);
    if (stored && stored.length > 0) {
      const parsed: MineErrorModel[] = JSON.parse(stored) as MineErrorModel[];
      return parsed;
    }
  } catch (e) {
    // fall through
  }

  // Try loading from persistent file
  const fromFile = loadErrorModelsFromFile();
  if (fromFile && fromFile.length > 0) {
    AppStorage.setOrCreate(ERROR_STORE_KEY, JSON.stringify(fromFile));
    return fromFile;
  }

  // Fallback to defaults — cache in AppStorage so IDs stay consistent
  const result: MineErrorModel[] = [];
  for (let i = 0; i < DEFAULT_ERROR_MODELS.length; i++) {
    const m = DEFAULT_ERROR_MODELS[i];
    const copy: MineErrorModel = {
      id: `err_default_${Date.now()}_${i}`,
      title: m.title,
      option: m.option,
      rightQues: m.rightQues,
      answer: m.answer,
      userNote: m.userNote,
      mistakeReason: m.mistakeReason,
      knowledgeTag: m.knowledgeTag,
      createTime: m.createTime,
      key: m.key,
    };
    result.push(copy);
  }
  AppStorage.setOrCreate(ERROR_STORE_KEY, JSON.stringify(result));
  return result;
}

export function saveErrorModels(models: MineErrorModel[]): void {
  const json = JSON.stringify(models);
  AppStorage.setOrCreate(ERROR_STORE_KEY, json);
  persistErrorModels(models);
}

export function addErrorModel(model: MineErrorModel): void {
  const models = getErrorModels();
  models.unshift(model);
  saveErrorModels(models);
}

export function deleteErrorModel(id: string): void {
  let models = getErrorModels();
  models = models.filter((m) => m.id !== id);
  saveErrorModels(models);
}

export function updateErrorModel(updated: MineErrorModel): void {
  const models = getErrorModels();
  const index = models.findIndex((m) => m.id === updated.id);
  if (index !== -1) {
    models[index] = updated;
    saveErrorModels(models);
  }
}

const DEFAULT_ERROR_MODELS: MineErrorModel[] = [
  createErrorModel(
    '极限 lim(x→0) sin(3x)/x 的值为？',
    ['0', '1', '3', '不存在'],
    2, 1, '等价无穷小替换：sin(3x)~3x，原式=lim(3x/x)=3',
    '误以为 sin(x)~x 对所有含参形式都直接替换为1，忽略了系数',
    '函数与极限'
  ),
  createErrorModel(
    '函数 f(x)=x³-3x 在区间[-2,2]上的最大值是？',
    ['-2', '0', '2', '6'],
    3, 1,
    'f\'(x)=3x²-3=3(x+1)(x-1)，驻点x=±1。f(-2)=-2, f(-1)=2, f(1)=-2, f(2)=2，最大值2',
    '只计算了驻点，忘记检查区间端点函数值',
    '导数与微分'
  ),
  createErrorModel(
    '不定积分 ∫(3x²+e^x)dx 的结果是？',
    ['x³+e^x+C', 'x³+e^x', '3x³+e^x+C', 'x³+e^x/x+C'],
    0, 2, '∫3x²dx=x³，∫e^xdx=e^x，加上积分常数C',
    '漏写积分常数C，不定积分必须加常数',
    '不定积分'
  ),
  createErrorModel(
    '定积分 ∫₀¹ (2x+1)dx 的值为？',
    ['1', '1.5', '2', '3'],
    2, 0,
    '原式=[x²+x]₀¹=(1+1)-(0+0)=2',
    '计算原函数时忘记常数项1的积分为x，误写成∫1dx=0',
    '定积分'
  ),
  createErrorModel(
    '判断级数 ∑(n=1→∞) 1/(n²+n) 的敛散性',
    ['发散', '条件收敛', '绝对收敛', '无法判断'],
    2, 3,
    '1/(n²+n)<1/n²，∑1/n²收敛(p=2>1)，由比较判别法知原级数绝对收敛',
    '误将分母 n²+n 当作 n 的一次方，用调和级数判断导致错误',
    '无穷级数'
  ),
];

const setListModels: MineSetListModel[][] = [
  [
    new MineSetListModel(
      $r('app.string.mine_set_grxx'),
      '0',
      'MineModiPersonPage'
    ),
    new MineSetListModel(
      $r('app.string.mine_set_xgmm'),
      '1',
      'ModifyPasswordView'
    ),
  ],
  [
    new MineSetListModel(
      $r('app.string.mine_set_ysxy'),
      '2',
      'PolicyAgreement'
    ),
    new MineSetListModel(
      $r('app.string.mine_set_qchc'),
      '3',
      '/clear'
    ),
    new MineSetListModel(
      $r('app.string.mine_set_zxzh'),
      '4',
      'LogoutView'
    ),
    new MineSetListModel(
      $r('app.string.mine_set_tcdl'),
      '5',
      '/logout'
    ),
  ]

];

const listModel: MineListModel[] = [
  new MineListModel(
    $r('app.media.mine_icon_1'),
    $r('app.string.mine_title_kc'),
    '0',
    'MineCoursePage',
    '#f56c6c'//蓝色
  ),
  new MineListModel(
    $r('app.media.mine_icon_2'),
    $r('app.string.mine_title_ks'),
    '1',
    'MineOnlineTestPage',
    '#409eff'
  ),
  new MineListModel(
    $r('app.media.mine_icon_3'),
    $r('app.string.mine_title_ct'),
    '2',
    'MineErrorPage',
    '#67c23a'
  ),
  new MineListModel(
    $r('app.media.mine_icon_4'),
    $r('app.string.mine_title_px'),
    '3',
    'MineTrainPage',
    '#e6a23c'
  ),
  new MineListModel(
    $r('app.media.mine_icon_4'),
    $r('app.string.mine_title_sz'),
    '4',
    'MineSetPage',
    '#409eff'//蓝色
  ),

];

const courseList: MineCourseListModel[] = [
  new MineCourseListModel(
    'placeHolder',
    '高等数学（上）',
    '1',
    0.92,
    '刘教授',
    ''
  ),
  new MineCourseListModel(
    'placeHolder',
    '程序设计基础（C语言）',
    '2',
    0.88,
    '李教授',
    ''
  ),
  new MineCourseListModel(
    'placeHolder',
    '数据结构',
    '3',
    0.65,
    '张教授',
    ''
  ),
  new MineCourseListModel(
    'placeHolder',
    '计算机组成原理',
    '4',
    0.55,
    '周教授',
    ''
  ),
  new MineCourseListModel(
    'placeHolder',
    '操作系统',
    '5',
    0.78,
    '陈教授',
    ''
  ),
  new MineCourseListModel(
    'placeHolder',
    '计算机网络',
    '6',
    0.48,
    '吴教授',
    ''
  ),
  new MineCourseListModel(
    'placeHolder',
    '数据库系统原理',
    '7',
    0.72,
    '赵教授',
    ''
  ),
  new MineCourseListModel(
    'placeHolder',
    '编译原理',
    '8',
    0.38,
    '周教授',
    ''
  )
];

class TrainInfo {
  id: number = 0;
  img?: Resource; //图片
  count?: number; //课程数量
  title?: string; //标题
  startTime?: string; //开始时间
  endTime?: string; //截止时间
  applyNum?: number; //报名人数
  money?: number; //钱
}

//培训列表数据
const trainList: TrainInfo[] = [
  {
    id: 1,
    img: $r('app.media.train_pic01'),
    count: 24,
    title: '行业模板专题宣传培训-注册用户专用培训班',
    startTime: '2023-09-28',
    endTime: '2024-12-31',
    applyNum: 13658,
    money: 1000
  },
  {
    id: 2,
    img: $r('app.media.train_pic02'),
    count: 14,
    title: '行业模板专题宣传培训-注册用户专用培训班',
    startTime: '2023-09-28',
    endTime: '2024-12-31',
    applyNum: 25879,
    money: 866
  },
  {
    id: 3,
    img: $r('app.media.train_pic03'),
    count: 256,
    title: '行业模板专题宣传培训-注册用户专用培训班',
    startTime: '2024-02-05',
    endTime: '2024-12-31',
    applyNum: 6894,
    money: 356
  },
  {
    id: 3,
    img: $r('app.media.train_pic03'),
    count: 256,
    title: '行业模板专题宣传培训-注册用户专用培训班',
    startTime: '2024-02-05',
    endTime: '2024-12-31',
    applyNum: 6894,
    money: 356
  },
  {
    id: 3,
    img: $r('app.media.train_pic03'),
    count: 256,
    title: '行业模板专题宣传培训-注册用户专用培训班',
    startTime: '2024-02-05',
    endTime: '2024-12-31',
    applyNum: 6894,
    money: 356
  },
  {
    id: 3,
    img: $r('app.media.train_pic03'),
    count: 256,
    title: '行业模板专题宣传培训-注册用户专用培训班',
    startTime: '2024-02-05',
    endTime: '2024-12-31',
    applyNum: 6894,
    money: 356
  },
  {
    id: 3,
    img: $r('app.media.train_pic03'),
    count: 256,
    title: '行业模板专题宣传培训-注册用户专用培训班',
    startTime: '2024-02-05',
    endTime: '2024-12-31',
    applyNum: 6894,
    money: 356
  },
  {
    id: 3,
    img: $r('app.media.train_pic03'),
    count: 256,
    title: '行业模板专题宣传培训-注册用户专用培训班',
    startTime: '2024-02-05',
    endTime: '2024-12-31',
    applyNum: 6894,
    money: 356
  },
  {
    id: 3,
    img: $r('app.media.train_pic03'),
    count: 256,
    title: '行业模板专题宣传培训-注册用户专用培训班',
    startTime: '2024-02-05',
    endTime: '2024-12-31',
    applyNum: 6894,
    money: 356
  },
  {
    id: 3,
    img: $r('app.media.train_pic03'),
    count: 256,
    title: '行业模板专题宣传培训-注册用户专用培训班',
    startTime: '2024-02-05',
    endTime: '2024-12-31',
    applyNum: 6894,
    money: 356
  },
  {
    id: 3,
    img: $r('app.media.train_pic03'),
    count: 256,
    title: '行业模板专题宣传培训-注册用户专用培训班',
    startTime: '2024-02-05',
    endTime: '2024-12-31',
    applyNum: 6894,
    money: 356
  },
  {
    id: 3,
    img: $r('app.media.train_pic03'),
    count: 256,
    title: '行业模板专题宣传培训-注册用户专用培训班',
    startTime: '2024-02-05',
    endTime: '2024-12-31',
    applyNum: 6894,
    money: 356
  },
];

const testList: MineOnlineTestModel[] = [
  new MineOnlineTestModel(
    '进行中',
    '行业模板安全规范学习，按照新的指导去规范学习行业模板开发',
    '1',
    '05-26',
    '05-30',
    '100'
  ),
  new MineOnlineTestModel(
    '已结束',
    '行业模板安全规范学习，按照新的指导去规范学习行业模板开发',
    '2',
    '05-26',
    '05-30',
    '100'
  ),
  new MineOnlineTestModel(
    '已结束',
    '行业模板安全规范学习，按照新的指导去规范学习行业模板开发',
    '3',
    '05-26',
    '05-30',
    '100'
  ),
  new MineOnlineTestModel(
    '已结束',
    '行业模板安全规范学习，按照新的指导去规范学习行业模板开发',
    '4',
    '05-26',
    '05-30',
    '100'
  ),
  new MineOnlineTestModel(
    '已结束',
    '行业模板安全规范学习，按照新的指导去规范学习行业模板开发',
    '5',
    '05-26',
    '05-30',
    '100'
  ),
  new MineOnlineTestModel(
    '已结束',
    '行业模板安全规范学习，按照新的指导去规范学习行业模板开发',
    '6',
    '05-26',
    '05-30',
    '100'
  ),
  new MineOnlineTestModel(
    '已结束',
    '行业模板安全规范学习，按照新的指导去规范学习行业模板开发',
    '7',
    '05-26',
    '05-30',
    '100'
  ),
];



export { listModel, setListModels, courseList, TrainInfo, trainList, testList };
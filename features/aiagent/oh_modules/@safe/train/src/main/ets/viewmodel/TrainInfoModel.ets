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


//培训列表info
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
    title: '行业模板的专题宣传-培训行业模板使用方法',
    startTime: '2023/09/28',
    endTime: '2024/09/28',
    applyNum: 13658,
    money: 1000
  },
  {
    id: 2,
    img: $r('app.media.train_pic02'),
    count: 26,
    title: '行业模板的专题宣传-培训行业模板使用方法',
    startTime: '2023/09/28',
    endTime: '2024/09/28',
    applyNum: 25879,
    money: 866
  },
  {
    id: 3,
    img: $r('app.media.train_pic03'),
    count: 60,
    title: '行业模板的专题宣传-培训行业模板使用方法',
    startTime: '2023/09/28',
    endTime: '2024/09/28',
    applyNum: 6894,
    money: 356
  },
  {
    id: 4,
    img: $r('app.media.train_pic04'),
    count: 11,
    title: '行业模板的专题宣传-培训行业模板使用方法',
    startTime: '2023/09/28',
    endTime: '2024/09/28',
    applyNum: 1145,
    money: 14
  },
  {
    id: 3,
    img: $r('app.media.train_pic03'),
    count: 256,
    title: '行业模板的专题宣传-培训行业模板使用方法',
    startTime: '2023/09/28',
    endTime: '2024/09/28',
    applyNum: 6894,
    money: 356
  },
  {
    id: 3,
    img: $r('app.media.train_pic03'),
    count: 256,
    title: '行业模板的专题宣传-培训行业模板使用方法',
    startTime: '2023/09/28',
    endTime: '2024/09/28',
    applyNum: 6894,
    money: 356
  },
  {
    id: 3,
    img: $r('app.media.train_pic03'),
    count: 256,
    title: '行业模板的专题宣传-培训行业模板使用方法',
    startTime: '2023/09/28',
    endTime: '2024/09/28',
    applyNum: 6894,
    money: 356
  },
  {
    id: 3,
    img: $r('app.media.train_pic03'),
    count: 256,
    title: '行业模板的专题宣传-培训行业模板使用方法',
    startTime: '2023/09/28',
    endTime: '2024/09/28',
    applyNum: 6894,
    money: 356
  },
  {
    id: 3,
    img: $r('app.media.train_pic03'),
    count: 256,
    title: '行业模板的专题宣传-培训行业模板使用方法',
    startTime: '2023/09/28',
    endTime: '2024/09/28',
    applyNum: 6894,
    money: 356
  },
  {
    id: 3,
    img: $r('app.media.train_pic03'),
    count: 256,
    title: '行业模板的专题宣传-培训行业模板使用方法',
    startTime: '2023/09/28',
    endTime: '2024/09/28',
    applyNum: 6894,
    money: 356
  }

];


//培训列表info
class IntroInfo {
  type?: string; //培训类型
  startTime?: string; //开始时间
  endTime?: string; //截止时间
  count?: number; //课程数量
  hour?: number; //规定学时
  company?: string; //主办单位
  trainingObject?: string; //培训对象
  process?: string; //学习进度
  requiredProcess?: string; //必修学习进度
  demand?: string; //考核要求

  constructor(type: string, startTime: string, endTime: string, count: number, hour: number, company: string,
    trainingObject: string, process: string, requiredProcess: string, demand: string) {
    this.type = type;
    this.startTime = startTime;
    this.endTime = endTime;
    this.count = count;
    this.hour = hour;
    this.company = company;
    this.trainingObject = trainingObject;
    this.process = process;
    this.requiredProcess = requiredProcess;
    this.demand = demand;
  }
}

//培训列表info 枚举
enum IntroInfoEnum {
  type = '培训类型',
  startTime = '开始时间',
  endTime = '截止时间',
  count = '课程数量',
  hour = '规定学时',
  company = '主办单位',
  trainingObject = '培训对象',
  process = '学习进度',
  requiredProcess = '必修学习进度',
  demand = '考核要求',
}

const introObj =
  new IntroInfo('行业模板宣传培训-行业模板专用培训班', '2023/09/28', '2024/09/28', 24, 7, '', '', '0.0%', '100.0%', '');


//课程info
class CourseInfo {
  id: number = 0;
  img?: Resource; //图片
  hour?: number; //时长
  title?: string; //标题
  process?: string; //时间
  type?: number = 0; //类型  0:选修
  finished?: number = 0; //0：已完成  1：未完成
  name?: string; //教师-课程名称
}

//大学计算机专业主修课程列表数据
const courseList: CourseInfo[] = [
  {
    id: 1,
    img: $r('app.media.train_pic01'),
    hour: 6,
    title: '高等数学（上）',
    process: '0.00',
    type: 1,
    finished: 1,
    name: '刘教授'
  },
  {
    id: 2,
    img: $r('app.media.train_pic02'),
    hour: 6,
    title: '高等数学（下）',
    process: '0.00',
    type: 1,
    finished: 1,
    name: '刘教授'
  },
  {
    id: 3,
    img: $r('app.media.train_pic03'),
    hour: 4,
    title: '线性代数',
    process: '0.00',
    type: 1,
    finished: 1,
    name: '王教授'
  },
  {
    id: 4,
    img: $r('app.media.train_pic04'),
    hour: 4,
    title: '概率论与数理统计',
    process: '0.00',
    type: 1,
    finished: 1,
    name: '陈教授'
  },
  {
    id: 5,
    img: $r('app.media.train_pic01'),
    hour: 4,
    title: '离散数学',
    process: '0.00',
    type: 1,
    finished: 1,
    name: '张教授'
  },
  {
    id: 6,
    img: $r('app.media.train_pic02'),
    hour: 4,
    title: '大学物理',
    process: '0.00',
    type: 1,
    finished: 1,
    name: '赵教授'
  },
  {
    id: 7,
    img: $r('app.media.train_pic03'),
    hour: 5,
    title: '程序设计基础（C语言）',
    process: '0.00',
    type: 1,
    finished: 1,
    name: '李教授'
  },
  {
    id: 8,
    img: $r('app.media.train_pic04'),
    hour: 4,
    title: '面向对象程序设计（Java）',
    process: '0.00',
    type: 1,
    finished: 1,
    name: '李教授'
  },
  {
    id: 9,
    img: $r('app.media.data_structure'),
    hour: 5,
    title: '数据结构',
    process: '0.00',
    type: 1,
    finished: 1,
    name: '张教授'
  },
  {
    id: 10,
    img: $r('app.media.train_pic02'),
    hour: 4,
    title: '算法设计与分析',
    process: '0.00',
    type: 1,
    finished: 1,
    name: '张教授'
  },
  {
    id: 11,
    img: $r('app.media.train_pic03'),
    hour: 5,
    title: '计算机组成原理',
    process: '0.00',
    type: 1,
    finished: 1,
    name: '周教授'
  },
  {
    id: 12,
    img: $r('app.media.operating_system'),
    hour: 4,
    title: '操作系统',
    process: '0.00',
    type: 1,
    finished: 1,
    name: '陈教授'
  },
  {
    id: 13,
    img: $r('app.media.computing_network'),
    hour: 4,
    title: '计算机网络',
    process: '0.00',
    type: 1,
    finished: 1,
    name: '吴教授'
  },
  {
    id: 14,
    img: $r('app.media.database'),
    hour: 4,
    title: '数据库系统原理',
    process: '0.00',
    type: 1,
    finished: 1,
    name: '赵教授'
  },
  {
    id: 15,
    img: $r('app.media.train_pic03'),
    hour: 4,
    title: '编译原理',
    process: '0.00',
    type: 1,
    finished: 1,
    name: '周教授'
  },
  {
    id: 16,
    img: $r('app.media.train_pic04'),
    hour: 3,
    title: '软件工程',
    process: '0.00',
    type: 1,
    finished: 1,
    name: '孙教授'
  },
  {
    id: 17,
    img: $r('app.media.organization'),
    hour: 3,
    title: '计算机组成原理',
    process: '0.00',
    type: 0,
    finished: 1,
    name: '黄教授'
  },
  {
    id: 18,
    img: $r('app.media.software'),
    hour: 3,
    title: '软件工程导论',
    process: '0.00',
    type: 0,
    finished: 1,
    name: '吴教授'
  },
  {
    id: 19,
    img: $r('app.media.train_pic03'),
    hour: 3,
    title: '计算机图形学',
    process: '0.00',
    type: 0,
    finished: 1,
    name: '郑教授'
  },
  {
    id: 20,
    img: $r('app.media.train_pic04'),
    hour: 4,
    title: '嵌入式系统',
    process: '0.00',
    type: 0,
    finished: 1,
    name: '周教授'
  },
  {
    id: 21,
    img: $r('app.media.train_pic01'),
    hour: 3,
    title: '信息安全概论',
    process: '0.00',
    type: 0,
    finished: 1,
    name: '杨教授'
  },
  {
    id: 22,
    img: $r('app.media.train_pic02'),
    hour: 3,
    title: '分布式系统',
    process: '0.00',
    type: 0,
    finished: 1,
    name: '陈教授'
  },
  {
    id: 23,
    img: $r('app.media.train_pic03'),
    hour: 3,
    title: '机器学习',
    process: '0.00',
    type: 0,
    finished: 1,
    name: '吴教授'
  },
  {
    id: 24,
    img: $r('app.media.train_pic04'),
    hour: 3,
    title: 'Web前端开发',
    process: '0.00',
    type: 0,
    finished: 1,
    name: '黄教授'
  },
  {
    id: 25,
    img: $r('app.media.train_pic01'),
    hour: 2,
    title: 'Linux系统管理',
    process: '0.00',
    type: 0,
    finished: 1,
    name: '马教授'
  }
];

//考试info
class ExaminationInfo {
  id: number = 0;
  hour?: number; //时长
  title?: string; //标题
  text?: string;
  finished?: number = 0; //0：已完成  1：未完成
}

//考试列表数据
const examinationList: ExaminationInfo[] = [
  {
    id: 1,
    hour: 30,
    title: '考试1',
    text: '去考试',
    finished: 0
  },
  {
    id: 2,
    hour: 30,
    title: '考试2',
    text: '去考试',
    finished: 1
  },
  {
    id: 3,
    hour: 30,
    title: '考试3',
    text: '去考试',
    finished: 1
  }
];


//课程评价info
class CourseEvaluateInfo {
  id: number = 0;
  img?: Resource; //头像
  name?: string; //姓名
  content?: string; //内容
  time?: string; //时间
  starCount?: number = 0; //类型  0:选修
}

const courseEvaluateList: CourseEvaluateInfo[] = [
  {
    id: 1,
    img: $r('app.media.pic'),
    name: '陆亿壹',
    content: '学到可知识，学到可知识学到可知识学到可知识学到可知识学到可知识学到可知识学到可知识',
    time: '2023/09/28',
    starCount: 3
  },
  {
    id: 2,
    img: $r('app.media.pic'),
    name: '陆亿壹',
    content: '学到可知识',
    time: '2023/09/28',
    starCount: 4
  },
  {
    id: 3,
    img: $r('app.media.pic'),
    name: '陆亿壹',
    content: '挺好',
    time: '2023/09/28',
    starCount: 2
  }
];


export { TrainInfo,
  trainList as TrainList,
  introObj as IntroObj,
  IntroInfoEnum,
  IntroInfo,
  ExaminationInfo,
  examinationList as ExaminationList,
  CourseInfo,
  courseList as CourseList,
  CourseEvaluateInfo,
  courseEvaluateList as CourseEvaluateList };



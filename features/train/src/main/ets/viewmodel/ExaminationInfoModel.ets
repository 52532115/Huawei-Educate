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
class ExaminationDetailInfo {
  totalScore?: number; //试卷总分
  score?: number; //及格分数
  hours?: number; //考试时长
  topicNum?: number; //题目数量
  highScore?: number; //最高分
  examNum?: number = 100; //考试次数
  useExamNum?: number; //已考试次数
  startTime?: string; //考试开始时间
  endTime?: string; //考试截止时间
  content?: string; //考试说明

  constructor(totalScore: number, score: number, hours: number, topicNum: number, highScore: number, examNum: number,
    useExamNum: number, startTime: string, endTime: string, content: string) {
    this.totalScore = totalScore;
    this.score = score;
    this.hours = hours;
    this.topicNum = topicNum;
    this.highScore = highScore;
    this.examNum = examNum;
    this.useExamNum = useExamNum;
    this.startTime = startTime;
    this.endTime = endTime;
    this.content = content;
  }
}


const examinationDetailObj =
  new ExaminationDetailInfo(100, 60, 30, 10, 80, 100, 2, '2023年06月08日', '2025年10月31日', '考试说明');


export { ExaminationDetailInfo, examinationDetailObj };
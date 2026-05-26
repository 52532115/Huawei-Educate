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

export interface MineErrorModel {
  id: string;
  title: string;
  option: string[];
  rightQues: number;
  answer?: number;
  userNote: string;
  mistakeReason: string;
  knowledgeTag: string;
  createTime: number;
  analysis?: string;
  key: string;
}

export interface AnswerModel {
  key: string;
  value: number;
}

export function createErrorModel(
  title: string,
  option: string[],
  rightQues: number,
  answer: number | undefined,
  userNote: string,
  mistakeReason: string,
  knowledgeTag: string,
): MineErrorModel {
  return {
    id: `err_${Date.now()}_${Math.random().toString(36).substring(2, 8)}`,
    title: title,
    option: option,
    rightQues: rightQues,
    answer: answer,
    userNote: userNote,
    mistakeReason: mistakeReason,
    knowledgeTag: knowledgeTag,
    createTime: Date.now(),
    key: '',
  };
}

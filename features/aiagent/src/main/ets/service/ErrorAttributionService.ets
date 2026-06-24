/*
 * Copyright (c) 2025 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 */

import fileIo from '@ohos.file.fs';
import { ErrorQuestionItem } from '../viewmodel/ChatModels';
import {
  AdaptivePracticeQuestion,
  ErrorAttributionResult,
  ErrorCauseType,
} from '../viewmodel/AdaptivePracticeModels';

interface ErrorBookRecord {
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
  source?: string;
  sourceId?: string;
}

const ERROR_STORE_KEY = 'ErrorQuestions';
const ERROR_BOOK_FILE = '/errorBook.json';

export class ErrorAttributionService {
  diagnosePracticeQuestion(question: AdaptivePracticeQuestion): ErrorAttributionResult {
    const userLabel = this.toOptionLabel(question.selectedIndex);
    const correctLabel = this.toOptionLabel(question.correctIndex);
    const evidence = `本题属于「${question.knowledgeTag}」，你选择了 ${userLabel}，正确答案是 ${correctLabel}。`;
    return this.diagnoseByFields(
      question.title,
      question.knowledgeTag,
      evidence,
      question.explanation,
      userLabel,
      correctLabel,
    );
  }

  diagnoseErrorQuestion(question: ErrorQuestionItem): ErrorAttributionResult {
    return this.diagnoseByFields(
      question.title,
      question.category,
      question.mistakeReason,
      question.userNote,
      question.userLabel,
      question.correctLabel,
    );
  }

  diagnoseByFields(
    title: string,
    knowledgeTag: string,
    mistakeReason: string,
    userNote: string,
    userLabel: string,
    correctLabel: string,
  ): ErrorAttributionResult {
    const corpus = `${title} ${knowledgeTag} ${mistakeReason} ${userNote}`;
    const normalized = corpus.toLowerCase();
    let causeType = ErrorCauseType.UNKNOWN;
    let label = '待进一步观察';
    let confidence = 55;
    let evidence = '当前错题信息较少，建议补充错误思路和学习笔记以提高归因准确度。';

    if (this.containsAny(normalized, ['概念', '混淆', '误以为', '理解', '定义', '性质'])) {
      causeType = ErrorCauseType.CONCEPT;
      label = '概念理解偏差';
      confidence = 84;
      evidence = '错误描述中出现概念、定义或混淆类线索，说明核心概念还没有稳定建立。';
    } else if (this.containsAny(normalized, ['公式', '定理', '法则', '规则', '等价', '判别法'])) {
      causeType = ErrorCauseType.FORMULA;
      label = '公式/规则使用错误';
      confidence = 80;
      evidence = '错误描述中出现公式、定理或判别法线索，说明规则适用条件需要重新梳理。';
    } else if (this.containsAny(normalized, ['步骤', '方法', '思路', '不会', '忘记检查', '只计算'])) {
      causeType = ErrorCauseType.METHOD;
      label = '解题方法不完整';
      confidence = 78;
      evidence = '错误描述中出现步骤、方法或遗漏关键环节的线索，说明解题流程需要固化。';
    } else if (this.containsAny(normalized, ['计算', '算错', '漏写', '漏掉', '粗心', '看错', '忘记'])) {
      causeType = ErrorCauseType.CARELESS;
      label = '审题/细节失误';
      confidence = 74;
      evidence = '错误描述中出现漏写、看错或忘记类线索，属于可通过检查清单改善的失误。';
    } else if (userLabel.length > 0 && correctLabel.length > 0 && userLabel !== correctLabel) {
      causeType = ErrorCauseType.METHOD;
      label = '选项辨析能力不足';
      confidence = 66;
      evidence = `已知错误选项为 ${userLabel}，正确选项为 ${correctLabel}，建议重点比较两个选项的条件差异。`;
    }

    const remediation = this.buildRemediation(causeType, knowledgeTag);
    const nextAction = this.buildNextAction(causeType, knowledgeTag);
    return new ErrorAttributionResult(causeType, label, confidence, evidence, remediation, nextAction);
  }

  updateErrorBookAttributions(): number {
    const records = this.readErrorBookRecords();
    if (records.length === 0) {
      return 0;
    }

    let updatedCount = 0;
    for (let i = 0; i < records.length; i++) {
      const record = records[i];
      if (record.analysis && record.analysis.length > 0) {
        continue;
      }

      const result = this.diagnoseByFields(
        record.title || '',
        record.knowledgeTag || '未分类',
        record.mistakeReason || '',
        record.userNote || '',
        this.toOptionLabel(record.answer === undefined ? -1 : record.answer),
        this.toOptionLabel(record.rightQues),
      );
      record.analysis = `${result.causeLabel}（置信度 ${result.confidence}%）：${result.remediation}`;
      updatedCount += 1;
    }

    if (updatedCount > 0) {
      this.writeErrorBookRecords(records);
    }
    return updatedCount;
  }

  private buildRemediation(causeType: ErrorCauseType, knowledgeTag: string): string {
    if (causeType === ErrorCauseType.CONCEPT) {
      return `先用自己的话复述「${knowledgeTag}」的定义和适用条件，再做 3 道基础辨析题。`;
    }
    if (causeType === ErrorCauseType.FORMULA) {
      return `整理「${knowledgeTag}」常用公式/规则的前提条件，做题前先判断是否满足条件。`;
    }
    if (causeType === ErrorCauseType.METHOD) {
      return `把「${knowledgeTag}」题型拆成固定步骤，做题时逐步勾选，避免跳步。`;
    }
    if (causeType === ErrorCauseType.CALCULATION || causeType === ErrorCauseType.CARELESS) {
      return `建立检查清单：重读题干、核对单位/边界条件、复算关键步骤。`;
    }
    return `补充这道题的错误思路，并围绕「${knowledgeTag}」做一次概念回顾。`;
  }

  private buildNextAction(causeType: ErrorCauseType, knowledgeTag: string): string {
    if (causeType === ErrorCauseType.CARELESS) {
      return `下一次练习时把「${knowledgeTag}」题目限时完成后，再预留 30 秒复查。`;
    }
    if (causeType === ErrorCauseType.CONCEPT) {
      return `今天优先复习「${knowledgeTag}」核心概念，并完成同类选择题训练。`;
    }
    if (causeType === ErrorCauseType.FORMULA) {
      return `把「${knowledgeTag}」相关公式写成一张条件-结论对照表。`;
    }
    return `从「${knowledgeTag}」的基础题开始，连续做对 3 题后再进入变式题。`;
  }

  private containsAny(text: string, keywords: string[]): boolean {
    for (let i = 0; i < keywords.length; i++) {
      if (text.indexOf(keywords[i].toLowerCase()) >= 0) {
        return true;
      }
    }
    return false;
  }

  private toOptionLabel(index: number): string {
    if (index < 0) {
      return '';
    }
    return String.fromCharCode(65 + index);
  }

  private readErrorBookRecords(): ErrorBookRecord[] {
    let errorJson = '';
    try {
      const stored = AppStorage.get<string>(ERROR_STORE_KEY);
      if (stored && stored.length > 0) {
        errorJson = stored;
      }
    } catch (e) {
      // AppStorage may not be initialized during preview.
    }

    if (errorJson.length === 0) {
      const filePath = this.getErrorBookFilePath();
      if (filePath) {
        try {
          errorJson = fileIo.readTextSync(filePath);
        } catch (e) {
          // No persisted error book yet.
        }
      }
    }

    if (errorJson.length === 0) {
      return [];
    }

    try {
      return JSON.parse(errorJson) as ErrorBookRecord[];
    } catch (e) {
      return [];
    }
  }

  private writeErrorBookRecords(records: ErrorBookRecord[]): void {
    const json = JSON.stringify(records);
    AppStorage.setOrCreate(ERROR_STORE_KEY, json);
    const filePath = this.getErrorBookFilePath();
    if (!filePath) {
      return;
    }

    try {
      const file: fileIo.File = fileIo.openSync(filePath, 0o2 | 0o100 | 0o1000);
      fileIo.writeSync(file.fd, json);
      fileIo.closeSync(file);
    } catch (e) {
      // Persist failure should not block the learning flow.
    }
  }

  private getErrorBookFilePath(): string | null {
    const filesDir = AppStorage.get<string>('filesDir');
    if (!filesDir) {
      return null;
    }
    return filesDir + ERROR_BOOK_FILE;
  }
}

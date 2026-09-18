/*
 * Copyright (c) 2025 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 */

import { SeedCourseInput } from '../viewmodel/KnowledgeModels';
import { normalizeQuestionTitle } from './ErrorBookPracticeSource';

/**
 * The shipped course catalogue, mirrored from `data/cs_courses.json`.
 *
 * It is embedded in code rather than loaded from a rawfile on purpose: the
 * corpus path then needs no resource manager, no file access and no
 * permission, which is exactly what keeps the whole retrieval chain offline
 * testable. When real long-form course notes arrive, this file is the single
 * seam to replace — the store, the chunker and the retriever do not change.
 *
 * Keeping it as data (not logic) means the only rule here is the title
 * de-duplication below.
 */
function entry(courseId: string, title: string, category: string, description: string): SeedCourseInput {
  const input = new SeedCourseInput();
  input.courseId = courseId;
  input.title = title;
  input.category = category;
  input.description = description;
  return input;
}

const CATALOG: SeedCourseInput[] = [
  entry('1', '高等数学（上）', '数学基础',
    '函数、极限、连续、一元函数微积分学、向量代数与空间解析几何、多元函数微积分学、无穷级数'),
  entry('2', '高等数学（下）', '数学基础',
    '常微分方程、线性代数初步、概率论基础、复变函数与积分变换'),
  entry('3', '线性代数', '数学基础',
    '行列式、矩阵、线性方程组、向量空间、特征值与特征向量、二次型'),
  entry('4', '概率论与数理统计', '数学基础',
    '随机事件与概率、随机变量及其分布、数字特征、大数定律与中心极限定理、参数估计、假设检验'),
  entry('5', '离散数学', '数学基础',
    '命题逻辑、谓词逻辑、集合与关系、图论、树、代数系统、组合数学'),
  entry('6', '大学物理', '自然科学基础',
    '力学、热学、电磁学、光学、近代物理基础'),
  entry('7', '程序设计基础（C语言）', '编程基础',
    'C语言语法、数据类型、控制结构、函数、数组、指针、结构体、文件操作、基本算法'),
  entry('8', '面向对象程序设计（Java）', '编程基础',
    '类与对象、继承、多态、接口、异常处理、集合框架、泛型、IO流、多线程、网络编程'),
  entry('9', '数据结构', '专业核心',
    '线性表、栈与队列、串、数组与广义表、树与二叉树、图、查找、排序'),
  entry('10', '算法设计与分析', '专业核心',
    '分治策略、动态规划、贪心算法、回溯法、分支限界法、随机化算法、NP完全性理论'),
  entry('11', '计算机组成原理', '专业核心',
    '计算机系统概述、数据表示与运算、存储系统、指令系统、中央处理器、总线、输入输出系统'),
  entry('12', '操作系统', '专业核心',
    '进程管理、内存管理、文件系统、设备管理、死锁、并发控制、操作系统安全'),
  entry('13', '计算机网络', '专业核心',
    '网络体系结构、物理层、数据链路层、网络层、传输层、应用层、网络安全'),
  entry('14', '数据库系统原理', '专业核心',
    '关系模型、SQL语言、数据库设计、规范化理论、事务管理、并发控制、数据库恢复'),
  entry('15', '编译原理', '专业核心',
    '词法分析、语法分析、语义分析、中间代码生成、代码优化、目标代码生成'),
  entry('16', '软件工程', '专业核心',
    '软件生命周期、需求分析、系统设计、软件测试、项目管理、敏捷开发、DevOps'),
  // The source JSON carries 计算机组成原理 twice (id 11 as a core course, id 17
  // under the programming track). Kept verbatim here so re-syncing from the
  // JSON stays mechanical; buildCourseCatalog() drops this second copy.
  entry('17', '计算机组成原理', '编程基础',
    '计算机系统概述、数据表示与运算、存储系统、指令系统、中央处理器、总线与输入输出系统'),
  entry('18', '软件工程导论', '专业方向',
    '软件工程基本概念、软件过程模型、需求工程、系统设计方法、软件测试基础、项目管理入门、团队协作与版本控制'),
  entry('19', '计算机图形学', '专业方向',
    '图形系统、光栅图形学、几何变换、三维观察、曲线曲面、真实感图形、计算机动画'),
  entry('20', '嵌入式系统', '专业方向',
    '嵌入式处理器架构、嵌入式操作系统、接口技术、驱动开发、实时系统、物联网应用'),
  entry('21', '信息安全概论', '专业方向',
    '密码学基础、身份认证、访问控制、网络安全、系统安全、应用安全、安全管理'),
  entry('22', '分布式系统', '专业方向',
    '分布式架构、一致性协议、分布式存储、分布式计算、微服务、容器化技术、云计算基础'),
  entry('23', '机器学习', '专业方向',
    '监督学习、无监督学习、集成学习、特征工程、模型评估、深度学习入门、常用框架'),
  entry('24', 'Web前端开发', '专业方向',
    'HTML/CSS/JavaScript、响应式设计、前端框架（Vue/React）、前端工程化、性能优化'),
  entry('25', 'Linux系统管理', '专业方向',
    'Linux基础命令、Shell脚本编程、用户与权限管理、进程管理、网络配置、服务管理'),
];

/**
 * Returns the catalogue with duplicate course titles collapsed to the first
 * occurrence.
 *
 * The source JSON lists 计算机组成原理 twice — once as a core course and once
 * under the programming track, with two descriptions of the same syllabus.
 * Indexing both would put two near-identical passages in front of the model for
 * the same query, so the later row is dropped and the core-course row (which
 * carries the fuller description) wins. This is a catalogue data-quality rule,
 * not a retrieval rule: the corpus adapter still owns id-level de-duplication.
 */
export function buildCourseCatalog(): SeedCourseInput[] {
  const unique: SeedCourseInput[] = [];
  const seenTitles = new Set<string>();
  for (let i = 0; i < CATALOG.length; i++) {
    const row = CATALOG[i];
    const titleKey = normalizeQuestionTitle(row.title);
    if (titleKey.length === 0 || seenTitles.has(titleKey)) {
      continue;
    }
    seenTitles.add(titleKey);
    unique.push(row);
  }
  return unique;
}

/** Raw row count, so a test can prove the de-duplication actually removed one. */
export const CATALOG_ROW_COUNT = CATALOG.length;

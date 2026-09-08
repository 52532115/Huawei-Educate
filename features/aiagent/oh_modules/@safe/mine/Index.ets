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

export { add } from './src/main/ets/utils/Calc';

export { MinePage } from './src/main/ets/views/MinePage';

export { MineCoursePage } from './src/main/ets/views/MineCoursePage';

export { MineOnlineTestPage } from './src/main/ets/views/MineOnlineTestPage';

export { MineStartTestPage } from './src/main/ets/views/MineStartTestPage';

export { MineTestResPage } from './src/main/ets/views/MineTestResPage';

export { MineSetPage } from './src/main/ets/views/MineSetPage';

export { MineErrorPage } from './src/main/ets/views/MineErrorPage';

export { MineAddErrorPage } from './src/main/ets/views/MineAddErrorPage';

export { MineModiPersonPage } from './src/main/ets/views/MineModiPersonPage';

// Learning data exports consumed by the AI analysis module. Keeping the
// source in mine avoids maintaining a second, divergent course list.
export { courseList as MineCourseList } from './src/main/ets/viewmodel/MineLocalData';
export { MineCourseListModel } from './src/main/ets/viewmodel/MineCourseListModel';

export { MineTrainPage } from './src/main/ets/views/MineTrainPage';






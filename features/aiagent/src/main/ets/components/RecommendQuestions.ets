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

@Component
export struct RecommendQuestions {
  @Prop questions: string[];
  onQuestionClick?: (question: string) => void;

  build() {
    Column({ space: 8 }) {
      Text('💡 快捷提问')
        .fontSize(12)
        .fontColor('#6B7280')
        .padding({ left: 4 });

      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.questions, (question: string, index: number) => {
          Text(question)
            .fontSize(12)
            .fontColor('#1A56DB')
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .backgroundColor('#EFF6FF')
            .borderRadius(16)
            .border({ width: 1, color: '#BFDBFE' })
            .margin({ right: 8, bottom: 8 })
            .onClick(() => {
              if (this.onQuestionClick) {
                this.onQuestionClick(question);
              }
            });
        }, (question: string, index: number) => `${index}`);
      };
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 });
  }
}

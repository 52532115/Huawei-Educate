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

/**
 * Lightweight Markdown rendering for AI replies. Parsing is deterministic
 * (indexOf only, no regex) to stay within ArkTS restrictions. Supported:
 * headings (#..######), fenced code blocks (```), unordered lists (-/*),
 * ordered lists (1.), bold (**text**), and inline code (`text`).
 */

export enum InlineKind {
  TEXT = 0,
  BOLD = 1,
  CODE = 2,
}

export class InlineSpan {
  text: string;
  kind: InlineKind;

  constructor(text: string, kind: InlineKind) {
    this.text = text;
    this.kind = kind;
  }
}

export enum BlockKind {
  PARAGRAPH = 0,
  HEADING = 1,
  CODE = 2,
  BULLET = 3,
  ORDERED = 4,
}

export class MarkdownBlock {
  kind: BlockKind;
  /** For HEADING: 1..6. For ORDERED: the item number. Otherwise 0. */
  level: number;
  lines: string[];

  constructor(kind: BlockKind, level: number, lines: string[]) {
    this.kind = kind;
    this.level = level;
    this.lines = lines;
  }
}

/**
 * Splits raw Markdown into typed blocks. Deterministic, no regex.
 */
export function parseMarkdown(source: string): MarkdownBlock[] {
  const lines = source.split('\n');
  const blocks: MarkdownBlock[] = [];
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    if (line.startsWith('```')) {
      const codeLines: string[] = [];
      i++;
      while (i < lines.length && !lines[i].startsWith('```')) {
        codeLines.push(lines[i]);
        i++;
      }
      if (i < lines.length) {
        i++; // skip closing fence
      }
      if (codeLines.length > 0) {
        blocks.push(new MarkdownBlock(BlockKind.CODE, 0, codeLines));
      }
      continue;
    }
    if (line.trim().length === 0) {
      i++;
      continue;
    }

    const hLevel = headingLevel(line);
    if (hLevel > 0) {
      const text = line.substring(hLevel).trim();
      blocks.push(new MarkdownBlock(BlockKind.HEADING, hLevel, [text]));
      i++;
      continue;
    }

    if (line.startsWith('- ') || line.startsWith('* ')) {
      const items: string[] = [];
      while (i < lines.length && (lines[i].startsWith('- ') || lines[i].startsWith('* '))) {
        items.push(lines[i].substring(2).trim());
        i++;
      }
      blocks.push(new MarkdownBlock(BlockKind.BULLET, 0, items));
      continue;
    }

    if (isOrderedItem(line)) {
      const items: string[] = [];
      while (i < lines.length && isOrderedItem(lines[i])) {
        items.push(stripOrderPrefix(lines[i]));
        i++;
      }
      blocks.push(new MarkdownBlock(BlockKind.ORDERED, 0, items));
      continue;
    }

    // Plain paragraph: collect until a blank line or any special line.
    const para: string[] = [];
    while (i < lines.length &&
      lines[i].trim().length > 0 &&
      !lines[i].startsWith('```') &&
      headingLevel(lines[i]) === 0 &&
      !lines[i].startsWith('- ') &&
      !lines[i].startsWith('* ') &&
      !isOrderedItem(lines[i])) {
      para.push(lines[i]);
      i++;
    }
    if (para.length > 0) {
      blocks.push(new MarkdownBlock(BlockKind.PARAGRAPH, 0, para));
    }
  }
  return blocks;
}

/**
 * Parses inline Markdown (**bold**, `code`) into spans. Deterministic, no regex.
 */
export function parseInline(text: string): InlineSpan[] {
  const spans: InlineSpan[] = [];
  let i = 0;
  let current = '';
  while (i < text.length) {
    if (text.startsWith('**', i)) {
      const close = text.indexOf('**', i + 2);
      if (close > i + 2) {
        if (current.length > 0) {
          spans.push(new InlineSpan(current, InlineKind.TEXT));
          current = '';
        }
        spans.push(new InlineSpan(text.substring(i + 2, close), InlineKind.BOLD));
        i = close + 2;
        continue;
      }
    }
    if (text.startsWith('`', i)) {
      const close = text.indexOf('`', i + 1);
      if (close > i + 1) {
        if (current.length > 0) {
          spans.push(new InlineSpan(current, InlineKind.TEXT));
          current = '';
        }
        spans.push(new InlineSpan(text.substring(i + 1, close), InlineKind.CODE));
        i = close + 1;
        continue;
      }
    }
    current += text.charAt(i);
    i++;
  }
  if (current.length > 0) {
    spans.push(new InlineSpan(current, InlineKind.TEXT));
  }
  if (spans.length === 0) {
    spans.push(new InlineSpan('', InlineKind.TEXT));
  }
  return spans;
}

/** Returns 1..6 for ATX headings, 0 otherwise. */
function headingLevel(line: string): number {
  const trimmed = line.trimStart();
  if (!trimmed.startsWith('#')) {
    return 0;
  }
  let count = 0;
  while (count < trimmed.length && trimmed.charAt(count) === '#') {
    count++;
  }
  if (count > 6) {
    return 0;
  }
  if (count >= trimmed.length || trimmed.charAt(count) === ' ') {
    return count;
  }
  return 0;
}

function isOrderedItem(line: string): boolean {
  const trimmed = line.trimStart();
  const dot = trimmed.indexOf('.');
  if (dot <= 0 || dot > 4) {
    return false;
  }
  const prefix = trimmed.substring(0, dot);
  for (let i = 0; i < prefix.length; i++) {
    const c = prefix.charAt(i);
    if (c < '0' || c > '9') {
      return false;
    }
  }
  return dot + 1 < trimmed.length && trimmed.charAt(dot + 1) === ' ';
}

function stripOrderPrefix(line: string): string {
  const trimmed = line.trimStart();
  const dot = trimmed.indexOf('.');
  return trimmed.substring(dot + 2).trim();
}

/** Renders one line's inline spans (**bold**, `code`) inside a single Text. */
@Builder
function InlineSpans(text: string, baseColor: string) {
  Text() {
    ForEach(parseInline(text), (span: InlineSpan) => {
      Span(span.text)
        .fontSize(span.kind === InlineKind.CODE ? 13 : 14)
        .fontWeight(span.kind === InlineKind.BOLD ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(span.kind === InlineKind.CODE ? '#C7254E' : baseColor)
        .backgroundColor(span.kind === InlineKind.CODE ? '#F3F4F6' : 'transparent');
    }, (span: InlineSpan) => `${span.kind}_${span.text.length}`);
  }
  .fontSize(14)
  .fontColor(baseColor)
  .lineHeight(22);
}

/**
 * Renders parsed Markdown blocks: headings, fenced code, bullet/ordered
 * lists, and paragraphs with inline bold/code.
 */
@Component
export struct MarkdownText {
  @Prop content: string;
  /**
   * Width in vp for the whole markdown column, supplied by the host bubble.
   * A definite number, not a percentage: inside a self-sizing bubble an
   * `'100%'` resolves against the constraint the parent hands down, which is
   * the full row width rather than the bubble's own — that is exactly how the
   * replies ended up rendering past the bubble's right edge.
   */
  @Prop contentWidth: number;

  build() {
    Column() {
      ForEach(parseMarkdown(this.content), (block: MarkdownBlock, index: number) => {
        if (block.kind === BlockKind.HEADING) {
          Text(block.lines[0])
            .fontSize(block.level === 1 ? 17 : (block.level === 2 ? 16 : 15))
            .fontWeight(FontWeight.Bold)
            .fontColor('#1F2937')
            // Bounded like every other branch: an unconstrained Text is measured
            // at its intrinsic width and widens the whole markdown column.
            .width('100%')
            .margin({ top: 6, bottom: 2 });
        } else if (block.kind === BlockKind.CODE) {
          Text(block.lines.join('\n'))
            .fontSize(13)
            .fontFamily('monospace')
            .fontColor('#374151')
            .backgroundColor('#F6F8FA')
            .borderRadius(8)
            .padding(10)
            .width('100%')
            .margin({ top: 4, bottom: 4 })
            .maxLines(999)
            // Code lines are often one long unbroken token; without this the
            // line cannot wrap and runs out of the bubble.
            .wordBreak(WordBreak.BREAK_ALL)
            .textOverflow({ overflow: TextOverflow.None });
        } else if (block.kind === BlockKind.BULLET) {
          Column({ space: 2 }) {
            ForEach(block.lines, (line: string) => {
              Row({ space: 6 }) {
                Text('•')
                  .fontSize(14)
                  .fontColor('#4B5563');
                Column() {
                  InlineSpans(line, '#333333');
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1);
              }
              .width('100%')
              .alignItems(VerticalAlign.Top);
            }, (line: string, li: number) => `${index}_${li}_${line.length}`);
          }
          .width('100%')
          .margin({ top: 2, bottom: 2 });
        } else if (block.kind === BlockKind.ORDERED) {
          Column({ space: 2 }) {
            ForEach(block.lines, (line: string, li: number) => {
              Row({ space: 6 }) {
                Text(`${li + 1}.`)
                  .fontSize(14)
                  .fontColor('#4B5563');
                Column() {
                  InlineSpans(line, '#333333');
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1);
              }
              .width('100%')
              .alignItems(VerticalAlign.Top);
            }, (line: string, li: number) => `${index}_${li}_${line.length}`);
          }
          .width('100%')
          .margin({ top: 2, bottom: 2 });
        } else {
          Column({ space: 2 }) {
            ForEach(block.lines, (line: string, li: number) => {
              Row() {
                // Bounded like the list branches: without layoutWeight the text
                // is measured at its intrinsic width and spills past the bubble.
                Column() {
                  InlineSpans(line, '#333333');
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1);
              }
              .width('100%')
              .alignItems(VerticalAlign.Top);
            }, (line: string, li: number) => `${index}_${li}_${line.length}`);
          }
          .width('100%')
          .margin({ top: 2, bottom: 2 });
        }
      }, (block: MarkdownBlock, index: number) => `${block.kind}_${index}_${block.lines.length}`);
    }
    // Width comes from the host, as a number. Two earlier revisions guessed here:
    // omitting it left the column measured at its children's intrinsic width (a
    // run of text the engine will not wrap widened the whole column), and
    // `.width('100%')` resolved against the parent's constraint — the full row —
    // rather than the bubble. Both ended with text outside the white bubble.
    .width(this.contentWidth)
    .alignItems(HorizontalAlign.Start);
  }
}

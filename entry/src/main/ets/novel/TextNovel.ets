import { util } from '@kit.ArkTS';

const MAX_CHAPTER_CHARS: number = 18000;
const MAX_CHAPTERS: number = 10000;
const MAX_BLOCK_CHARS: number = 360;

const CHINESE_HEADING: RegExp = /^第[ \t　]*[0-9０-９零〇○一二三四五六七八九十百千万亿两壹贰叁肆伍陆柒捌玖拾佰仟]+[ \t　]*[章节卷回话幕篇部集](?:[ \t　:：.·\-—]*.{0,52})$/;
const SPECIAL_HEADING: RegExp = /^(?:楔子|序章|引子|序言|终章|尾声|后记|番外)(?:[ \t　:：.·\-—].{0,52}|[一二三四五六七八九十0-9]{1,5})?$/;
const ENGLISH_HEADING: RegExp = /^(?:chapter|part)[ \t]+#?(?:[0-9]+|[ivxlcdm]+)(?:[ \t:.\-—].{0,52})?$/i;

export class TextChapter {
  public title: string;
  public text: string;

  constructor(title: string, text: string) {
    this.title = title;
    this.text = text;
  }
}

class Heading {
  public title: string;
  public start: number;
  public body: number;

  constructor(title: string, start: number, body: number) {
    this.title = title;
    this.start = start;
    this.body = body;
  }
}

export class ReaderBlock {
  public offset: number;
  public text: string;
  public newParagraph: boolean;
  public key: string;

  constructor(offset: number, text: string, newParagraph: boolean, key: string) {
    this.offset = offset;
    this.text = text;
    this.newParagraph = newParagraph;
    this.key = key;
  }
}

export function decodeText(bytes: Uint8Array, declaredEncoding: string = ''): string {
  if (bytes.length === 0) {
    return '';
  }

  let encoding: string = declaredEncoding.trim().toLowerCase();
  let start: number = 0;
  if (bytes.length >= 3 && bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf) {
    encoding = 'utf-8';
    start = 3;
  } else if (bytes.length >= 2 && bytes[0] === 0xff && bytes[1] === 0xfe) {
    encoding = 'utf-16le';
    start = 2;
  } else if (bytes.length >= 2 && bytes[0] === 0xfe && bytes[1] === 0xff) {
    encoding = 'utf-16be';
    start = 2;
  }
  if (encoding === 'gb2312' || encoding === 'gbk' || encoding === 'x-gbk') {
    encoding = 'gb18030';
  } else if (encoding === 'utf8') {
    encoding = 'utf-8';
  }

  const content: Uint8Array = bytes.subarray(start);
  if (encoding.length > 0) {
    try {
      return strictDecode(content, encoding);
    } catch {
      if (start > 0 || encoding === 'utf-16le' || encoding === 'utf-16be') {
        throw new Error('文件的 Unicode 编码不完整');
      }
    }
  }
  try {
    return strictDecode(content, 'utf-8');
  } catch {
    try {
      return strictDecode(content, 'gb18030');
    } catch {
      throw new Error('无法识别文本编码。请使用 UTF-8、带 BOM 的 UTF-16 或 GB18030');
    }
  }
}

function strictDecode(bytes: Uint8Array, encoding: string): string {
  return util.TextDecoder.create(encoding, { fatal: true }).decodeToString(bytes);
}

function hasBinaryControls(content: string): boolean {
  const limit: number = Math.min(content.length, 12000);
  let controls: number = 0;
  for (let index: number = 0; index < limit; index++) {
    const code: number = content.charCodeAt(index);
    if (code < 0x20 && code !== 9 && code !== 10 && code !== 13 && code !== 12) {
      controls++;
    }
  }
  return controls > Math.max(3, limit * 0.03);
}

export function splitTextNovel(content: string): TextChapter[] {
  const text: string = content.replace(/\r\n?/g, '\n');
  if (hasBinaryControls(text)) {
    throw new Error('所选文件看起来不是文本小说');
  }
  if (text.trim().length === 0) {
    throw new Error('这份 TXT 没有可阅读的文字');
  }

  const headings: Heading[] = findHeadings(text);
  const chapters: TextChapter[] = [];
  if (headings.length === 0) {
    addChapter(chapters, '正文', text, true);
    return chapters;
  }

  const before: string = text.slice(0, headings[0].start).trim();
  if (before.length > 0) {
    addChapter(chapters, '卷首', before, false);
  }
  for (let index: number = 0; index < headings.length; index++) {
    const heading: Heading = headings[index];
    const end: number = index + 1 < headings.length ? headings[index + 1].start : text.length;
    addChapter(chapters, heading.title, text.slice(heading.body, end), false);
  }
  return chapters;
}

function findHeadings(text: string): Heading[] {
  const headings: Heading[] = [];
  let start: number = 0;
  while (start < text.length) {
    const newline: number = text.indexOf('\n', start);
    const end: number = newline < 0 ? text.length : newline;
    if (end - start <= 100) {
      const line: string = text.slice(start, end).trim();
      if (CHINESE_HEADING.test(line) || SPECIAL_HEADING.test(line) || ENGLISH_HEADING.test(line)) {
        headings.push(new Heading(line, start, Math.min(end + 1, text.length)));
        if (headings.length > MAX_CHAPTERS) {
          throw new Error('TXT 识别出的章节超过 10000 章');
        }
      }
    }
    start = end + 1;
  }
  return headings;
}

function addChapter(destination: TextChapter[], title: string, original: string, labelParts: boolean): void {
  const content: string = original.trim();
  let offset: number = 0;
  let part: number = 1;
  do {
    let end: number = Math.min(content.length, offset + MAX_CHAPTER_CHARS);
    if (end < content.length) {
      const breakAt: number = content.lastIndexOf('\n', end - 1);
      if (breakAt >= offset + MAX_CHAPTER_CHARS / 2) {
        end = breakAt + 1;
      } else {
        end = codePointBoundary(content, end);
      }
    }
    let partTitle: string = title;
    if (labelParts && content.length > MAX_CHAPTER_CHARS) {
      partTitle = title + ' ' + part;
    } else if (part > 1) {
      partTitle = title + ' · 续 ' + (part - 1);
    }
    destination.push(new TextChapter(partTitle, content.slice(offset, end).trim()));
    if (destination.length > MAX_CHAPTERS) {
      throw new Error('TXT 分段后的章节超过 10000 章');
    }
    offset = end;
    part++;
  } while (offset < content.length);
}

function codePointBoundary(text: string, index: number): number {
  const code: number = text.charCodeAt(index);
  return code >= 0xdc00 && code <= 0xdfff ? index - 1 : index;
}

export function makeReaderBlocks(text: string, chapterId: string): ReaderBlock[] {
  const blocks: ReaderBlock[] = [];
  let start: number = 0;
  while (start < text.length) {
    const newline: number = text.indexOf('\n', start);
    const end: number = newline < 0 ? text.length : newline;
    const line: string = text.slice(start, end).trim();
    let offset: number = 0;
    while (offset < line.length) {
      const next: number = codePointBoundary(line, Math.min(line.length, offset + MAX_BLOCK_CHARS));
      blocks.push(new ReaderBlock(start + offset, line.slice(offset, next), offset === 0, chapterId + ":" + (start + offset)));
      offset = next;
    }
    start = end + 1;
  }
  return blocks;
}

export function blockIndexForOffset(blocks: ReaderBlock[], offset: number): number {
  if (offset <= 0 || blocks.length === 0) {
    return 0;
  }
  let lower: number = 0;
  let upper: number = blocks.length;
  while (lower < upper) {
    const middle: number = Math.floor((lower + upper) / 2);
    if (blocks[middle].offset <= offset) {
      lower = middle + 1;
    } else {
      upper = middle;
    }
  }
  return Math.max(1, lower);
}

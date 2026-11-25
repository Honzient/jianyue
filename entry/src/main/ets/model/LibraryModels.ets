export enum BookKind {
  Local = 0,
  Online = 1
}

export class Book {
  public id: string;
  public identity: string;
  public kind: BookKind;
  public title: string;
  public author: string;
  public description: string;
  public sourceKey: string;
  public sourceName: string;
  public detailUrl: string;
  public tocUrl: string;
  public onShelf: boolean;
  public ruleValues: string;

  constructor(
    id: string,
    identity: string,
    kind: BookKind,
    title: string,
    author: string = '',
    description: string = '',
    sourceKey: string = '',
    sourceName: string = '',
    detailUrl: string = '',
    tocUrl: string = '',
    onShelf: boolean = false,
    ruleValues: string = ''
  ) {
    this.id = id;
    this.identity = identity;
    this.kind = kind;
    this.title = title;
    this.author = author;
    this.description = description;
    this.sourceKey = sourceKey;
    this.sourceName = sourceName;
    this.detailUrl = detailUrl;
    this.tocUrl = tocUrl;
    this.onShelf = onShelf;
    this.ruleValues = ruleValues;
  }
}

export class Chapter {
  public id: string;
  public bookId: string;
  public index: number;
  public title: string;
  public url: string;
  public byteOffset: number;
  public byteLength: number;

  constructor(
    id: string,
    bookId: string,
    index: number,
    title: string,
    url: string = '',
    byteOffset: number = 0,
    byteLength: number = 0
  ) {
    this.id = id;
    this.bookId = bookId;
    this.index = index;
    this.title = title;
    this.url = url;
    this.byteOffset = byteOffset;
    this.byteLength = byteLength;
  }
}

export class ReadPosition {
  public chapterId: string;
  public offset: number;

  constructor(chapterId: string = '', offset: number = 0) {
    this.chapterId = chapterId;
    this.offset = offset;
  }
}

export class ShelfItem {
  public book: Book;
  public chapterTitle: string;
  public chapterCount: number;
  public lastReadAt: number;

  constructor(
    book: Book,
    chapterTitle: string,
    chapterCount: number,
    lastReadAt: number
  ) {
    this.book = book;
    this.chapterTitle = chapterTitle;
    this.chapterCount = chapterCount;
    this.lastReadAt = lastReadAt;
  }

  caption(): string {
    return this.chapterTitle.length > 0 ? this.chapterTitle : this.chapterCount + ' 章';
  }
}

export class ReadingStyle {
  static readonly MIN_FONT: number = 14;
  static readonly MAX_FONT: number = 30;
  static readonly MIN_SPACING: number = 0;
  static readonly MAX_SPACING: number = 3;

  public fontSize: number;
  public spacing: number;

  public night: boolean;

  constructor(
    fontSize: number = 20,
    spacing: number = 1,
    night: boolean = false
  ) {
    this.night = night;
    this.fontSize = Math.max(ReadingStyle.MIN_FONT, Math.min(ReadingStyle.MAX_FONT, fontSize));
    this.spacing = Math.max(ReadingStyle.MIN_SPACING, Math.min(ReadingStyle.MAX_SPACING, spacing));
  }

  lineHeight(): number {
    return Math.round(this.fontSize * (1.45 + this.spacing * 0.17));
  }
}

export class OnlineListing {
  public sourceKey: string;
  public sourceName: string;
  public title: string;
  public author: string;
  public description: string;
  public detailUrl: string;
  public tocUrl: string;
  public ruleValues: string;

  constructor(
    sourceKey: string,
    sourceName: string,
    title: string,
    author: string,
    description: string,
    detailUrl: string,
    tocUrl: string = '',
    ruleValues: string = ''
  ) {
    this.sourceKey = sourceKey;
    this.sourceName = sourceName;
    this.title = title;
    this.author = author;
    this.description = description;
    this.detailUrl = detailUrl;
    this.tocUrl = tocUrl;
    this.ruleValues = ruleValues;
  }
}

export class OnlineChapter {
  public title: string;
  public url: string;

  constructor(title: string, url: string) {
    this.title = title;
    this.url = url;
  }
}

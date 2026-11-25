import { common } from '@kit.AbilityKit';
import { Book, BookKind, Chapter, ReadingStyle, ReadPosition } from '../model/LibraryModels';
import { chapterOrdinal, filterChapters } from '../novel/ChapterFilter';
import { ListFeed } from '../novel/ReaderData';
import { blockIndexForOffset, makeReaderBlocks, ReaderBlock } from '../novel/TextNovel';
import { loadChapterText, loadOnlineCatalog } from '../service/OnlineNovels';
import { RequestGroup } from '../source/SiteReader';
import { errorMessage, ReaderLibrary } from '../service/ReaderLibrary';
import { ActionText, PageHeader, StatusPanel } from '../ui/CommonViews';
import { INK, Palette, PAPER } from '../ui/Palette';
import { applyWindowColors } from '../ui/WindowColors';

enum ReaderPanel {
  None,
  Directory,
  Style
}

@Component
export struct ReaderPage {
  @Prop bookId: string = '';
  @Prop openDirectory: boolean = false;
  onExit: () => void = (): void => {};

  @State private title: string = '';
  @State private chapterTitle: string = '';
  @State private loading: boolean = true;
  @State private issue: string = '';
  @State private styleIssue: string = '';
  @State private style: ReadingStyle = new ReadingStyle();
  @State private panel: ReaderPanel = ReaderPanel.None;
  @State private chapterIndex: number = -1;
  @State private chapterCount: number = 0;
  @State private blockCount: number = 0;
  @State private directoryKeyword: string = '';
  @State private directoryMatches: number = 0;
  @State private savedChapterId: string = '';
  @State private savedChapterIndex: number = -1;

  private library?: ReaderLibrary;
  private book?: Book;
  private chapters: Chapter[] = [];
  private directory: ListFeed<Chapter> = new ListFeed<Chapter>();
  private blocks: ListFeed<ReaderBlock> = new ListFeed<ReaderBlock>();
  private scroller: Scroller = new Scroller();
  private directoryScroller: Scroller = new Scroller();
  private initialIndex: number = 0;
  private lastVisibleIndex: number = 0;
  private acceptScroll: boolean = false;
  private requestSerial: number = 0;
  private active: boolean = false;
  private exiting: boolean = false;
  private requestedOffset: number = 0;
  private loadedChapterId: string = '';
  private savedOffset: number = 0;
  private directoryScrollSerial: number = 0;
  private readingRequests: RequestGroup = new RequestGroup();

  aboutToAppear(): void {
    this.active = true;
    this.initialize();
  }

  aboutToDisappear(): void {
    this.active = false;
    this.requestSerial++;
    this.readingRequests.cancel();
    applyWindowColors(PAPER);
    this.library?.flushPosition();
  }

  private palette(): Palette {
    return this.style.night ? INK : PAPER;
  }

  private async initialize(): Promise<void> {
    this.loading = true;
    this.issue = '';
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const library: ReaderLibrary = await ReaderLibrary.get(context);
      const book: Book | undefined = await library.store.bookById(this.bookId);
      if (book === undefined) {
        throw new Error('这本小说已经不在本机');
      }
      if (!this.active) {
        return;
      }
      this.library = library;
      this.book = book;
      this.title = book.title;
      this.style = await library.store.readingStyle();
      if (!this.active) {
        return;
      }
      applyWindowColors(this.palette());
      this.chapters = await library.store.chapters(book.id);
      if (this.chapters.length === 0 && book.kind === BookKind.Online) {
        this.chapters = await loadOnlineCatalog(library, book, this.readingRequests);
      }
      if (!this.active) {
        return;
      }
      this.directory.replace(this.chapters);
      this.directoryKeyword = '';
      this.directoryMatches = this.chapters.length;
      this.chapterCount = this.chapters.length;
      if (this.chapterCount === 0) {
        throw new Error('这本小说还没有可用的章节');
      }
      const position: ReadPosition = await library.store.position(book.id);
      if (!this.active) {
        return;
      }
      const savedIndex: number = this.chapters.findIndex((chapter: Chapter): boolean =>
        chapter.id === position.chapterId);
      this.savedChapterId = savedIndex >= 0 ? position.chapterId : '';
      this.savedChapterIndex = savedIndex;
      this.savedOffset = savedIndex >= 0 ? position.offset : 0;
      if (this.openDirectory) {
        // The saved position is read above but never written back: this path only previews the
        // directory until the reader taps a chapter.
        this.loading = false;
        this.panel = ReaderPanel.Directory;
        this.scrollDirectoryTo(this.directoryAnchorStart());
        return;
      }
      const index: number = Math.max(0, savedIndex);
      const offset: number = savedIndex >= 0 ? position.offset : 0;
      await this.showChapter(index, offset);
    } catch (error) {
      if (this.active) {
        this.issue = errorMessage(error as Error, '打开小说失败');
        this.loading = false;
      }
    }
  }

  private async showChapter(index: number, offset: number = 0): Promise<void> {
    const library: ReaderLibrary | undefined = this.library;
    const book: Book | undefined = this.book;
    if (!this.active || library === undefined || book === undefined || index < 0 || index >= this.chapters.length) {
      return;
    }

    const chapter: Chapter = this.chapters[index];
    const request: number = ++this.requestSerial;
    this.readingRequests.cancel();
    const requests: RequestGroup = new RequestGroup();
    this.readingRequests = requests;
    this.requestedOffset = offset;
    this.acceptScroll = false;
    this.loading = true;
    this.issue = '';
    this.chapterIndex = index;
    this.chapterTitle = chapter.title;
    try {
      // Persist the previous chapter's pending debounce before replacing it with the target jump.
      await library.flushPosition();
      const nextUrl: string = index + 1 < this.chapters.length ? this.chapters[index + 1].url : '';
      const text: string = await loadChapterText(library, book, chapter, nextUrl, requests);
      if (!this.active || request !== this.requestSerial) {
        return;
      }

      const blocks: ReaderBlock[] = makeReaderBlocks(text, chapter.id);
      const initialIndex: number = blockIndexForOffset(blocks, offset);
      this.blocks.replace(blocks);
      this.blockCount = blocks.length;
      this.loadedChapterId = chapter.id;
      this.initialIndex = initialIndex;
      this.lastVisibleIndex = initialIndex;
      this.panel = ReaderPanel.None;
      this.loading = false;
      this.restoreFirstIndex();
      // Every successful load records the exact requested offset; this covers the first open,
      // reopening the app, a normal chapter jump and a retry after a failed jump. Only the
      // direct-directory preview returns before this point and therefore stays read-only.
      const targetOffset: number = Math.max(0, Math.min(offset, text.length));
      library.stagePosition(book.id, chapter.id, targetOffset);
    } catch (error) {
      if (this.active && request === this.requestSerial) {
        this.loadedChapterId = '';
        this.issue = errorMessage(error as Error, '读取章节失败');
        this.loading = false;
      }
    }
  }

  private restoreFirstIndex(): void {
    if (this.acceptScroll || this.loading || this.issue.length > 0) {
      return;
    }
    const current: number = this.requestSerial;
    setTimeout((): void => {
      if (!this.active || current !== this.requestSerial || this.loading || this.acceptScroll) {
        return;
      }
      this.scroller.scrollToIndex(this.initialIndex, false, ScrollAlign.START);
      this.acceptScroll = true;
    }, 45);
  }

  private rememberVisible(first: number): void {
    // Position writes from scrolling require a loaded body, a closed panel and the chapter id
    // that the currently shown block list actually belongs to.
    if (!this.acceptScroll || this.panel !== ReaderPanel.None || this.loading ||
      this.chapterIndex < 0 || first < 0 || first === this.lastVisibleIndex) {
      return;
    }
    const chapterId: string = this.loadedChapterId;
    if (chapterId.length === 0) {
      return;
    }
    const itemCount: number = this.blockCount + 2;
    if (first >= itemCount) {
      return;
    }
    const index: number = this.blockCount > 0 ? Math.min(first, this.blockCount) : 0;
    const offset: number = index > 0 ? this.blocks.getData(index - 1).offset : 0;
    this.lastVisibleIndex = first;
    this.library?.stagePosition(this.bookId, chapterId, offset);
  }

  private hasDirectoryKeyword(): boolean {
    return this.directoryKeyword.trim().length > 0;
  }

  private directoryAnchorStart(): number {
    const anchor: number = this.chapterIndex >= 0 ? this.chapterIndex : this.savedChapterIndex;
    return Math.max(0, anchor - 2);
  }

  private directoryStartIndex(): number {
    return this.hasDirectoryKeyword() ? 0 : this.directoryAnchorStart();
  }

  private openDirectoryPanel(): void {
    if (this.chapters.length === 0) {
      return;
    }
    // Opening or closing the directory is not a reading action: no position is staged here.
    this.directoryKeyword = '';
    const matches: Chapter[] = filterChapters(this.chapters, '');
    this.directoryMatches = matches.length;
    this.directory.replace(matches);
    this.panel = ReaderPanel.Directory;
    this.scrollDirectoryTo(this.directoryAnchorStart());
  }

  private applyDirectoryKeyword(value: string): void {
    // Filtering only reloads the virtual list; the saved reading position stays untouched.
    // Invalidate pending scroll callbacks first, including when the result is empty.
    this.invalidateDirectoryScroll();
    this.directoryKeyword = value;
    const matches: Chapter[] = filterChapters(this.chapters, value);
    this.directoryMatches = matches.length;
    this.directory.replace(matches);
    if (matches.length > 0) {
      this.scrollDirectoryTo(this.directoryStartIndex());
    }
  }

  private invalidateDirectoryScroll(): void {
    this.directoryScrollSerial++;
  }

  private scrollDirectoryTo(index: number): void {
    const serial: number = ++this.directoryScrollSerial;
    setTimeout((): void => this.tryScrollDirectory(index, 0, serial), 40);
  }

  private tryScrollDirectory(index: number, attempt: number, serial: number): void {
    // Opening, filtering, clearing or closing the directory supersedes older delayed callbacks.
    if (!this.active || this.panel !== ReaderPanel.Directory || serial !== this.directoryScrollSerial) {
      return;
    }
    const count: number = this.directory.totalCount();
    if (count <= 0) {
      return;
    }
    const target: number = Math.max(0, Math.min(index, count - 1));
    try {
      this.directoryScroller.scrollToIndex(target, false, ScrollAlign.START);
    } catch {
      // The virtual list may still be laying out right after the panel opened or filtered.
      if (attempt < 2) {
        setTimeout((): void => this.tryScrollDirectory(target, attempt + 1, serial), 80);
      }
    }
  }

  private isDirectoryAnchor(chapter: Chapter): boolean {
    if (chapter.index === this.chapterIndex) {
      return true;
    }
    return this.chapterIndex < 0 && chapter.id === this.savedChapterId;
  }

  private selectChapter(chapter: Chapter): void {
    this.panel = ReaderPanel.None;
    const bodyMissing: boolean = this.loadedChapterId.length === 0;
    if (bodyMissing && chapter.id === this.savedChapterId) {
      // Tapping the saved chapter before the body loaded restores the saved text offset.
      this.showChapter(chapter.index, this.savedOffset);
      return;
    }
    if (chapter.index !== this.chapterIndex || this.issue.length > 0 || bodyMissing) {
      this.showChapter(chapter.index, 0);
    }
  }

  private async leaveReader(): Promise<void> {
    if (this.exiting) {
      return;
    }
    this.exiting = true;
    try {
      await this.library?.flushPosition();
    } finally {
      this.onExit();
    }
  }

  private async exitReader(): Promise<void> {
    if (this.exiting) {
      return;
    }
    if (this.panel !== ReaderPanel.None) {
      this.closePanel();
      return;
    }
    await this.leaveReader();
  }

  private closePanel(): void {
    const previous: ReaderPanel = this.panel;
    if (previous === ReaderPanel.Directory) {
      // Closing the directory supersedes any delayed scroll callback scheduled by this panel.
      this.invalidateDirectoryScroll();
      if (this.chapterIndex < 0) {
        // Entering from the detail page only shows the directory: closing it without a chapter tap
        // leaves the reader, and the directory overlay stays up so no empty body is shown.
        this.leaveReader();
        return;
      }
    }
    this.panel = ReaderPanel.None;
    if (previous === ReaderPanel.Style && !this.loading && this.issue.length === 0) {
      this.initialIndex = this.lastVisibleIndex;
      this.acceptScroll = false;
      this.restoreFirstIndex();
    }
  }

  private async updateStyle(font: number, spacing: number, night: boolean): Promise<void> {
    const style: ReadingStyle = new ReadingStyle(font, spacing, night);
    this.style = style;
    applyWindowColors(this.palette());
    this.styleIssue = '';
    try {
      await this.library?.store.saveReadingStyle(style);
    } catch (error) {
      this.styleIssue = errorMessage(error as Error, '保存阅读设置失败');
    }
  }

  private retry(): void {
    if (this.chapterIndex >= 0) {
      this.showChapter(this.chapterIndex, this.requestedOffset);
    } else {
      this.initialize();
    }
  }

  @Builder
  private chapterText(block: ReaderBlock) {
    Row() {
      Text(block.text)
        .width('100%')
        .constraintSize({ maxWidth: 660 })
        .fontSize(this.style.fontSize)
        .fontColor(this.palette().ink)
        .lineHeight(this.style.lineHeight())
        .textIndent(block.newParagraph ? this.style.fontSize * 2 : 0)
        .fontWeight(FontWeight.Regular)
        .wordBreak(WordBreak.BREAK_WORD)
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ left: 23, right: 23, top: 0, bottom: block.newParagraph ? 10 : 3 })
  }

  @Builder
  private readingBody() {
    List({ scroller: this.scroller, initialIndex: this.initialIndex }) {
      ListItem() {
        Row() {
          Column({ space: 10 }) {
            Text((this.chapterIndex + 1) + ' / ' + this.chapterCount)
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().accent)
            Text(this.chapterTitle)
              .id('chapter-title')
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.palette().ink)
              .lineHeight(36)
          }
          .width('100%')
          .constraintSize({ maxWidth: 660 })
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ left: 23, right: 23, top: 25, bottom: 23 })
      }

      LazyForEach(this.blocks, (block: ReaderBlock) => {
        ListItem() {
          this.chapterText(block)
        }
      }, (block: ReaderBlock) => block.key)

      ListItem() {
        Text(this.blockCount === 0 ? '本章没有正文' : '本章完')
          .fontSize(13)
          .fontColor(this.palette().muted)
          .textAlign(TextAlign.Center)
          .width('100%')
          .padding({ top: 18, bottom: 34 })
      }
    }
    .id('reading-body')
    .width('100%')
    .layoutWeight(1)
    .cachedCount(5)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.None)
    .onAreaChange(() => this.restoreFirstIndex())
    .onScrollIndex((first: number) => this.rememberVisible(first))
    .onScrollStop(() => this.library?.flushPosition())
  }

  @Builder
  private readingControls() {
    Row({ space: 8 }) {
      ActionText({ title: '上一章', actionId: 'chapter-prev', tint: this.palette().surface,
        ink: this.palette().ink, canClick: this.chapterIndex > 0 && !this.loading,
        onActivate: () => this.showChapter(this.chapterIndex - 1) })
      Blank()
      ActionText({ title: 'Aa', actionId: 'reader-style', tint: this.palette().accentSoft,
        ink: this.palette().accent, onActivate: () => {
          this.styleIssue = '';
          this.panel = ReaderPanel.Style;
        } })
      Blank()
      ActionText({ title: '下一章', actionId: 'chapter-next', tint: this.palette().surface,
        ink: this.palette().ink, canClick: this.chapterIndex >= 0 && this.chapterIndex + 1 < this.chapterCount &&
          !this.loading, onActivate: () => this.showChapter(this.chapterIndex + 1) })
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 7, bottom: 10 })
    .backgroundColor(this.palette().paper)
  }

  @Builder
  private directoryKeywordRow() {
    Row({ space: 8 }) {
      TextInput({ text: this.directoryKeyword, placeholder: '输入章节名或章序筛选' })
        .id('directory-keyword')
        .layoutWeight(1)
        .height(44)
        .fontSize(15)
        .fontColor(this.palette().ink)
        .placeholderColor(this.palette().muted)
        .placeholderFont({ size: 15 })
        .backgroundColor(this.palette().surface)
        .borderRadius(12)
        .padding({ left: 12, right: 12 })
        .onChange((value: string) => this.applyDirectoryKeyword(value))
      if (this.hasDirectoryKeyword()) {
        ActionText({ title: '清除', actionId: 'directory-clear-keyword', tint: this.palette().surface,
          ink: this.palette().accent, onActivate: () => this.applyDirectoryKeyword('') })
      }
    }
    .width('100%')
    .constraintSize({ maxWidth: 700 })
    .padding({ left: 18, right: 18 })
  }

  @Builder
  private directoryChapterRow(chapter: Chapter) {
    Row({ space: 10 }) {
      Text(chapterOrdinal(chapter).toString())
        .width(35)
        .fontSize(13)
        .fontColor(this.palette().muted)
      Text(chapter.title)
        .fontSize(16)
        .fontWeight(chapter.index === this.chapterIndex ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(chapter.index === this.chapterIndex ? this.palette().accent : this.palette().ink)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      if (chapter.index === this.chapterIndex) {
        Text('当前').fontSize(12).fontColor(this.palette().accent)
      } else if (this.chapterIndex < 0 && chapter.id === this.savedChapterId) {
        Text('上次读到')
          .id('directory-current')
          .fontSize(12)
          .fontColor(this.palette().accent)
      }
    }
    .width('100%')
    .constraintSize({ minHeight: 53 })
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor(this.isDirectoryAnchor(chapter) ? this.palette().accentSoft : this.palette().surface)
    .borderRadius(12)
    .id('directory-chapter-' + chapter.index)
    .onClick(() => this.selectChapter(chapter))
  }

  @Builder
  private directoryPanel() {
    Column({ space: 8 }) {
      PageHeader({
        title: '章节目录', detail: '共 ' + this.chapterCount + ' 章',
        palette: this.palette(), onBack: () => this.closePanel()
      })
      this.directoryKeywordRow()
      if (this.hasDirectoryKeyword()) {
        Text('匹配 ' + this.directoryMatches + ' 章')
          .id('directory-filtered-count')
          .width('100%')
          .constraintSize({ maxWidth: 700 })
          .fontSize(12)
          .fontColor(this.palette().muted)
          .padding({ left: 18, right: 18 })
      }
      if (this.hasDirectoryKeyword() && this.directoryMatches === 0) {
        Column({ space: 8 }) {
          Text('没有匹配的章节')
            .id('directory-empty')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().ink)
          Text('换个章节名或章序再试')
            .fontSize(13)
            .fontColor(this.palette().muted)
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ scroller: this.directoryScroller, initialIndex: this.directoryStartIndex(), space: 6 }) {
          LazyForEach(this.directory, (chapter: Chapter) => {
            ListItem() {
              this.directoryChapterRow(chapter)
            }
          }, (chapter: Chapter) => chapter.id)
        }
        .layoutWeight(1)
        .width('100%')
        .constraintSize({ maxWidth: 700 })
        .cachedCount(8)
        .padding({ left: 18, right: 18, bottom: 12 })
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.None)
      }
    }
    .id('directory-panel')
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette().paper)
  }

  @Builder
  private styleControls(label: string, value: string, minusId: string, plusId: string,
    canReduce: boolean, canIncrease: boolean, decrement: () => void, increment: () => void) {
    Row({ space: 12 }) {
      Text(label).layoutWeight(1).fontSize(15).fontColor(this.palette().ink).fontWeight(FontWeight.Medium)
      ActionText({ title: '−', actionId: minusId, canClick: canReduce, tint: this.palette().accentSoft,
        ink: this.palette().accent, onActivate: decrement })
      Text(value).width(34).textAlign(TextAlign.Center).fontSize(15).fontColor(this.palette().ink)
      ActionText({ title: '+', actionId: plusId, canClick: canIncrease, tint: this.palette().accentSoft,
        ink: this.palette().accent, onActivate: increment })
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
  }

  @Builder
  private stylePanel() {
    Column({ space: 14 }) {
      PageHeader({ title: '阅读设置', palette: this.palette(), onBack: () => this.closePanel() })
      Column({ space: 10 }) {
        this.styleControls('字号', this.style.fontSize.toString(), 'font-minus', 'font-plus',
          this.style.fontSize > ReadingStyle.MIN_FONT, this.style.fontSize < ReadingStyle.MAX_FONT,
          () => this.updateStyle(this.style.fontSize - 1, this.style.spacing, this.style.night),
          () => this.updateStyle(this.style.fontSize + 1, this.style.spacing, this.style.night))
        Divider().color(this.palette().line)
        this.styleControls('行距', (this.style.spacing + 1).toString(), 'spacing-minus', 'spacing-plus',
          this.style.spacing > ReadingStyle.MIN_SPACING, this.style.spacing < ReadingStyle.MAX_SPACING,
          () => this.updateStyle(this.style.fontSize, this.style.spacing - 1, this.style.night),
          () => this.updateStyle(this.style.fontSize, this.style.spacing + 1, this.style.night))
        Divider().color(this.palette().line)
        Row({ space: 10 }) {
          Text('主题').layoutWeight(1).fontSize(15).fontColor(this.palette().ink).fontWeight(FontWeight.Medium)
          ActionText({ title: '日间', actionId: 'theme-day',
            tint: this.style.night ? this.palette().surface : this.palette().accent,
            ink: this.style.night ? this.palette().ink : this.palette().onAccent,
            onActivate: () => this.updateStyle(this.style.fontSize, this.style.spacing, false) })
          ActionText({ title: '夜间', actionId: 'theme-night',
            tint: this.style.night ? this.palette().accent : this.palette().surface,
            ink: this.style.night ? this.palette().onAccent : this.palette().ink,
            onActivate: () => this.updateStyle(this.style.fontSize, this.style.spacing, true) })
        }
        .width('100%')
        .padding({ top: 10, bottom: 10 })
      }
      .width('100%')
      .constraintSize({ maxWidth: 560 })
      .padding(18)
      .backgroundColor(this.palette().surface)
      .borderRadius(18)
      if (this.styleIssue.length > 0) {
        Text(this.styleIssue).fontColor(this.palette().accent).fontSize(14).padding(18)
      }
    }
    .id('style-panel')
    .width('100%')
    .height('100%')
    .padding({ left: 12, right: 12 })
    .backgroundColor(this.palette().paper)
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Top }) {
        Column() {
          PageHeader({
            title: this.title.length > 0 ? this.title : '阅读',
            detail: this.chapterTitle,
            trailingAction: this.chapterCount > 0 ? '目录' : '',
            trailingId: 'reader-directory',
            palette: this.palette(),
            onBack: () => this.exitReader(),
            onTrailing: () => this.openDirectoryPanel()
          })
          Divider().color(this.palette().line)
          if (this.loading || this.issue.length > 0) {
            Column() {
              StatusPanel({ title: this.loading ? '正在打开章节' : '章节加载失败',
                detail: this.issue, palette: this.palette(), busy: this.loading,
                action: this.loading ? '' : '重试', actionId: 'retry-chapter', onActivate: () => this.retry() })
            }
            .width('100%')
            .layoutWeight(1)
            .padding(18)
            .justifyContent(FlexAlign.Center)
          } else {
            this.readingBody()
          }
          Divider().color(this.palette().line)
          this.readingControls()
        }
        .width('100%')
        .height('100%')
        .accessibilityLevel(this.panel === ReaderPanel.None ? 'auto' : 'no-hide-descendants')
        if (this.panel === ReaderPanel.Directory) {
          this.directoryPanel()
        } else if (this.panel === ReaderPanel.Style) {
          this.stylePanel()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.palette().paper)
    }
    .hideTitleBar(true)
    .onBackPressed((): boolean => {
      this.exitReader();
      return true;
    })
    .onWillHide(() => this.library?.flushPosition())
  }
}

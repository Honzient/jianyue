import { Book, BookKind, ShelfItem } from '../model/LibraryModels';
import { ActionText, BookMarkArt, StatusPanel } from './CommonViews';
import { PAPER } from './Palette';

@Component
export struct ShelfView {
  @Prop items: ShelfItem[] = [];
  @Prop loading: boolean = false;
  @Prop importing: boolean = false;
  @Prop problem: string = '';
  onOpen: (bookId: string) => void = (_bookId: string): void => {};
  onImport: () => void = (): void => {};
  onSearch: () => void = (): void => {};
  onReload: () => void = (): void => {};
  onRemoveBook: (book: Book) => void = (_book: Book): void => {};
  @State private organizing: boolean = false;
  @State private finding: boolean = false;
  @State private keyword: string = '';
  private inputController: TextInputController = new TextInputController();

  private subtitle(item: ShelfItem): string {
    const source: string = item.book.kind === BookKind.Local ? '本地 TXT' : item.book.sourceName;
    const label: string = item.book.author.length > 0 ? item.book.author + ' · ' + source : source;
    return label + ' · ' + item.caption();
  }

  private filterTerm(): string {
    return this.keyword.trim().toLowerCase();
  }

  private filtering(): boolean {
    return this.finding && this.filterTerm().length > 0;
  }

  private visibleItems(): ShelfItem[] {
    const term: string = this.filterTerm();
    if (term.length === 0) {
      return this.items;
    }
    return this.items.filter((item: ShelfItem): boolean => item.book.title.toLowerCase().includes(term));
  }

  private clearKeyword(): void {
    this.inputController.stopEditing();
    this.keyword = '';
  }

  private toggleFinding(): void {
    if (this.finding) {
      this.finding = false;
      this.clearKeyword();
      return;
    }
    this.finding = true;
    this.organizing = false;
  }

  private toggleOrganizing(): void {
    if (this.organizing) {
      this.organizing = false;
      return;
    }
    this.organizing = true;
    this.finding = false;
    this.clearKeyword();
  }

  @Builder
  private topBar() {
    Row({ space: 12 }) {
      Text('简阅')
        .fontColor(PAPER.ink)
        .fontSize(36)
        .fontWeight(FontWeight.Bold)
        .layoutWeight(1)
      ActionText({ title: this.importing ? '导入中…' : '导入 TXT', actionId: 'import-txt', canClick: !this.importing,
        onActivate: this.onImport })
    }
    .width('100%')
    .margin({ bottom: 18 })
  }

  @Builder
  private resumeCard(item: ShelfItem) {
    Row({ space: 16 }) {
      BookMarkArt({ artWidth: 66, artHeight: 90, tint: '#B76852' })
      Column({ space: 6 }) {
        Text('继续阅读')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FCE0D5')
        Text(item.book.title)
          .fontSize(23)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFF8EF')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(item.caption())
          .fontSize(13)
          .fontColor('#FCE0D5')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text('›').fontSize(28).fontColor('#FFF8EF')
    }
    .width('100%')
    .padding(18)
    .borderRadius(20)
    .backgroundColor('#853C32')
    .id('resume-book')
    .onClick(() => this.onOpen(item.book.id))
  }

  @Builder
  private bookRow(item: ShelfItem) {
    Row({ space: 13 }) {
      BookMarkArt({ tint: item.book.kind === BookKind.Local ? '#826550' : '#537169' })
      Column({ space: 6 }) {
        Text(item.book.title)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(PAPER.ink)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.subtitle(item))
          .fontSize(12)
          .fontColor(PAPER.muted)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      if (this.organizing) {
        ActionText({ title: '移出', actionId: 'remove-book-' + item.book.id,
          tint: PAPER.accentSoft, ink: PAPER.accent, onActivate: () => this.onRemoveBook(item.book) })
      } else {
        Text('›').fontSize(25).fontColor(PAPER.muted)
      }
    }
    .width('100%')
    .padding({ left: 12, right: 14, top: 12, bottom: 12 })
    .borderRadius(16)
    .backgroundColor(PAPER.surface)
    .border({ width: 1, color: PAPER.line })
    .id('book-' + item.book.id)
    .onClick(() => {
      if (!this.organizing) {
        this.onOpen(item.book.id);
      }
    })
  }

  @Builder
  private emptyShelf() {
    Column({ space: 13 }) {
      BookMarkArt({ artWidth: 70, artHeight: 92 })
      Text('书架还是空的')
        .fontColor(PAPER.ink)
        .fontSize(23)
        .fontWeight(FontWeight.Bold)
      Text('导入手机里的 TXT，或从已启用的书源找一本小说。')
        .fontColor(PAPER.muted)
        .fontSize(14)
        .lineHeight(22)
        .textAlign(TextAlign.Center)
      ActionText({ title: '去搜书', actionId: 'shelf-to-search', tint: PAPER.accentSoft,
        ink: PAPER.accent, onActivate: this.onSearch })
    }
    .width('100%')
    .padding({ top: 34, bottom: 30, left: 22, right: 22 })
    .backgroundColor(PAPER.surface)
    .borderRadius(20)
    .border({ width: 1, color: PAPER.line })
  }

  @Builder
  private findBar() {
    Row({ space: 10 }) {
      TextInput({ text: this.keyword, placeholder: '按书名查找', controller: this.inputController })
        .id('shelf-keyword')
        .layoutWeight(1)
        .height(44)
        .borderRadius(13)
        .backgroundColor(PAPER.surface)
        .border({ width: 1, color: PAPER.line })
        .fontColor(PAPER.ink)
        .placeholderColor(PAPER.muted)
        .enterKeyType(EnterKeyType.Search)
        .maxLength(80)
        .onChange((text: string) => { this.keyword = text; })
        .onSubmit(() => this.inputController.stopEditing())
      if (this.keyword.length > 0) {
        ActionText({ title: '清除', actionId: 'shelf-clear-keyword', tint: PAPER.surface, ink: PAPER.accent,
          onActivate: () => this.clearKeyword() })
      }
    }
    .width('100%')
    .padding({ top: 3, bottom: 3 })
  }

  @Builder
  private emptyResult() {
    Column({ space: 8 }) {
      Text('没有找到相关书名')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(PAPER.ink)
      Text('换一个书名关键词，或清除查找后查看全部书。')
        .fontSize(13)
        .lineHeight(20)
        .fontColor(PAPER.muted)
      ActionText({ title: '清除查找', actionId: 'shelf-clear-filter', tint: PAPER.accent,
        ink: PAPER.onAccent, onActivate: () => this.clearKeyword() })
    }
    .id('shelf-empty-result')
    .width('100%')
    .padding(14)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(PAPER.surface)
    .borderRadius(16)
    .border({ width: 1, color: PAPER.line })
  }

  build() {
    Scroll() {
      Column({ space: 11 }) {
        this.topBar()
        if (this.loading) {
          StatusPanel({ title: '正在打开书架', busy: true })
        } else if (this.problem.length > 0) {
          StatusPanel({ title: '书架加载失败', detail: this.problem, action: '重试', actionId: 'retry-shelf',
            onActivate: this.onReload })
        } else if (this.items.length === 0) {
          this.emptyShelf()
        } else {
          if (this.items[0].lastReadAt > 0 && !this.organizing && !this.filtering()) {
            ForEach(this.items.slice(0, 1), (item: ShelfItem) => {
              this.resumeCard(item)
            }, (item: ShelfItem) => item.book.id + ':' + item.lastReadAt + ':' + item.caption())
          }
          Row({ space: 8 }) {
            Text('书架')
              .fontSize(19)
              .fontWeight(FontWeight.Bold)
              .fontColor(PAPER.ink)
              .layoutWeight(1)
            if (this.filtering()) {
              Text('找到 ' + this.visibleItems().length + ' 本')
                .id('shelf-filtered-count')
                .fontSize(13)
                .fontColor(PAPER.muted)
            } else {
              Text(this.items.length + ' 本').fontSize(13).fontColor(PAPER.muted)
            }
            ActionText({ title: this.finding ? '收起' : '查找', actionId: 'shelf-find',
              tint: this.finding ? PAPER.accentSoft : PAPER.paper, ink: PAPER.accent,
              onActivate: () => this.toggleFinding() })
            ActionText({ title: this.organizing ? '完成' : '整理', actionId: 'organize-shelf',
              tint: PAPER.paper, ink: PAPER.accent, onActivate: () => this.toggleOrganizing() })
          }
          .width('100%')
          .padding({ top: 10, bottom: 3 })
          if (this.finding) {
            this.findBar()
          }
          if (this.filtering() && this.visibleItems().length === 0) {
            this.emptyResult()
          } else {
            ForEach(this.visibleItems(), (item: ShelfItem) => {
              this.bookRow(item)
            }, (item: ShelfItem) => item.book.id + ':' + item.lastReadAt + ':' + item.chapterCount)
          }
        }
      }
      .width('100%')
      .constraintSize({ maxWidth: 680 })
      .padding({ left: 22, right: 22, top: 18, bottom: 18 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
  }
}

import { common } from '@kit.AbilityKit';
import { Book, Chapter, OnlineListing } from '../model/LibraryModels';
import { fetchListing, loadOnlineCatalog } from '../service/OnlineNovels';
import { errorMessage, ReaderLibrary } from '../service/ReaderLibrary';
import { RequestGroup } from '../source/SiteReader';
import { ActionText, BookMarkArt, PageHeader } from '../ui/CommonViews';
import { PAPER } from '../ui/Palette';

@Component
export struct BookDetailPage {
  @Prop hit?: OnlineListing;
  onReadBook: (bookId: string, showDirectory: boolean) => void =
    (_bookId: string, _showDirectory: boolean): void => {};
  onShelfChange: () => void = (): void => {};
  onExit: () => void = (): void => {};

  @State private bookTitle: string = '';
  @State private author: string = '';
  @State private sourceName: string = '';
  @State private description: string = '';
  @State private loadedChapters: number = 0;
  @State private saved: boolean = false;
  @State private fetching: boolean = true;
  @State private requestedAction: string = '';
  @State private problem: string = '';
  private listing?: OnlineListing;
  private library?: ReaderLibrary;
  private requests: RequestGroup = new RequestGroup();

  aboutToAppear(): void {
    if (this.hit !== undefined) {
      this.apply(this.hit);
    }
    this.initialize();
  }

  aboutToDisappear(): void {
    this.requests.cancel();
  }

  private apply(listing: OnlineListing): void {
    this.listing = listing;
    this.bookTitle = listing.title;
    this.author = listing.author;
    this.sourceName = listing.sourceName;
    this.description = listing.description;
  }

  private async initialize(): Promise<void> {
    const hit: OnlineListing | undefined = this.hit;
    if (hit === undefined) {
      this.fetching = false;
      this.problem = '找不到这本小说的搜索结果';
      return;
    }
    this.fetching = true;
    this.problem = '';
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const library: ReaderLibrary = await ReaderLibrary.get(context);
      this.library = library;
      const saved: Book | undefined = await library.store.onlineBook(hit.sourceKey, hit.detailUrl);
      if (this.requests.isCanceled()) {
        return;
      }
      if (saved !== undefined) {
        this.saved = saved.onShelf;
        this.apply(new OnlineListing(saved.sourceKey, saved.sourceName, saved.title,
          saved.author, saved.description, saved.detailUrl, saved.tocUrl, saved.ruleValues));
        this.loadedChapters = (await library.store.chapters(saved.id)).length;
      }
      const information: OnlineListing = await fetchListing(library, hit, this.requests);
      if (!this.requests.isCanceled()) {
        this.apply(information);
      }
    } catch (error) {
      if (!this.requests.isCanceled()) {
        this.problem = '详情暂不可用 · ' + errorMessage(error as Error, '请重试');
      }
    } finally {
      this.fetching = false;
    }
  }

  private async changeShelf(): Promise<void> {
    const library: ReaderLibrary | undefined = this.library;
    const listing: OnlineListing | undefined = this.listing;
    if (!library || !listing || this.requestedAction.length > 0) {
      return;
    }
    this.requestedAction = 'shelf';
    this.problem = '';
    try {
      const book: Book = await library.store.saveOnline(listing);
      await library.store.setOnShelf(book.id, !book.onShelf);
      this.saved = !book.onShelf;
      this.onShelfChange();
    } catch (error) {
      this.problem = errorMessage(error as Error, '更新书架失败');
    } finally {
      this.requestedAction = '';
    }
  }

  private async prepareReader(showDirectory: boolean, forceRefresh: boolean = false): Promise<void> {
    const library: ReaderLibrary | undefined = this.library;
    const listing: OnlineListing | undefined = this.listing;
    if (!library || !listing || this.requestedAction.length > 0) {
      return;
    }
    this.requestedAction = showDirectory ? 'directory' : 'read';
    this.problem = '';
    try {
      const book: Book = await library.store.saveOnline(listing);
      let chapters: Chapter[] = await library.store.chapters(book.id);
      if (forceRefresh || chapters.length === 0) {
        chapters = await loadOnlineCatalog(library, book, this.requests);
      }
      if (!this.requests.isCanceled()) {
        this.loadedChapters = chapters.length;
        this.onShelfChange();
        this.onReadBook(book.id, showDirectory);
      }
    } catch (error) {
      if (!this.requests.isCanceled()) {
        this.problem = errorMessage(error as Error, '读取目录失败');
      }
    } finally {
      this.requestedAction = '';
    }
  }

  @Builder
  private bookSummary() {
    Row({ space: 17 }) {
      BookMarkArt({ artWidth: 76, artHeight: 105, tint: '#537169' })
      Column({ space: 8 }) {
        Text(this.bookTitle)
          .fontSize(27).fontWeight(FontWeight.Bold).fontColor(PAPER.ink).lineHeight(35)
          .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.author.length > 0) {
          Text(this.author).fontSize(14).fontColor(PAPER.muted).maxLines(2)
        }
        Text(this.sourceName).fontSize(13).fontColor(PAPER.accent).maxLines(2)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(17)
    .borderRadius(18)
    .backgroundColor(PAPER.surface)
    .border({ width: 1, color: PAPER.line })
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: '小说详情', onBack: this.onExit })
        Divider().color(PAPER.line)
        Scroll() {
          Column({ space: 14 }) {
            this.bookSummary()
            Row({ space: 9 }) {
              ActionText({ title: this.requestedAction === 'read' ? '正在打开…' : '开始阅读', actionId: 'detail-read',
                canClick: !this.fetching && this.requestedAction.length === 0,
                onActivate: () => this.prepareReader(false) })
              ActionText({ title: this.saved ? '移出书架' : '加入书架', actionId: 'detail-favorite',
                tint: PAPER.accentSoft, ink: PAPER.accent,
                canClick: !this.fetching && this.requestedAction.length === 0, onActivate: () => this.changeShelf() })
            }
            .width('100%')
            Row({ space: 9 }) {
              ActionText({ title: this.requestedAction === 'directory' ? '正在读取目录…' :
                (this.loadedChapters > 0 ? '目录 · ' + this.loadedChapters + ' 章' : '查看目录'),
                actionId: 'detail-directory', tint: PAPER.surface, ink: PAPER.accent,
                canClick: !this.fetching && this.requestedAction.length === 0,
                onActivate: () => this.prepareReader(true) })
              if (this.loadedChapters > 0) {
                ActionText({ title: '刷新目录', actionId: 'detail-refresh', tint: PAPER.paper,
                  ink: PAPER.muted, canClick: !this.fetching && this.requestedAction.length === 0,
                  onActivate: () => this.prepareReader(true, true) })
              }
            }
            .width('100%')
            if (this.fetching) {
              Row({ space: 8 }) {
                LoadingProgress().color(PAPER.accent).width(22).height(22)
                Text('读取详情中').fontSize(13).fontColor(PAPER.muted)
              }
            }
            if (this.problem.length > 0) {
              Text(this.problem).fontSize(14).lineHeight(21).fontColor(PAPER.accent)
              if (!this.fetching && this.requestedAction.length === 0) {
                ActionText({ title: '重试详情', actionId: 'detail-retry', tint: PAPER.accentSoft,
                  ink: PAPER.accent, onActivate: () => this.initialize() })
              }
            }
            if (this.description.length > 0) {
              Column({ space: 10 }) {
                Text('简介').fontSize(17).fontWeight(FontWeight.Bold).fontColor(PAPER.ink)
                Text(this.description).fontSize(15).lineHeight(24).fontColor(PAPER.muted)
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding(16)
              .borderRadius(15)
              .backgroundColor(PAPER.surface)
            }
          }
          .width('100%').constraintSize({ maxWidth: 680 })
          .padding({ left: 20, right: 20, top: 16, bottom: 24 })
          .alignItems(HorizontalAlign.Start)
        }
        .align(Alignment.Top)
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width('100%').height('100%').backgroundColor(PAPER.paper)
    }
    .hideTitleBar(true)
  }
}

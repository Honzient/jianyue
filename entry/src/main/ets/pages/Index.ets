import { common } from '@kit.AbilityKit';
import { Book, OnlineListing, ShelfItem } from '../model/LibraryModels';
import { LegadoBookSource, sourceEnabled, sourceKey } from '../model/LegadoBookSource';
import { assessSource, SourceAvailability } from '../source/BookSource';
import { errorMessage, ReaderLibrary } from '../service/ReaderLibrary';
import { pickDocument } from '../storage/NovelFiles';
import { ShelfView } from '../ui/ShelfView';
import { SearchView } from '../ui/SearchView';
import { SourcesView } from '../ui/SourcesView';
import { StatusPanel } from '../ui/CommonViews';
import { PAPER } from '../ui/Palette';
import { ReaderPage } from './ReaderPage';
import { BookDetailPage } from './BookDetailPage';
import { SourceTestPage } from './SourceTestPage';
import { SourceLogPage } from './SourceLogPage';

enum HomeTab {
  Shelf,
  Search,
  Sources
}

class ReaderRoute {
  bookId: string;
  showDirectory: boolean;

  constructor(bookId: string, showDirectory: boolean) {
    this.bookId = bookId;
    this.showDirectory = showDirectory;
  }
}

@Entry
@Component
struct Index {
  @State private shelf: ShelfItem[] = [];
  @State private loading: boolean = true;
  @State private importing: boolean = false;
  @State private issue: string = '';
  @State private selectedTab: HomeTab = HomeTab.Shelf;
  @State private sourceItems: SourceAvailability[] = [];
  @State private enabledSources: number = 0;
  @State private sourcesLoaded: boolean = false;
  @State private loadingSources: boolean = false;
  @State private sourceIssue: string = '';

  private navigation: NavPathStack = new NavPathStack();
  private shelfRequest: number = 0;
  private sourcesRequest: number = 0;

  aboutToAppear(): void {
    // 0.5.0：启动只加载本地书架。书源在首次进入“搜书”或“书源”页时按需读取并校验。
    this.reloadShelf();
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private async reloadShelf(): Promise<void> {
    const request: number = ++this.shelfRequest;
    try {
      const library: ReaderLibrary = await ReaderLibrary.get(this.context());
      await library.flushPosition();
      const items: ShelfItem[] = await library.store.listShelf();
      if (request === this.shelfRequest) {
        this.shelf = items;
        this.issue = '';
      }
    } catch (error) {
      if (request === this.shelfRequest) {
        this.issue = errorMessage(error as Error, '无法加载本地书架');
      }
    } finally {
      if (request === this.shelfRequest) {
        this.loading = false;
      }
    }
  }

  private async reloadSources(force: boolean = false): Promise<void> {
    if (this.loadingSources && !force) {
      return;
    }
    const request: number = ++this.sourcesRequest;
    this.loadingSources = true;
    try {
      const library: ReaderLibrary = await ReaderLibrary.get(this.context());
      const records: LegadoBookSource[] = await library.store.sources();
      if (request === this.sourcesRequest) {
        this.sourceItems = records.map((record: LegadoBookSource): SourceAvailability => assessSource(record));
        this.enabledSources = this.sourceItems.filter((entry: SourceAvailability): boolean =>
          entry.searchIssue.length === 0 && sourceEnabled(entry.source)).length;
        this.sourceIssue = '';
        this.sourcesLoaded = true;
      }
    } catch (error) {
      if (request === this.sourcesRequest) {
        this.sourceIssue = errorMessage(error as Error, '无法加载书源');
      }
    } finally {
      if (request === this.sourcesRequest) {
        this.loadingSources = false;
      }
    }
  }

  // 首次进入搜书/书源时按需加载；已加载或请求在途时不重复读取。
  private ensureSources(): void {
    if (this.sourcesLoaded || this.loadingSources) {
      return;
    }
    this.reloadSources();
  }

  // 所有书源相关入口（底部 tab、空书架“去搜书”、搜书页“去管理书源”）统一走这里。
  private selectTab(target: HomeTab): void {
    if (this.selectedTab === target) {
      return;
    }
    this.selectedTab = target;
    if (target === HomeTab.Search || target === HomeTab.Sources) {
      this.ensureSources();
    }
  }

  private async importTxt(): Promise<void> {
    if (this.importing) {
      return;
    }
    this.importing = true;
    try {
      const uri: string = await pickDocument(this.context(), 'TXT 小说', '.txt');
      if (uri.length === 0) {
        return;
      }
      const library: ReaderLibrary = await ReaderLibrary.get(this.context());
      const book: Book = await library.importText(uri);
      await this.reloadShelf();
      this.read(book.id);
    } catch (error) {
      this.getUIContext().getPromptAction().showToast({
        message: errorMessage(error as Error, 'TXT 导入失败')
      });
    } finally {
      this.importing = false;
    }
  }

  private async removeFromShelf(book: Book): Promise<void> {
    try {
      const choice = await this.getUIContext().getPromptAction().showDialog({
        title: '移出书架',
        message: '移出《' + book.title + '》？以后再次加入时可继续原来的进度。',
        buttons: [{ text: '取消', color: PAPER.muted }, { text: '移出', color: PAPER.accent }]
      });
      if (choice.index === 1) {
        const library: ReaderLibrary = await ReaderLibrary.get(this.context());
        await library.store.setOnShelf(book.id, false);
        await this.reloadShelf();
      }
    } catch (error) {
      this.getUIContext().getPromptAction().showToast({
        message: errorMessage(error as Error, '移出书架失败')
      });
    }
  }

  private read(bookId: string, showDirectory: boolean = false): void {
    this.navigation.pushPathByName('Reader', new ReaderRoute(bookId, showDirectory), () => {
      this.reloadShelf();
    });
  }

  private showBook(item: OnlineListing): void {
    this.navigation.pushPathByName('BookDetails', item, () => {
      this.reloadShelf();
    });
  }

  private showTest(key: string): void {
    const entry: SourceAvailability | undefined = this.sourceItems.find((item: SourceAvailability) =>
      sourceKey(item.source) === key);
    if (entry !== undefined) {
      this.navigation.pushPathByName('SourceTest', entry.source);
    }
  }

  @Builder
  private destinations(name: string, parameter: Object) {
    if (name === 'Reader') {
      ReaderPage({
        bookId: (parameter as ReaderRoute).bookId,
        openDirectory: (parameter as ReaderRoute).showDirectory,
        onExit: () => {
          this.navigation.pop();
          this.reloadShelf();
        }
      })
    } else if (name === 'BookDetails') {
      BookDetailPage({
        hit: parameter as OnlineListing,
        onReadBook: (bookId: string, showDirectory: boolean) => this.read(bookId, showDirectory),
        onShelfChange: () => this.reloadShelf(),
        onExit: () => { this.navigation.pop(); }
      })
    } else if (name === 'SourceTest') {
      SourceTestPage({
        sourceItem: parameter as LegadoBookSource,
        onExit: () => { this.navigation.pop(); }
      })
    } else if (name === 'SourceLog') {
      SourceLogPage({ onExit: () => { this.navigation.pop(); } })
    }
  }

  @Builder
  private tabButton(text: string, name: string, target: HomeTab) {
    Button(text, { type: ButtonType.Normal })
      .id(name)
      .layoutWeight(1)
      .height(44)
      .borderRadius(13)
      .fontSize(15)
      .fontWeight(this.selectedTab === target ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.selectedTab === target ? PAPER.accent : PAPER.muted)
      .backgroundColor(this.selectedTab === target ? PAPER.accentSoft : PAPER.surface)
      .onClick(() => this.selectTab(target))
  }

  @Builder
  private sourcesGate() {
    Column() {
      if (this.loadingSources || this.sourceIssue.length === 0) {
        StatusPanel({ title: '正在加载书源', busy: true })
      } else {
        StatusPanel({
          title: '书源加载失败',
          detail: this.sourceIssue,
          action: '重试',
          actionId: 'sources-loading-retry',
          onActivate: () => { this.reloadSources(); }
        })
      }
    }
    .id('sources-loading')
    .width('100%')
    .height('100%')
    .padding({ left: 22, right: 22, top: 18 })
    .backgroundColor(PAPER.paper)
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Navigation(this.navigation) {
      Column() {
        Stack({ alignContent: Alignment.Top }) {
          ShelfView({
            items: this.shelf,
            loading: this.loading,
            importing: this.importing,
            problem: this.issue,
            onOpen: (bookId: string) => this.read(bookId),
            onImport: () => this.importTxt(),
            onSearch: () => { this.selectTab(HomeTab.Search); },
            onReload: () => this.reloadShelf(),
            onRemoveBook: (book: Book) => this.removeFromShelf(book)
          })
          .visibility(this.selectedTab === HomeTab.Shelf ? Visibility.Visible : Visibility.None)
          SearchView({
            enabledSources: this.enabledSources,
            onOpenBook: (item: OnlineListing) => this.showBook(item),
            onManageSources: () => { this.selectTab(HomeTab.Sources); }
          })
          .visibility(this.selectedTab === HomeTab.Search && this.sourcesLoaded
            ? Visibility.Visible : Visibility.None)
          SourcesView({
            entries: this.sourceItems,
            enabledCount: this.enabledSources,
            loading: this.loadingSources,
            loadIssue: this.sourceIssue,
            onChangeSources: () => { this.reloadSources(true); },
            onOpenLog: () => this.navigation.pushPathByName('SourceLog', ''),
            onTestSource: (key: string) => this.showTest(key)
          })
          .visibility(this.selectedTab === HomeTab.Sources ? Visibility.Visible : Visibility.None)
          if (this.selectedTab === HomeTab.Search && !this.sourcesLoaded) {
            this.sourcesGate()
          }
        }
        .width('100%')
        .layoutWeight(1)
        Divider().color(PAPER.line)
        Row({ space: 6 }) {
          this.tabButton('书架', 'tab-shelf', HomeTab.Shelf)
          this.tabButton('搜书', 'tab-search', HomeTab.Search)
          this.tabButton('书源', 'tab-sources', HomeTab.Sources)
        }
        .width('100%')
        .constraintSize({ maxWidth: 700 })
        .padding({ left: 16, right: 16, top: 7, bottom: 9 })
        .backgroundColor(PAPER.surface)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(PAPER.paper)
    }
    .navDestination(this.destinations)
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .width('100%')
    .height('100%')
    .backgroundColor(PAPER.paper)
  }
}

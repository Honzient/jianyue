import { common } from '@kit.AbilityKit';
import { OnlineListing } from '../model/LibraryModels';
import { BookSource } from '../source/BookSource';
import { searchSources, searchTargets, SearchOutcome } from '../service/OnlineNovels';
import { errorMessage, ReaderLibrary } from '../service/ReaderLibrary';
import { RequestGroup } from '../source/SiteReader';
import { ActionText, BookMarkArt, StatusPanel } from './CommonViews';
import { PAPER } from './Palette';

const LIMIT: number = 180;

@Component
export struct SearchView {
  @Prop enabledSources: number = 0;
  onOpenBook: (item: OnlineListing) => void = (_item: OnlineListing): void => {};
  onManageSources: () => void = (): void => {};

  @State private keyword: string = '';
  @State private query: string = '';
  @State private results: OnlineListing[] = [];
  @State private failures: SearchOutcome[] = [];
  @State private searching: boolean = false;
  @State private showFailures: boolean = false;
  @State private message: string = '';
  @State private total: number = 0;
  @State private checked: number = 0;
  @State private limited: boolean = false;
  private inputController: TextInputController = new TextInputController();
  private request?: RequestGroup;

  aboutToDisappear(): void {
    this.request?.cancel();
  }

  private async search(): Promise<void> {
    const keyword: string = this.keyword.trim();
    if (keyword.length === 0) {
      return;
    }
    this.request?.cancel();
    const request: RequestGroup = new RequestGroup();
    this.request = request;
    this.inputController.stopEditing();
    this.query = keyword;
    this.searching = true;
    this.showFailures = false;
    this.results = [];
    this.failures = [];
    this.total = 0;
    this.checked = 0;
    this.limited = false;
    this.message = '';

    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const library: ReaderLibrary = await ReaderLibrary.get(context);
      const enabled: BookSource[] = searchTargets(await library.store.sources(), library.sourceLog, request.id);
      if (request.isCanceled()) {
        return;
      }
      this.total = enabled.length;
      if (this.total === 0) {
        this.message = '没有已启用且可搜索的书源';
        return;
      }
      await searchSources(enabled, keyword, request, library.sourceLog, (outcome: SearchOutcome): void => {
        this.checked++;
        if (outcome.problem.length > 0) {
          this.failures = this.failures.concat([outcome]);
        } else if (outcome.results.length > 0) {
          const available: number = LIMIT - this.results.length;
          this.limited = this.limited || outcome.results.length > available;
          this.results = this.results.concat(outcome.results.slice(0, available));
        }
      });
    } catch (error) {
      if (!request.isCanceled()) {
        this.message = errorMessage(error as Error, '搜索无法完成');
      }
    } finally {
      if (request === this.request) {
        this.searching = false;
      }
    }
  }

  private cancel(): void {
    this.request?.cancel();
    this.searching = false;
    this.message = '搜索已停止';
  }

  @Builder
  private resultCard(item: OnlineListing) {
    Row({ space: 13 }) {
      BookMarkArt({ tint: '#537169' })
      Column({ space: 5 }) {
        Text(item.title)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(PAPER.ink)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(item.author.length > 0 ? item.author + ' · ' + item.sourceName : item.sourceName)
          .fontSize(12)
          .fontColor(PAPER.muted)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (item.description.length > 0) {
          Text(item.description)
            .fontSize(13)
            .lineHeight(19)
            .fontColor(PAPER.muted)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Text('›').fontSize(25).fontColor(PAPER.muted)
    }
    .width('100%')
    .padding(13)
    .backgroundColor(PAPER.surface)
    .borderRadius(16)
    .border({ width: 1, color: PAPER.line })
    .onClick(() => this.onOpenBook(item))
  }

  @Builder
  private searchStatus() {
    Row({ space: 9 }) {
      if (this.searching) {
        LoadingProgress().color(PAPER.accent).width(23).height(23)
      }
      Text(this.searching ? '正在搜索 ' + this.checked + ' / ' + this.total :
        this.results.length + ' 本' + (this.limited ? ' · 已达显示上限' : ''))
        .fontSize(13)
        .fontColor(PAPER.muted)
        .layoutWeight(1)
        .id('search-status')
      if (this.searching) {
        ActionText({ title: '停止', actionId: 'cancel-search', tint: PAPER.accentSoft,
          ink: PAPER.accent, onActivate: () => this.cancel() })
      } else if (this.failures.length > 0) {
        ActionText({ title: this.failures.length + ' 个来源失败', actionId: 'search-failures',
          tint: PAPER.accentSoft, ink: PAPER.accent, onActivate: () => { this.showFailures = !this.showFailures; } })
      }
    }
    .width('100%')
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        Text('搜书')
          .fontSize(32)
          .fontWeight(FontWeight.Bold)
          .fontColor(PAPER.ink)
          .margin({ bottom: 7 })
        Row({ space: 10 }) {
          TextInput({ text: this.keyword, placeholder: '输入书名或作者', controller: this.inputController })
            .id('search-keyword')
            .layoutWeight(1)
            .height(48)
            .borderRadius(13)
            .backgroundColor(PAPER.surface)
            .border({ width: 1, color: PAPER.line })
            .fontColor(PAPER.ink)
            .placeholderColor(PAPER.muted)
            .enterKeyType(EnterKeyType.Search)
            .maxLength(80)
            .onChange((text: string) => { this.keyword = text; })
            .onSubmit(() => this.search())
          ActionText({ title: '搜索', actionId: 'start-search', canClick: this.keyword.trim().length > 0,
            onActivate: () => this.search() })
        }
        .width('100%')

        if (this.enabledSources === 0 && !this.searching && this.results.length === 0) {
          StatusPanel({
            title: '还没有已启用且可搜索的书源',
            detail: '可在书源页导入 JSON，查看书源是否可搜索并启用。',
            action: '去管理书源', actionId: 'manage-sources', onActivate: this.onManageSources
          })
        } else if (this.query.length === 0) {
          Text('将从 ' + this.enabledSources + ' 个可用书源搜索')
            .fontSize(14).fontColor(PAPER.muted).padding({ top: 5 })
        } else {
          this.searchStatus()
          if (this.message.length > 0) {
            Text(this.message).fontSize(13).fontColor(PAPER.accent)
          }
          if (this.showFailures) {
            Column({ space: 8 }) {
              ForEach(this.failures, (failure: SearchOutcome, index: number) => {
                Text(failure.sourceName + ' · ' + failure.problem)
                  .fontSize(13).lineHeight(20).fontColor(PAPER.muted).width('100%')
              }, (failure: SearchOutcome, index: number) => failure.sourceName + ':' + index)
            }
            .width('100%')
            .padding(14)
            .borderRadius(13)
            .backgroundColor(PAPER.accentSoft)
          }
          ForEach(this.results, (item: OnlineListing) => {
            this.resultCard(item)
          }, (item: OnlineListing) => item.sourceKey + '|' + item.detailUrl)
          if (!this.searching && this.results.length === 0 && this.message.length === 0) {
            StatusPanel({ title: this.total > 0 && this.failures.length === this.total ? '书源搜索失败' : '没有搜到小说',
              detail: this.failures.length > 0 ? '可查看失败原因，也可以换一个书名再试。' : '换一个书名或作者试试。' })
          }
        }
      }
      .width('100%')
      .constraintSize({ maxWidth: 680 })
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 22, right: 22, top: 18, bottom: 20 })
    }
    .align(Alignment.Top)
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
  }
}

import { common } from '@kit.AbilityKit';
import {
  ImportIssue, LegadoBookSource, optionalText, sourceEnabled, sourceKey, sourceLabel
} from '../model/LegadoBookSource';
import { ListFeed } from '../novel/ReaderData';
import { importSources, SourceImportSummary } from '../service/OnlineNovels';
import { errorMessage, ReaderLibrary } from '../service/ReaderLibrary';
import { SourceAvailability } from '../source/BookSource';
import { pickDocument } from '../storage/NovelFiles';
import { ActionText, StatusPanel } from './CommonViews';
import { PAPER } from './Palette';

enum SourceFilter {
  All,
  Searchable,
  NeedsReview
}

@Component
export struct SourcesView {
  @Prop @Watch('syncRows') entries: SourceAvailability[] = [];
  @Prop enabledCount: number = 0;
  @Prop loading: boolean = false;
  @Prop loadIssue: string = '';
  onChangeSources: () => void = (): void => {};
  onOpenLog: () => void = (): void => {};
  onTestSource: (key: string) => void = (_key: string): void => {};

  @State private importing: boolean = false;
  @State private pendingKey: string = '';
  @State private message: string = '';
  @State private report: SourceImportSummary | undefined = undefined;
  @State private sourceFilter: SourceFilter = SourceFilter.All;
  @State private keyword: string = '';
  @State private compatibleCount: number = 0;
  @State private configuredCount: number = 0;
  @State private visibleCount: number = 0;
  private inputController: TextInputController = new TextInputController();
  private feed: ListFeed<SourceAvailability> = new ListFeed<SourceAvailability>();
  private listScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.syncRows();
  }

  private syncRows(): void {
    const query: string = this.keyword.trim().toLowerCase();
    const terms: string[] = query.length > 0 ? query.split(/\s+/) : [];
    const filtered: SourceAvailability[] = [];
    let compatible: number = 0;
    let configured: number = 0;
    for (const entry of this.entries) {
      const canSearch: boolean = entry.searchIssue.length === 0;
      if (entry.hasSearch) {
        configured++;
      }
      if (canSearch) {
        compatible++;
      }
      if ((this.sourceFilter === SourceFilter.Searchable && !canSearch) ||
        (this.sourceFilter === SourceFilter.NeedsReview && canSearch && entry.readingIssue.length === 0)) {
        continue;
      }
      if (terms.length > 0) {
        const indexedText: string = (sourceLabel(entry.source) + '\n' +
          optionalText(entry.source.bookSourceGroup) + '\n' + sourceKey(entry.source)).toLowerCase();
        if (!terms.every((term: string): boolean => indexedText.includes(term))) {
          continue;
        }
      }
      filtered.push(entry);
    }
    if (this.sourceFilter === SourceFilter.NeedsReview) {
      filtered.sort((left: SourceAvailability, right: SourceAvailability): number =>
        Number(right.hasSearch) - Number(left.hasSearch));
    }
    this.configuredCount = configured;
    this.compatibleCount = compatible;
    this.visibleCount = filtered.length;
    this.feed.replace(filtered);
  }

  private switchFilter(filter: SourceFilter): void {
    if (this.sourceFilter !== filter) {
      this.inputController.stopEditing();
      this.sourceFilter = filter;
      this.syncRows();
      this.listScroller.scrollToIndex(0, false);
    }
  }

  private changeKeyword(value: string): void {
    if (this.keyword !== value) {
      this.keyword = value;
      this.syncRows();
      this.listScroller.scrollToIndex(0, false);
    }
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private async importJson(): Promise<void> {
    if (this.importing) {
      return;
    }
    this.importing = true;
    this.message = '';
    try {
      const selected: string = await pickDocument(this.context(), 'Legado 3.0 书源 JSON', '.json');
      if (selected.length === 0) {
        return;
      }
      this.report = undefined;
      const library: ReaderLibrary = await ReaderLibrary.get(this.context());
      this.report = await importSources(library, selected);
      this.onChangeSources();
      this.listScroller.scrollToIndex(0, false);
    } catch (error) {
      this.report = undefined;
      this.message = errorMessage(error as Error, '书源导入失败');
    } finally {
      this.importing = false;
    }
  }

  private async toggle(item: LegadoBookSource): Promise<void> {
    if (this.pendingKey.length > 0) {
      return;
    }
    this.pendingKey = sourceKey(item);
    this.message = '';
    try {
      const library: ReaderLibrary = await ReaderLibrary.get(this.context());
      await library.store.setSourceEnabled(sourceKey(item), !sourceEnabled(item));
      this.onChangeSources();
    } catch (error) {
      this.message = errorMessage(error as Error, '修改书源状态失败');
    } finally {
      this.pendingKey = '';
    }
  }

  private async remove(item: LegadoBookSource): Promise<void> {
    if (this.pendingKey.length > 0) {
      return;
    }
    this.pendingKey = sourceKey(item);
    try {
      const choice = await this.getUIContext().getPromptAction().showDialog({
        title: '移除书源',
        message: '移除「' + sourceLabel(item) + '」？已缓存的章节仍可阅读。',
        buttons: [{ text: '取消', color: PAPER.muted }, { text: '移除', color: PAPER.accent }]
      });
      if (choice.index !== 1) {
        return;
      }
      const library: ReaderLibrary = await ReaderLibrary.get(this.context());
      await library.store.removeSource(sourceKey(item));
      this.onChangeSources();
    } catch (error) {
      this.message = errorMessage(error as Error, '移除书源失败');
    } finally {
      this.pendingKey = '';
    }
  }

  @Builder
  private sourceCard(entry: SourceAvailability) {
    Column({ space: 9 }) {
      Row({ space: 9 }) {
        Column({ space: 4 }) {
          Text(sourceLabel(entry.source))
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(PAPER.ink)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(optionalText(entry.source.bookSourceGroup).length > 0
            ? optionalText(entry.source.bookSourceGroup) : sourceKey(entry.source))
            .fontSize(12)
            .fontColor(PAPER.muted)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        ActionText({ title: sourceEnabled(entry.source) ? '已启用' : '已停用',
          actionId: 'source-toggle-' + sourceLabel(entry.source),
          tint: sourceEnabled(entry.source) ? PAPER.accentSoft : PAPER.paper,
          ink: sourceEnabled(entry.source) ? PAPER.accent : PAPER.muted,
          canClick: this.pendingKey.length === 0, onActivate: () => this.toggle(entry.source) })
      }
      .width('100%')
      if (entry.searchIssue.length > 0) {
        Text(entry.searchIssue).fontSize(13).lineHeight(20).fontColor(PAPER.muted).width('100%')
      } else if (entry.readingIssue.length > 0) {
        Text('可搜索 · ' + entry.readingIssue).fontSize(13).lineHeight(20).fontColor(PAPER.muted).width('100%')
      } else {
        Text('搜索与阅读规则兼容').fontSize(13).fontColor(PAPER.accent)
      }
      Divider().color(PAPER.line)
      Row({ space: 8 }) {
        ActionText({ title: entry.searchIssue.length === 0 ? '测试' : '检查',
          actionId: 'source-test-' + sourceLabel(entry.source), tint: PAPER.accentSoft, ink: PAPER.accent,
          onActivate: () => this.onTestSource(sourceKey(entry.source)) })
        Blank()
        ActionText({ title: '移除', actionId: 'source-remove-' + sourceLabel(entry.source),
          tint: PAPER.paper, ink: PAPER.muted, canClick: this.pendingKey.length === 0,
          onActivate: () => this.remove(entry.source) })
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(14)
    .backgroundColor(PAPER.surface)
    .borderRadius(16)
    .border({ width: 1, color: PAPER.line })
  }

  @Builder
  private importResults(report: SourceImportSummary) {
    Column({ space: 7 }) {
      Row({ space: 10 }) {
        Text('已导入 ' + report.total + ' 条')
          .fontSize(16).fontWeight(FontWeight.Bold).fontColor(PAPER.accent).layoutWeight(1)
          .id('source-import-summary')
        ActionText({ title: '关闭', actionId: 'dismiss-import-results', tint: PAPER.surface, ink: PAPER.accent,
          onActivate: () => { this.report = undefined; } })
      }
      .width('100%')
      Text('新增 ' + report.added + ' · 更新 ' + report.updated + ' · 格式错误 ' + report.issues.length +
        (report.repeated > 0 ? ' · 文件内合并 ' + report.repeated + ' 条重复源' : ''))
        .fontSize(13).fontColor(PAPER.ink).width('100%').id('source-import-counts')
      ForEach(report.issues.slice(0, 12), (item: ImportIssue) => {
        Text(item.label + ' · ' + item.reason)
          .fontSize(13).lineHeight(20).fontColor(PAPER.ink).width('100%')
      }, (item: ImportIssue) => item.index.toString())
      if (report.issues.length > 12) {
        Text('还存在 ' + (report.issues.length - 12) + ' 条格式错误').fontSize(13).fontColor(PAPER.muted)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(13)
    .backgroundColor(PAPER.accentSoft)
    .borderRadius(14)
  }

  @Builder
  private filterButton(label: string, actionId: string, filter: SourceFilter) {
    ActionText({ title: label, actionId: actionId,
      tint: this.sourceFilter === filter ? PAPER.accentSoft : PAPER.surface,
      ink: this.sourceFilter === filter ? PAPER.accent : PAPER.muted,
      onActivate: () => this.switchFilter(filter) })
  }

  @Builder
  private heading() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Text('书源')
          .fontSize(32).fontWeight(FontWeight.Bold).fontColor(PAPER.ink).layoutWeight(1)
        ActionText({ title: '日志', actionId: 'source-open-log', tint: PAPER.surface, ink: PAPER.accent,
          onActivate: this.onOpenLog })
        ActionText({ title: this.importing ? '导入中…' : '导入 JSON', actionId: 'source-import',
          canClick: !this.importing, onActivate: () => this.importJson() })
      }
      .width('100%')
      .margin({ bottom: 7 })
      if (this.message.length > 0) {
        Text(this.message).fontSize(14).lineHeight(21).fontColor(PAPER.accent).id('source-import-error')
      }
      if (this.report !== undefined) {
        this.importResults(this.report)
      }
      if (this.loading) {
        StatusPanel({ title: '正在读取书源', busy: true })
      } else if (this.loadIssue.length > 0) {
        StatusPanel({ title: '书源加载失败', detail: this.loadIssue, action: '重试', actionId: 'retry-sources',
          onActivate: this.onChangeSources })
      } else if (this.entries.length === 0) {
        StatusPanel({ title: '还没有书源', detail: '选择 Legado 3.0 导出的 JSON 文件，支持单条书源和批量数组。' })
      } else {
        Text(this.entries.length + ' 条书源 · 搜索规则 ' + this.compatibleCount + '/' + this.configuredCount +
          ' 条可执行 · ' + this.enabledCount + ' 条参与搜索')
          .fontSize(13).lineHeight(20).fontColor(PAPER.muted).id('source-total')
        Row({ space: 8 }) {
          TextInput({ text: this.keyword, placeholder: '按名称、分组或网址查找', controller: this.inputController })
            .id('source-keyword')
            .layoutWeight(1)
            .height(44)
            .borderRadius(13)
            .backgroundColor(PAPER.surface)
            .border({ width: 1, color: PAPER.line })
            .fontColor(PAPER.ink)
            .placeholderColor(PAPER.muted)
            .enterKeyType(EnterKeyType.Search)
            .maxLength(150)
            .onChange((value: string) => this.changeKeyword(value))
            .onSubmit(() => this.inputController.stopEditing())
          if (this.keyword.length > 0) {
            ActionText({ title: '清除', actionId: 'source-clear-keyword', tint: PAPER.surface, ink: PAPER.accent,
              onActivate: () => {
                this.inputController.stopEditing();
                this.changeKeyword('');
              } })
          }
        }
        .width('100%')
        Row({ space: 8 }) {
          this.filterButton('全部', 'sources-show-all', SourceFilter.All)
          this.filterButton('可搜索', 'sources-show-searchable', SourceFilter.Searchable)
          this.filterButton('待检查', 'sources-show-review', SourceFilter.NeedsReview)
        }
        .width('100%')
        if (this.keyword.trim().length > 0 || this.sourceFilter !== SourceFilter.All) {
          Text(this.visibleCount === 0 ? '没有符合条件的书源' : '显示 ' + this.visibleCount + ' 条')
            .id('source-filtered-count').fontSize(13).fontColor(PAPER.muted)
        }
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    List({ space: 12, scroller: this.listScroller }) {
      ListItem() {
        this.heading()
      }
      LazyForEach(this.feed, (entry: SourceAvailability) => {
        ListItem() {
          this.sourceCard(entry)
        }
      }, (entry: SourceAvailability) => sourceKey(entry.source) + ':' + sourceLabel(entry.source) + ':' +
        optionalText(entry.source.bookSourceGroup) + ':' + sourceEnabled(entry.source) + ':' +
        entry.searchIssue + ':' + entry.readingIssue)
    }
    .width('100%')
    .height('100%')
    .constraintSize({ maxWidth: 680 })
    .cachedCount(4)
    .padding({ left: 22, right: 22, top: 18, bottom: 20 })
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.None)
  }
}

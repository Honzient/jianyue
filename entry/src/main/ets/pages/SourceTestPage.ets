import { common } from '@kit.AbilityKit';
import { LegadoBookSource, sourceLabel } from '../model/LegadoBookSource';
import { checkKeyword, diagnoseSource, SourceCheck } from '../service/OnlineNovels';
import { errorMessage, ReaderLibrary } from '../service/ReaderLibrary';
import { assessSource, SourceAvailability } from '../source/BookSource';
import { RequestGroup } from '../source/SiteReader';
import { ActionText, PageHeader } from '../ui/CommonViews';
import { PAPER } from '../ui/Palette';

const STAGES: string[] = ['搜索', '详情', '目录', '正文'];

@Component
export struct SourceTestPage {
  @Prop sourceItem?: LegadoBookSource;
  onExit: () => void = (): void => {};

  @State private keyword: string = '';
  @State private checks: SourceCheck[] = [];
  @State private inspected: SourceAvailability | undefined = undefined;
  @State private working: boolean = false;
  @State private message: string = '';

  private requests?: RequestGroup;
  private controller: TextInputController = new TextInputController();

  aboutToAppear(): void {
    if (this.sourceItem !== undefined) {
      try {
        this.inspected = assessSource(this.sourceItem);
        this.keyword = checkKeyword(this.sourceItem);
      } catch (error) {
        this.message = errorMessage(error as Error, '书源配置无效');
      }
    }
  }

  aboutToDisappear(): void {
    this.requests?.cancel();
  }

  private async test(): Promise<void> {
    const source: LegadoBookSource | undefined = this.sourceItem;
    const query: string = this.keyword.trim();
    if (source === undefined || this.inspected?.searchIssue !== '' || query.length === 0 || this.working) {
      return;
    }
    this.controller.stopEditing();
    this.working = true;
    this.message = '';
    this.checks = [];
    const group: RequestGroup = new RequestGroup();
    this.requests = group;
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const library: ReaderLibrary = await ReaderLibrary.get(context);
      await diagnoseSource(source, query, group, library.sourceLog, (update: SourceCheck): void => {
        if (!group.isCanceled()) {
          this.checks = this.checks.concat([update]);
        }
      });
    } catch (error) {
      if (!group.isCanceled()) {
        this.message = errorMessage(error as Error, '无法启动书源测试');
      }
    } finally {
      if (!group.isCanceled()) {
        this.working = false;
      }
    }
  }

  private stop(): void {
    this.requests?.cancel();
    this.working = false;
    this.message = '测试已停止';
  }

  private detailAt(index: number): string {
    if (index < this.checks.length) {
      return this.checks[index].detail;
    }
    return this.working && index === this.checks.length ? '正在检查…' : '待检查';
  }

  @Builder
  private ruleRow(stage: string, issue: string, id: string) {
    Row({ space: 12 }) {
      Text(stage).fontSize(13).fontWeight(FontWeight.Medium).fontColor(PAPER.ink).width(35)
      Text(issue.length === 0 ? '可执行' : issue).fontSize(13).lineHeight(19)
        .fontColor(issue.length === 0 ? PAPER.muted : PAPER.accent).layoutWeight(1).id(id)
    }
    .alignItems(VerticalAlign.Top)
    .width('100%')
  }

  @Builder
  private ruleOverview(check: SourceAvailability) {
    Column({ space: 7 }) {
      Text('规则检查').fontSize(16).fontWeight(FontWeight.Bold).fontColor(PAPER.ink).id('diagnostic-rules')
      this.ruleRow('搜索', check.searchIssue, 'diagnostic-rule-search')
      this.ruleRow('详情', check.detailIssue, 'diagnostic-rule-detail')
      this.ruleRow('目录', check.tocIssue, 'diagnostic-rule-toc')
      this.ruleRow('正文', check.contentIssue, 'diagnostic-rule-content')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(14)
    .borderRadius(14)
    .backgroundColor(PAPER.surface)
    .border({ width: 1, color: PAPER.line })
  }

  @Builder
  private stageRow(stage: string, index: number) {
    Column({ space: 6 }) {
      Row({ space: 10 }) {
        Text(stage).fontSize(16).fontWeight(FontWeight.Bold).fontColor(PAPER.ink).layoutWeight(1)
        if (index < this.checks.length) {
          Text(this.checks[index].successful ? '通过' : '失败')
            .fontSize(13).fontWeight(FontWeight.Medium)
            .fontColor(this.checks[index].successful ? '#35604D' : PAPER.accent)
            .id('diagnostic-' + index)
        } else if (this.working && index === this.checks.length) {
          LoadingProgress().color(PAPER.accent).width(21).height(21)
        }
      }
      .width('100%')
      Text(this.detailAt(index)).fontSize(13).lineHeight(20).fontColor(PAPER.muted)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(14)
    .borderRadius(14)
    .backgroundColor(PAPER.surface)
    .border({ width: 1, color: PAPER.line })
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: '书源诊断', detail: this.sourceItem !== undefined ? sourceLabel(this.sourceItem) : '', onBack: this.onExit })
        Divider().color(PAPER.line)
        Scroll() {
          Column({ space: 10 }) {
            if (this.inspected !== undefined) {
              this.ruleOverview(this.inspected)
            }
            if (this.inspected?.searchIssue === '') {
              Text('联网测试').fontSize(16).fontWeight(FontWeight.Bold).fontColor(PAPER.ink)
              Row({ space: 8 }) {
                TextInput({ text: this.keyword, placeholder: '输入本站可搜到的书名', controller: this.controller })
                  .id('diagnostic-keyword')
                  .layoutWeight(1)
                  .height(48)
                  .fontColor(PAPER.ink)
                  .placeholderColor(PAPER.muted)
                  .backgroundColor(PAPER.surface)
                  .borderRadius(13)
                  .border({ width: 1, color: PAPER.line })
                  .maxLength(80)
                  .enterKeyType(EnterKeyType.Search)
                  .onChange((value: string) => { this.keyword = value; })
                  .onSubmit(() => this.test())
                ActionText({ title: this.working ? '停止' : '运行测试', actionId: 'diagnostic-run',
                  canClick: this.working || this.keyword.trim().length > 0, onActivate: () => {
                    if (this.working) {
                      this.stop();
                    } else {
                      this.test();
                    }
                  } })
              }
              .width('100%')
              ForEach(STAGES, (stage: string, index: number) => {
                this.stageRow(stage, index)
              }, (stage: string) => stage)
            }
            if (this.message.length > 0) {
              Text(this.message).fontSize(13).fontColor(PAPER.accent)
            }
          }
          .width('100%').constraintSize({ maxWidth: 680 })
          .padding({ left: 20, right: 20, top: 16, bottom: 24 })
          .alignItems(HorizontalAlign.Start)
        }
        .align(Alignment.Top)
        .width('100%').layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width('100%').height('100%').backgroundColor(PAPER.paper)
    }
    .hideTitleBar(true)
  }
}

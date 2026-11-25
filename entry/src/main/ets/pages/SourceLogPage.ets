import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { ReaderLibrary } from '../service/ReaderLibrary';
import { ActionText, PageHeader, StatusPanel } from '../ui/CommonViews';
import { PAPER } from '../ui/Palette';

const RECENT_LINES: number = 120;

@Component
export struct SourceLogPage {
  onExit: () => void = (): void => {};

  @State private recent: string = '';
  @State private loading: boolean = true;
  @State private exporting: boolean = false;
  @State private message: string = '';

  aboutToAppear(): void {
    this.refresh();
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private async refresh(): Promise<void> {
    this.loading = true;
    this.message = '';
    try {
      const library: ReaderLibrary = await ReaderLibrary.get(this.context());
      this.recent = (await library.sourceLog.snapshot()).trimEnd().split('\n').slice(-RECENT_LINES).reverse().join('\n');
    } catch {
      this.message = '读取本地日志失败';
    } finally {
      this.loading = false;
    }
  }

  private async exportLog(): Promise<void> {
    if (this.exporting) {
      return;
    }
    this.exporting = true;
    this.message = '';
    try {
      const context: common.UIAbilityContext = this.context();
      const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
      options.newFileNames = ['jianyue-source-' + Date.now() + '.txt'];
      const saved: string[] = await new picker.DocumentViewPicker(context).save(options);
      if (saved.length > 0) {
        const library: ReaderLibrary = await ReaderLibrary.get(context);
        await library.sourceLog.exportTo(saved[0]);
        this.message = '已导出日志';
      }
    } catch {
      this.message = '保存日志文件失败';
    } finally {
      this.exporting = false;
    }
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({ title: '本地日志', detail: '书源运行记录', onBack: this.onExit })
        Divider().color(PAPER.line)
        Row({ space: 10 }) {
          ActionText({ title: '刷新', actionId: 'source-log-refresh', tint: PAPER.accentSoft,
            ink: PAPER.accent, canClick: !this.loading, onActivate: () => this.refresh() })
          ActionText({ title: this.exporting ? '正在导出…' : '导出日志', actionId: 'source-log-export',
            canClick: !this.exporting && this.recent.length > 0, onActivate: () => this.exportLog() })
        }
        .width('100%')
        .padding({ left: 18, right: 18, top: 12, bottom: 4 })
        if (this.message.length > 0) {
          Text(this.message).fontSize(14).fontColor(PAPER.accent).padding(12)
        }
        if (this.loading) {
          StatusPanel({ title: '正在读取本地日志', busy: true })
        } else if (this.recent.length === 0) {
          StatusPanel({ title: '暂无日志', detail: '运行一次搜书或书源测试后，可在这里查看记录。' })
        } else {
          Scroll() {
            Text(this.recent)
              .id('source-log-records')
              .width('100%')
              .fontSize(12)
              .lineHeight(19)
              .fontColor(PAPER.ink)
              .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE)
              .padding(14)
              .backgroundColor(PAPER.surface)
              .borderRadius(13)
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 18, right: 18, top: 10, bottom: 16 })
          .align(Alignment.Top)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(PAPER.paper)
    }
    .hideTitleBar(true)
  }
}

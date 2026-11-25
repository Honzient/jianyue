import { UIAbility } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { bindWindowColors } from '../ui/WindowColors';
import { ReaderLibrary } from '../service/ReaderLibrary';

export default class EntryAbility extends UIAbility {
  onWindowStageCreate(windowStage: window.WindowStage): void {
    bindWindowColors(windowStage.getMainWindowSync());
    windowStage.loadContent('pages/Index', (error) => {
      if (error.code) {
        hilog.error(0x0010, 'Jianyue', 'Cannot load bookshelf: %{public}d', error.code);
      }
    });
  }

  onBackground(): void {
    ReaderLibrary.flushOnBackground();
  }
}

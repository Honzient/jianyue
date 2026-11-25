import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Palette, PAPER } from './Palette';

let mainWindow: window.Window | undefined;

export function bindWindowColors(appWindow: window.Window): void {
  mainWindow = appWindow;
  applyWindowColors(PAPER);
}

export async function applyWindowColors(palette: Palette): Promise<void> {
  const target: window.Window | undefined = mainWindow;
  if (target === undefined) {
    return;
  }
  const properties: window.SystemBarProperties = {
    statusBarColor: palette.paper,
    statusBarContentColor: palette.ink,
    navigationBarColor: palette.paper,
    navigationBarContentColor: palette.ink
  };
  try {
    target.setWindowBackgroundColor(palette.paper);
    await target.setWindowSystemBarProperties(properties);
  } catch {
    hilog.warn(0x0010, 'Jianyue', 'Cannot apply reader system bar colors');
  }
}

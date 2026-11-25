import { PAPER, Palette } from './Palette';

@Component
export struct ActionText {
  @Prop title: string = '';
  @Prop actionId: string = '';
  @Prop tint: string = PAPER.accent;
  @Prop ink: string = PAPER.onAccent;
  @Prop canClick: boolean = true;
  onActivate: () => void = (): void => {};

  build() {
    Button(this.title, { type: ButtonType.Normal })
      .id(this.actionId)
      .type(ButtonType.Normal)
      .borderRadius(13)
      .constraintSize({ minHeight: 44 })
      .padding({ left: 14, right: 14 })
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.ink)
      .backgroundColor(this.tint)
      .enabled(this.canClick)
      .opacity(this.canClick ? 1 : 0.45)
      .onClick(() => this.onActivate())
  }
}

@Component
export struct PageHeader {
  @Prop title: string = '';
  @Prop detail: string = '';
  @Prop palette: Palette = PAPER;
  @Prop trailingAction: string = '';
  @Prop trailingId: string = '';
  @Prop trailingEnabled: boolean = true;
  onBack: () => void = (): void => {};
  onTrailing: () => void = (): void => {};

  build() {
    Row({ space: 10 }) {
      Button('‹', { type: ButtonType.Normal })
        .id('page-back')
        .accessibilityText('返回')
        .fontSize(30)
        .fontWeight(FontWeight.Regular)
        .width(44)
        .height(44)
        .borderRadius(14)
        .fontColor(this.palette.ink)
        .backgroundColor(this.palette.surface)
        .onClick(() => this.onBack())
      Column({ space: 3 }) {
        Text(this.title)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.ink)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.detail.length > 0) {
          Text(this.detail)
            .fontSize(12)
            .fontColor(this.palette.muted)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      if (this.trailingAction.length > 0) {
        ActionText({
          title: this.trailingAction, actionId: this.trailingId, tint: this.palette.accentSoft,
          ink: this.palette.accent, canClick: this.trailingEnabled, onActivate: this.onTrailing
        })
      }
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 10, bottom: 10 })
    .backgroundColor(this.palette.paper)
  }
}

@Component
export struct StatusPanel {
  @Prop title: string = '';
  @Prop detail: string = '';
  @Prop palette: Palette = PAPER;
  @Prop busy: boolean = false;
  @Prop action: string = '';
  @Prop actionId: string = '';
  onActivate: () => void = (): void => {};

  build() {
    Column({ space: 12 }) {
      if (this.busy) {
        LoadingProgress().color(this.palette.accent).width(32).height(32)
      }
      Text(this.title)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette.ink)
        .textAlign(TextAlign.Center)
      if (this.detail.length > 0) {
        Text(this.detail)
          .fontSize(14)
          .lineHeight(21)
          .fontColor(this.palette.muted)
          .textAlign(TextAlign.Center)
      }
      if (this.action.length > 0) {
        ActionText({ title: this.action, actionId: this.actionId, tint: this.palette.accent,
          ink: this.palette.onAccent, onActivate: this.onActivate })
      }
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 24, bottom: 24 })
    .backgroundColor(this.palette.surface)
    .borderRadius(20)
  }
}

@Component
export struct BookMarkArt {
  @Prop artWidth: number = 46;
  @Prop artHeight: number = 62;
  @Prop tint: string = PAPER.accent;

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Row({ space: 3 }) {
        /*
         * The two pages use separate rounded corners, which keeps the image legible at book-row size.
         */
        Rect().width(this.artWidth * 0.24).height(this.artHeight * 0.33).radius(2).fill('#FFF0DB')
        Rect().width(this.artWidth * 0.24).height(this.artHeight * 0.33).radius(2).fill('#FFF0DB')
      }
    }
    .width(this.artWidth)
    .height(this.artHeight)
    .backgroundColor(this.tint)
    .borderRadius(9)
    .accessibilityLevel('no')
  }
}

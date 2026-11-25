import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Book, BookKind, Chapter, ReadPosition } from '../model/LibraryModels';
import { decodeText, splitTextNovel, TextChapter } from '../novel/TextNovel';
import { LibraryStore } from '../storage/LibraryStore';
import { SourceLog } from '../storage/SourceLog';
import { documentBaseName, NovelFiles } from '../storage/NovelFiles';

class PendingPosition {
  public bookId: string;
  public position: ReadPosition;
  public revision: number;

  constructor(bookId: string, position: ReadPosition, revision: number) {
    this.bookId = bookId;
    this.position = position;
    this.revision = revision;
  }
}

export class ReaderLibrary {
  private static opening?: Promise<ReaderLibrary>;
  private static instance?: ReaderLibrary;

  private importQueue: Promise<void> = Promise.resolve();
  private positionTask: Promise<void> = Promise.resolve();
  private stagedPosition?: PendingPosition;
  private saveTimer: number = -1;
  private positionRevision: number = 0;

  public store: LibraryStore;
  public files: NovelFiles;
  public sourceLog: SourceLog;

  private constructor(store: LibraryStore, files: NovelFiles, sourceLog: SourceLog) {
    this.store = store;
    this.files = files;
    this.sourceLog = sourceLog;
  }

  static get(context: common.UIAbilityContext): Promise<ReaderLibrary> {
    if (ReaderLibrary.opening === undefined) {
      ReaderLibrary.opening = ReaderLibrary.open(context);
    }
    return ReaderLibrary.opening;
  }

  static async flushOnBackground(): Promise<void> {
    if (ReaderLibrary.instance) {
      await Promise.all([ReaderLibrary.instance.flushPosition(), ReaderLibrary.instance.sourceLog.flush()]);
    }
  }

  private static async open(context: common.UIAbilityContext): Promise<ReaderLibrary> {
    try {
      const store: LibraryStore = await LibraryStore.open(context);
      const library: ReaderLibrary = new ReaderLibrary(store, new NovelFiles(context), new SourceLog(context.filesDir));
      ReaderLibrary.instance = library;
      return library;
    } catch (error) {
      ReaderLibrary.opening = undefined;
      throw error as Error;
    }
  }

  async importText(uri: string): Promise<Book> {
    const task: Promise<Book> = this.importQueue.then(() => this.persistText(uri));
    this.importQueue = task.then((): void => {}, (): void => {});
    return task;
  }

  stagePosition(bookId: string, chapterId: string, offset: number): void {
    if (this.stagedPosition?.bookId !== undefined && this.stagedPosition.bookId !== bookId) {
      this.flushPosition();
    }
    this.stagedPosition = new PendingPosition(bookId, new ReadPosition(chapterId, offset), ++this.positionRevision);
    if (this.saveTimer >= 0) {
      clearTimeout(this.saveTimer);
    }
    this.saveTimer = setTimeout((): void => {
      this.flushPosition();
    }, 220);
  }

  async flushPosition(): Promise<void> {
    if (this.saveTimer >= 0) {
      clearTimeout(this.saveTimer);
      this.saveTimer = -1;
    }
    const item: PendingPosition | undefined = this.stagedPosition;
    this.stagedPosition = undefined;
    if (item !== undefined) {
      this.positionTask = this.positionTask.then(async () => {
        try {
          await this.store.savePosition(item.bookId, item.position);
        } catch (error) {
          hilog.error(0x0010, 'Jianyue', 'Could not persist reading position');
          if (this.stagedPosition === undefined && item.revision === this.positionRevision) {
            this.stagedPosition = item;
          }
        }
      });
    }
    await this.positionTask;
  }

  private async persistText(uri: string): Promise<Book> {
    const bytes: Uint8Array = await this.files.rawNovel(uri);
    const identity: string = await this.files.identity(bytes);
    const known: Book | undefined = await this.store.bookByIdentity(identity);
    if (known !== undefined) {
      if (!known.onShelf) {
        await this.store.setOnShelf(known.id, true);
        known.onShelf = true;
      }
      return known;
    }

    const chapters: TextChapter[] = splitTextNovel(decodeText(bytes));
    const book: Book = new Book(
      util.generateRandomUUID(), identity, BookKind.Local, documentBaseName(uri), '', '', '', '', '', '', true
    );
    const index: Chapter[] = await this.files.saveLocalBook(book, bytes, chapters);
    try {
      await this.store.insertLocal(book, index);
      return book;
    } catch (error) {
      await this.files.discardLocalBook(book.id);
      throw error as Error;
    }
  }
}

export function errorMessage(error: Error, fallback: string): string {
  return typeof error.message === 'string' && error.message.trim().length > 0 ? error.message : fallback;
}

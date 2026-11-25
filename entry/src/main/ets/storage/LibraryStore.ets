import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import {
  Book, BookKind, Chapter, OnlineChapter, OnlineListing, ReadingStyle, ReadPosition, ShelfItem
} from '../model/LibraryModels';
import { decodeSourceDocument, LegadoBookSource, sourceEnabled, sourceKey } from '../model/LegadoBookSource';

const CREATE_TABLES: string[] = [
  'CREATE TABLE IF NOT EXISTS books (' +
    'id TEXT PRIMARY KEY, identity TEXT NOT NULL UNIQUE, kind INTEGER NOT NULL, title TEXT NOT NULL, ' +
    'author TEXT NOT NULL, description TEXT NOT NULL, source_key TEXT NOT NULL, source_name TEXT NOT NULL, ' +
    'detail_url TEXT NOT NULL, toc_url TEXT NOT NULL, on_shelf INTEGER NOT NULL, added_at INTEGER NOT NULL, ' +
    "rule_values TEXT NOT NULL DEFAULT '')",
  'CREATE TABLE IF NOT EXISTS chapters (' +
    'id TEXT PRIMARY KEY, book_id TEXT NOT NULL, idx INTEGER NOT NULL, title TEXT NOT NULL, url TEXT NOT NULL, ' +
    'byte_offset INTEGER NOT NULL, byte_length INTEGER NOT NULL, UNIQUE(book_id, idx))',
  'CREATE TABLE IF NOT EXISTS positions (' +
    'book_id TEXT PRIMARY KEY, chapter_id TEXT NOT NULL, text_offset INTEGER NOT NULL, updated_at INTEGER NOT NULL)',
  'CREATE TABLE IF NOT EXISTS book_sources (' +
    'bookSourceUrl TEXT PRIMARY KEY, document TEXT NOT NULL)',
  'CREATE TABLE IF NOT EXISTS reader_style (' +
    'id INTEGER PRIMARY KEY, font_size INTEGER NOT NULL, spacing INTEGER NOT NULL, night INTEGER NOT NULL)'
];

const UPSERT_BOOK: string =
  'INSERT INTO books (id, identity, kind, title, author, description, source_key, source_name, ' +
    'detail_url, toc_url, on_shelf, added_at, rule_values) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ' +
    'ON CONFLICT(id) DO UPDATE SET title = excluded.title, author = excluded.author, ' +
    'description = excluded.description, source_name = excluded.source_name, toc_url = excluded.toc_url, ' +
    'on_shelf = excluded.on_shelf, rule_values = excluded.rule_values';

const SHELF_QUERY: string =
  'SELECT b.*, c.title AS resume_title, p.updated_at AS last_read_at, ' +
    '(SELECT COUNT(*) FROM chapters x WHERE x.book_id = b.id) AS chapter_count ' +
    'FROM books b LEFT JOIN positions p ON p.book_id = b.id ' +
    'LEFT JOIN chapters c ON c.book_id = b.id AND c.id = p.chapter_id ' +
    'WHERE b.on_shelf = 1 ORDER BY COALESCE(p.updated_at, 0) DESC, b.added_at DESC, b.id';

export class LibraryStore {
  private pendingWrite: Promise<void> = Promise.resolve();

  private database: relationalStore.RdbStore;

  private constructor(database: relationalStore.RdbStore) {
    this.database = database;
  }

  static async open(context: common.UIAbilityContext): Promise<LibraryStore> {
    const config: relationalStore.StoreConfig = {
      name: 'yuejian.db',
      securityLevel: relationalStore.SecurityLevel.S1
    };
    const database: relationalStore.RdbStore = await relationalStore.getRdbStore(context, config);
    const version: number = database.version;
    if (version < 2) {
      for (const sql of CREATE_TABLES) {
        await database.execute(sql);
      }
      if (version === 1) {
        await LibraryStore.migrateSources(database);
      }
      database.version = 2;
    }
    if (version < 3) {
      await LibraryStore.addRuleValues(database);
      database.version = 3;
    }
    return new LibraryStore(database);
  }

  private static async addRuleValues(database: relationalStore.RdbStore): Promise<void> {
    const columns: relationalStore.ResultSet = await database.querySql('PRAGMA table_info(books)');
    try {
      const name: number = columns.getColumnIndex('name');
      while (columns.goToNextRow()) {
        if (columns.getString(name) === 'rule_values') {
          return;
        }
      }
    } finally {
      columns.close();
    }
    await database.execute("ALTER TABLE books ADD COLUMN rule_values TEXT NOT NULL DEFAULT ''");
  }

  private static async migrateSources(database: relationalStore.RdbStore): Promise<void> {
    const transaction: relationalStore.Transaction = await database.createTransaction();
    let rows: relationalStore.ResultSet | undefined;
    try {
      rows = await transaction.querySql('SELECT source_key, enabled, payload FROM sources');
      while (rows.goToNextRow()) {
        const key: string = rows.getString(0);
        const enabled: boolean = rows.getLong(1) === 1;
        const source: LegadoBookSource = decodeSourceDocument(rows.getString(2));
        if (sourceKey(source) !== key) {
          source.bookSourceUrl = key;
        }
        if (sourceEnabled(source) !== enabled) {
          source.enabled = enabled;
        }
        await transaction.execute('INSERT OR IGNORE INTO book_sources (bookSourceUrl, document) VALUES (?, ?)',
          [key, JSON.stringify(source)]);
      }
      rows.close();
      rows = undefined;
      await transaction.commit();
    } catch (error) {
      rows?.close();
      try {
        await transaction.rollback();
      } catch {
        // Leave the migration version unchanged so a later launch can retry.
      }
      throw error as Error;
    }
  }

  private write<T>(operation: () => Promise<T>): Promise<T> {
    const task: Promise<T> = this.pendingWrite.then(operation);
    this.pendingWrite = task.then((): void => {}, (): void => {});
    return task;
  }

  private async transaction<T>(operation: (transaction: relationalStore.Transaction) => Promise<T>): Promise<T> {
    const transaction: relationalStore.Transaction = await this.database.createTransaction();
    try {
      const result: T = await operation(transaction);
      await transaction.commit();
      return result;
    } catch (error) {
      try {
        await transaction.rollback();
      } catch {
        // Keep the error from the original operation.
      }
      throw error as Error;
    }
  }

  async listShelf(): Promise<ShelfItem[]> {
    const rows: relationalStore.ResultSet = await this.database.querySql(SHELF_QUERY);
    try {
      const shelf: ShelfItem[] = [];
      while (rows.goToNextRow()) {
        shelf.push(new ShelfItem(
          this.readBook(rows),
          this.nullableString(rows, 'resume_title'),
          this.number(rows, 'chapter_count'),
          this.nullableNumber(rows, 'last_read_at')
        ));
      }
      return shelf;
    } finally {
      rows.close();
    }
  }

  async bookById(id: string): Promise<Book | undefined> {
    return this.queryBook('SELECT * FROM books WHERE id = ?', id);
  }

  async bookByIdentity(identity: string): Promise<Book | undefined> {
    return this.queryBook('SELECT * FROM books WHERE identity = ?', identity);
  }

  async onlineBook(sourceKey: string, detailUrl: string): Promise<Book | undefined> {
    return this.bookByIdentity(this.onlineIdentity(sourceKey, detailUrl));
  }

  private async queryBook(sql: string, value: string): Promise<Book | undefined> {
    const rows: relationalStore.ResultSet = await this.database.querySql(sql, [value]);
    try {
      return rows.goToFirstRow() ? this.readBook(rows) : undefined;
    } finally {
      rows.close();
    }
  }

  async chapters(bookId: string): Promise<Chapter[]> {
    const rows: relationalStore.ResultSet = await this.database.querySql(
      'SELECT * FROM chapters WHERE book_id = ? ORDER BY idx', [bookId]);
    try {
      const chapters: Chapter[] = [];
      while (rows.goToNextRow()) {
        chapters.push(new Chapter(
          this.string(rows, 'id'), bookId, this.number(rows, 'idx'), this.string(rows, 'title'),
          this.string(rows, 'url'), this.number(rows, 'byte_offset'), this.number(rows, 'byte_length')
        ));
      }
      return chapters;
    } finally {
      rows.close();
    }
  }

  async insertLocal(book: Book, chapters: Chapter[]): Promise<void> {
    await this.write(() => this.transaction(async (transaction: relationalStore.Transaction) => {
      await transaction.execute(UPSERT_BOOK, this.bookValues(book));
      await this.insertChapters(transaction, chapters);
    }));
  }

  async saveOnline(listing: OnlineListing, catalog?: OnlineChapter[]): Promise<Book> {
    return this.write(async () => {
      const identity: string = this.onlineIdentity(listing.sourceKey, listing.detailUrl);
      const previous: Book | undefined = await this.bookByIdentity(identity);
      const book: Book = new Book(
        previous?.id ?? util.generateRandomUUID(), identity, BookKind.Online, listing.title, listing.author,
        listing.description, listing.sourceKey, listing.sourceName, listing.detailUrl,
        listing.tocUrl.length > 0 ? listing.tocUrl : previous?.tocUrl ?? '', previous?.onShelf ?? false,
        listing.ruleValues || previous?.ruleValues || ''
      );
      const replacement: Chapter[] = [];
      if (catalog !== undefined) {
        const existing: Map<string, string> = new Map<string, string>();
        for (const chapter of await this.chapters(book.id)) {
          existing.set(chapter.url, chapter.id);
        }
        for (const item of catalog) {
          replacement.push(new Chapter(
            existing.get(item.url) ?? util.generateRandomUUID(), book.id, replacement.length, item.title, item.url
          ));
        }
      }

      return this.transaction(async (transaction: relationalStore.Transaction) => {
        await transaction.execute(UPSERT_BOOK, this.bookValues(book));
        if (catalog !== undefined) {
          await transaction.execute('DELETE FROM chapters WHERE book_id = ?', [book.id]);
          await this.insertChapters(transaction, replacement);
        }
        return book;
      });
    });
  }

  async setOnShelf(bookId: string, onShelf: boolean): Promise<void> {
    await this.write(async () => {
      await this.database.execute('UPDATE books SET on_shelf = ? WHERE id = ?', [onShelf ? 1 : 0, bookId]);
    });
  }

  async position(bookId: string): Promise<ReadPosition> {
    const rows: relationalStore.ResultSet = await this.database.querySql(
      'SELECT chapter_id, text_offset FROM positions WHERE book_id = ?', [bookId]);
    try {
      return rows.goToFirstRow()
        ? new ReadPosition(this.string(rows, 'chapter_id'), this.number(rows, 'text_offset'))
        : new ReadPosition();
    } finally {
      rows.close();
    }
  }

  async savePosition(bookId: string, position: ReadPosition): Promise<void> {
    const time: number = Date.now();
    await this.write(async () => {
      await this.database.execute(
        'INSERT INTO positions (book_id, chapter_id, text_offset, updated_at) VALUES (?, ?, ?, ?) ' +
          'ON CONFLICT(book_id) DO UPDATE SET chapter_id = excluded.chapter_id, ' +
          'text_offset = excluded.text_offset, updated_at = excluded.updated_at',
        [bookId, position.chapterId, position.offset, time]
      );
    });
  }

  async readingStyle(): Promise<ReadingStyle> {
    const rows: relationalStore.ResultSet = await this.database.querySql(
      'SELECT font_size, spacing, night FROM reader_style WHERE id = 1');
    try {
      return rows.goToFirstRow()
        ? new ReadingStyle(this.number(rows, 'font_size'), this.number(rows, 'spacing'), this.number(rows, 'night') === 1)
        : new ReadingStyle();
    } finally {
      rows.close();
    }
  }

  async saveReadingStyle(style: ReadingStyle): Promise<void> {
    await this.write(async () => {
      await this.database.execute(
        'INSERT INTO reader_style (id, font_size, spacing, night) VALUES (1, ?, ?, ?) ' +
          'ON CONFLICT(id) DO UPDATE SET font_size = excluded.font_size, ' +
          'spacing = excluded.spacing, night = excluded.night',
        [style.fontSize, style.spacing, style.night ? 1 : 0]
      );
    });
  }

  async sources(): Promise<LegadoBookSource[]> {
    const rows: relationalStore.ResultSet = await this.database.querySql('SELECT document FROM book_sources');
    try {
      const list: LegadoBookSource[] = [];
      while (rows.goToNextRow()) {
        list.push(decodeSourceDocument(rows.getString(0)));
      }
      list.sort((left: LegadoBookSource, right: LegadoBookSource): number => {
        const leftOrder: number = typeof left.customOrder === 'number' ? left.customOrder : 0;
        const rightOrder: number = typeof right.customOrder === 'number' ? right.customOrder : 0;
        return leftOrder - rightOrder || left.bookSourceName.localeCompare(right.bookSourceName);
      });
      return list;
    } finally {
      rows.close();
    }
  }

  async source(key: string): Promise<LegadoBookSource | undefined> {
    const rows: relationalStore.ResultSet = await this.database.querySql(
      'SELECT document FROM book_sources WHERE bookSourceUrl = ?', [key]);
    try {
      return rows.goToFirstRow() ? decodeSourceDocument(rows.getString(0)) : undefined;
    } finally {
      rows.close();
    }
  }

  async saveSources(sources: LegadoBookSource[]): Promise<number> {
    if (sources.length === 0) {
      return 0;
    }
    return this.write(() => this.transaction(async (transaction: relationalStore.Transaction): Promise<number> => {
      const existing: Set<string> = new Set<string>();
      const rows: relationalStore.ResultSet = await transaction.querySql('SELECT bookSourceUrl FROM book_sources');
      try {
        while (rows.goToNextRow()) {
          existing.add(rows.getString(0));
        }
      } finally {
        rows.close();
      }

      let updated: number = 0;
      const size: number = 120;
      for (let index: number = 0; index < sources.length; index += size) {
        const terms: string[] = [];
        const values: relationalStore.ValueType[] = [];
        for (const source of sources.slice(index, index + size)) {
          const key: string = sourceKey(source);
          terms.push('(?, ?)');
          values.push(key, JSON.stringify(source));
          if (existing.has(key)) {
            updated++;
          }
        }
        await transaction.execute('INSERT INTO book_sources (bookSourceUrl, document) VALUES ' + terms.join(', ') +
          ' ON CONFLICT(bookSourceUrl) DO UPDATE SET document = excluded.document', values);
      }
      return updated;
    }));
  }

  async setSourceEnabled(key: string, enabled: boolean): Promise<void> {
    await this.write(async () => {
      const source: LegadoBookSource | undefined = await this.source(key);
      if (source !== undefined) {
        source.enabled = enabled;
        await this.database.execute('UPDATE book_sources SET document = ? WHERE bookSourceUrl = ?',
          [JSON.stringify(source), key]);
      }
    });
  }

  async removeSource(key: string): Promise<void> {
    await this.write(async () => {
      await this.database.execute('DELETE FROM book_sources WHERE bookSourceUrl = ?', [key]);
    });
  }

  private async insertChapters(transaction: relationalStore.Transaction, chapters: Chapter[]): Promise<void> {
    const size: number = 240;
    for (let index: number = 0; index < chapters.length; index += size) {
      const rows: relationalStore.ValuesBucket[] = [];
      for (const chapter of chapters.slice(index, index + size)) {
        const values: relationalStore.ValuesBucket = {
          id: chapter.id,
          book_id: chapter.bookId,
          idx: chapter.index,
          title: chapter.title,
          url: chapter.url,
          byte_offset: chapter.byteOffset,
          byte_length: chapter.byteLength
        };
        rows.push(values);
      }
      await transaction.batchInsert('chapters', rows);
    }
  }

  private readBook(rows: relationalStore.ResultSet): Book {
    return new Book(
      this.string(rows, 'id'), this.string(rows, 'identity'), this.number(rows, 'kind') as BookKind,
      this.string(rows, 'title'), this.string(rows, 'author'), this.string(rows, 'description'),
      this.string(rows, 'source_key'), this.string(rows, 'source_name'), this.string(rows, 'detail_url'),
      this.string(rows, 'toc_url'), this.number(rows, 'on_shelf') === 1, this.string(rows, 'rule_values')
    );
  }

  private bookValues(book: Book): relationalStore.ValueType[] {
    return [
      book.id, book.identity, book.kind, book.title, book.author, book.description, book.sourceKey,
      book.sourceName, book.detailUrl, book.tocUrl, book.onShelf ? 1 : 0, Date.now(), book.ruleValues
    ];
  }

  private onlineIdentity(sourceKey: string, detailUrl: string): string {
    return 'online:' + sourceKey.length + ':' + sourceKey + detailUrl;
  }

  private string(rows: relationalStore.ResultSet, column: string): string {
    return rows.getString(rows.getColumnIndex(column));
  }

  private number(rows: relationalStore.ResultSet, column: string): number {
    return rows.getLong(rows.getColumnIndex(column));
  }

  private nullableString(rows: relationalStore.ResultSet, column: string): string {
    const index: number = rows.getColumnIndex(column);
    return rows.isColumnNull(index) ? '' : rows.getString(index);
  }

  private nullableNumber(rows: relationalStore.ResultSet, column: string): number {
    const index: number = rows.getColumnIndex(column);
    return rows.isColumnNull(index) ? 0 : rows.getLong(index);
  }
}

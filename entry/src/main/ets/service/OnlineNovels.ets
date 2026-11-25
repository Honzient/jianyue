import { hilog } from '@kit.PerformanceAnalysisKit';
import { Book, BookKind, Chapter, OnlineChapter, OnlineListing } from '../model/LibraryModels';
import { ImportIssue, LegadoBookSource, optionalText, prepareSourceImport, SourceImportReport, sourceEnabled, sourceKey, sourceLabel }
  from '../model/LegadoBookSource';
import { BookSource } from '../source/BookSource';
import { RequestGroup, SiteReader } from '../source/SiteReader';
import { LogLevel, newTraceId, SourceLog, SourceTrace } from '../storage/SourceLog';
import { errorMessage, ReaderLibrary } from './ReaderLibrary';

export class SearchOutcome {
  sourceName: string;
  results: OnlineListing[];
  problem: string;

  constructor(sourceName: string, results: OnlineListing[], problem: string = '') {
    this.sourceName = sourceName;
    this.results = results;
    this.problem = problem;
  }
}

export class SourceCheck {
  stage: string;
  successful: boolean;
  detail: string;

  constructor(stage: string, successful: boolean, detail: string) {
    this.stage = stage;
    this.successful = successful;
    this.detail = detail;
  }
}

export class SourceImportSummary {
  readonly total: number;
  readonly added: number;
  readonly updated: number;
  readonly repeated: number;
  readonly issues: ImportIssue[];

  constructor(batch: SourceImportReport, updated: number) {
    this.total = batch.sources.length;
    this.added = this.total - updated;
    this.updated = updated;
    this.repeated = batch.repeated;
    this.issues = batch.issues;
  }
}

export async function importSources(library: ReaderLibrary, uri: string): Promise<SourceImportSummary> {
  const batch: SourceImportReport = prepareSourceImport(await library.files.sourceJson(uri));
  const updated: number = await library.store.saveSources(batch.sources);
  const summary: SourceImportSummary = new SourceImportSummary(batch, updated);
  library.sourceLog.trace(newTraceId()).event(LogLevel.Info, '书源导入',
    '新增 ' + summary.added + '，更新 ' + summary.updated + '，格式错误 ' + summary.issues.length);
  return summary;
}

export function searchTargets(sources: LegadoBookSource[], log: SourceLog, run: string): BookSource[] {
  const ready: BookSource[] = [];
  let enabled: number = 0;
  let incomplete: number = 0;
  let unsupported: number = 0;
  for (const source of sources) {
    if (!sourceEnabled(source)) {
      continue;
    }
    enabled++;
    if (optionalText(source.searchUrl).length === 0 || !source.ruleSearch) {
      incomplete++;
      continue;
    }
    try {
      const runtime: BookSource = new BookSource(source);
      runtime.compileSearch();
      ready.push(runtime);
    } catch (error) {
      unsupported++;
      log.trace(run, sourceLabel(source), sourceKey(source)).event(LogLevel.Warning, '搜索/兼容性',
        safeFailure(error as Error));
    }
  }
  log.trace(run).event(LogLevel.Info, '搜书批次', '书源 ' + sources.length + '，已启用 ' + enabled +
    '，参与搜索 ' + ready.length + '，缺少搜索规则 ' + incomplete + '，规则暂不能执行 ' + unsupported);
  return ready;
}

export async function searchSources(
  sources: BookSource[],
  keyword: string,
  group: RequestGroup,
  log: SourceLog,
  onResult: (outcome: SearchOutcome) => void
): Promise<void> {
  let next: number = 0;
  const worker = async (): Promise<void> => {
    while (!group.isCanceled() && next < sources.length) {
      const item: BookSource = sources[next++];
      let outcome: SearchOutcome;
      const trace: SourceTrace = log.trace(group.id, item.label, item.key);
      try {
        const results: OnlineListing[] = await new SiteReader(item, group, trace).search(keyword);
        outcome = new SearchOutcome(item.label, results);
      } catch (error) {
        if (!group.isCanceled()) {
          trace.event(LogLevel.Warning, '搜索/失败', safeFailure(error as Error));
        }
        outcome = new SearchOutcome(item.label, [], errorMessage(error as Error, '搜索失败'));
      }
      if (!group.isCanceled()) {
        onResult(outcome);
      }
    }
  };

  const pending: Promise<void>[] = [];
  for (let index: number = 0; index < Math.min(sources.length, 4); index++) {
    pending.push(worker());
  }
  await Promise.all(pending);
  log.trace(group.id).event(LogLevel.Info, '搜书批次', group.isCanceled() ? '已取消' : '已完成');
}

export function checkKeyword(source: LegadoBookSource): string {
  return optionalText(source.ruleSearch?.checkKeyWord).slice(0, 60);
}

export async function diagnoseSource(
  record: LegadoBookSource,
  keyword: string,
  group: RequestGroup,
  log: SourceLog,
  onUpdate: (check: SourceCheck) => void
): Promise<void> {
  let stage: string = '搜索';
  const trace: SourceTrace = log.trace(group.id, sourceLabel(record), sourceKey(record));
  try {
    const site: SiteReader = new SiteReader(new BookSource(record), group, trace);
    const hits: OnlineListing[] = await site.search(keyword);
    if (hits.length === 0) {
      throw new Error('没有提取到结果。请换一个站点能搜到的书名，或检查 ruleSearch.bookList');
    }
    onUpdate(new SourceCheck(stage, true, '找到 ' + hits.length + ' 本，已选《' + hits[0].title + '》继续测试'));

    stage = '详情';
    const info: OnlineListing = await site.details(hits[0]);
    onUpdate(new SourceCheck(stage, true, '《' + info.title + '》'));

    stage = '目录';
    const catalog: OnlineChapter[] = await site.catalog(info.tocUrl, info.ruleValues);
    onUpdate(new SourceCheck(stage, true, '提取 ' + catalog.length + ' 章'));

    stage = '正文';
    const text: string = await site.chapter(catalog[0].url, catalog.length > 1 ? catalog[1].url : '', info.ruleValues);
    onUpdate(new SourceCheck(stage, true, '「' + catalog[0].title + '」提取 ' + text.length + ' 字符'));
  } catch (error) {
    if (!group.isCanceled()) {
      trace.event(LogLevel.Warning, stage + '/测试失败', safeFailure(error as Error));
      onUpdate(new SourceCheck(stage, false, errorMessage(error as Error, '书源测试失败')));
    }
  }
}

export async function fetchListing(
  library: ReaderLibrary, listing: OnlineListing, group: RequestGroup
): Promise<OnlineListing> {
  const source: BookSource = await activeSource(library, listing.sourceKey);
  return new SiteReader(source, group, library.sourceLog.trace(group.id, source.label, source.key)).details(listing);
}

export async function loadOnlineCatalog(
  library: ReaderLibrary, book: Book, group: RequestGroup = new RequestGroup()
): Promise<Chapter[]> {
  const source: BookSource = await activeSource(library, book.sourceKey);
  const site: SiteReader = new SiteReader(source, group, library.sourceLog.trace(group.id, source.label, source.key));
  let listing: OnlineListing = new OnlineListing(
    book.sourceKey, source.label, book.title, book.author, book.description, book.detailUrl, book.tocUrl, book.ruleValues
  );
  if (listing.tocUrl.length === 0) {
    listing = await site.details(listing);
  }
  const catalog: OnlineChapter[] = await site.catalog(listing.tocUrl, listing.ruleValues);
  const current: Book = await library.store.saveOnline(listing, catalog);
  return library.store.chapters(current.id);
}

export async function loadChapterText(
  library: ReaderLibrary, book: Book, chapter: Chapter, nextUrl: string, group: RequestGroup
): Promise<string> {
  if (book.kind === BookKind.Local) {
    return library.files.readLocalChapter(chapter);
  }

  try {
    const cached: string | undefined = await library.files.readCachedChapter(chapter);
    if (cached !== undefined && cached.length > 0) {
      return cached;
    }
  } catch {
    hilog.warn(0x0010, 'Jianyue', 'Cannot read the existing chapter cache');
  }

  const source: BookSource = await activeSource(library, book.sourceKey);
  const trace: SourceTrace = library.sourceLog.trace(group.id, source.label, source.key);
  const text: string = await new SiteReader(source, group, trace).chapter(chapter.url, nextUrl, book.ruleValues);
  try {
    await library.files.cacheChapter(chapter, text);
  } catch {
    hilog.warn(0x0010, 'Jianyue', 'Cannot persist a chapter to the offline cache');
  }
  return text;
}

async function activeSource(library: ReaderLibrary, key: string): Promise<BookSource> {
  const record: LegadoBookSource | undefined = await library.store.source(key);
  if (record === undefined) {
    throw new Error('这本小说的书源已移除。重新导入同一书源后可以联网加载');
  }
  if (!sourceEnabled(record)) {
    throw new Error('此书源已停用。请在书源页启用后重试');
  }
  return new BookSource(record);
}

function safeFailure(error: Error): string {
  const message: string = errorMessage(error, '书源处理失败');
  const field: RegExpMatchArray | null = message.match(
    /(?:ruleSearch|ruleBookInfo|ruleToc|ruleContent|searchUrl|header)(?:\.[a-zA-Z_][a-zA-Z0-9_]{0,32})?/);
  if (field !== null) {
    return '检查字段 ' + field[0];
  }
  const status: RegExpMatchArray | null = message.match(/^站点返回 HTTP [1-5][0-9]{2}$/);
  if (status !== null) {
    return status[0];
  }
  if (message.startsWith('网络请求失败：')) {
    return '网络请求失败，详见同批次的请求记录';
  }
  if (message.startsWith('无法解码')) {
    return '响应编码无法识别';
  }
  return '当前阶段无法完成';
}

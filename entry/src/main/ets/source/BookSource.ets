import {
  LegadoBookSource, LegadoBookInfoRule, LegadoContentRule, LegadoSearchRule, LegadoTocRule,
  optionalText, sourceKey, sourceLabel
} from '../model/LegadoBookSource';
import {
  BookRequest, compileSearchRequest, headersFrom, RequestHeader, SearchRequestTemplate, tryHttpUrl
} from './LegadoRequests';
import { compileSourceField, SourceField } from './LegadoRules';
import { compileTextCleanup, TextCleanup } from './SourceTextRule';

export class SearchRule {
  request: SearchRequestTemplate;
  list: SourceField;
  title: SourceField;
  author?: SourceField;
  intro?: SourceField;
  link: SourceField;

  constructor(request: SearchRequestTemplate, list: SourceField, title: SourceField, link: SourceField) {
    this.request = request;
    this.list = list;
    this.title = title;
    this.link = link;
  }
}

export class DetailRule {
  root?: SourceField;
  title?: SourceField;
  author?: SourceField;
  intro?: SourceField;
  tocLink?: SourceField;
}

export class TocRule {
  list: SourceField;
  title: SourceField;
  link: SourceField;
  next?: SourceField;

  constructor(list: SourceField, title: SourceField, link: SourceField) {
    this.list = list;
    this.title = title;
    this.link = link;
  }
}

export class ContentRule {
  body: SourceField;
  next?: SourceField;
  cleanup?: TextCleanup;
  cleanupIssue: string = '';

  constructor(body: SourceField) {
    this.body = body;
  }
}

export class BookSource {
  readonly key: string;
  readonly label: string;
  readonly headers: RequestHeader[];
  private readonly document: LegadoBookSource;
  private readonly base: string;
  private searchPlan?: SearchRule;

  constructor(document: LegadoBookSource) {
    if (typeof document.bookSourceType === 'number' && document.bookSourceType !== 0) {
      throw new Error('此源的 bookSourceType 不是文字小说');
    }
    this.document = document;
    this.key = sourceKey(document);
    this.label = sourceLabel(document);
    this.base = tryHttpUrl(this.key, '');
    this.headers = headersFrom(document.header);
  }

  compileSearch(): SearchRule {
    if (this.searchPlan !== undefined) {
      return this.searchPlan;
    }
    const raw: string = optionalText(this.document.searchUrl);
    const fields: LegadoSearchRule | null | undefined = this.document.ruleSearch;
    if (raw.length === 0 || fields === null || fields === undefined) {
      throw new Error('缺少 searchUrl 或 ruleSearch');
    }
    const plan: SearchRule = new SearchRule(
      this.searchTemplate(raw),
      requiredRule(fields.bookList, 'ruleSearch.bookList', 'text', true, true),
      requiredRule(fields.name, 'ruleSearch.name'),
      requiredRule(fields.bookUrl, 'ruleSearch.bookUrl', 'href')
    );
    plan.author = metadataRule(fields.author);
    plan.intro = metadataRule(fields.intro);
    this.searchPlan = plan;
    return plan;
  }

  private searchTemplate(raw: string): SearchRequestTemplate {
    try {
      return compileSearchRequest(raw, this.base);
    } catch (error) {
      throw new Error('searchUrl · ' + ((error as Error).message || '搜索请求暂不能运行'));
    }
  }

  searchRequest(rule: SearchRule, keyword: string): BookRequest {
    return rule.request.build(this.base, keyword);
  }

  compileDetails(): DetailRule {
    const fields: LegadoBookInfoRule | null | undefined = this.document.ruleBookInfo;
    const rule: DetailRule = new DetailRule();
    if (fields !== null && fields !== undefined) {
      rule.root = optionalRule(fields.init, 'ruleBookInfo.init', 'text', true);
      rule.title = metadataRule(fields.name);
      rule.author = metadataRule(fields.author);
      rule.intro = metadataRule(fields.intro);
      rule.tocLink = optionalRule(fields.tocUrl, 'ruleBookInfo.tocUrl', 'href');
    }
    return rule;
  }

  compileToc(): TocRule {
    const fields: LegadoTocRule | null | undefined = this.document.ruleToc;
    if (fields === undefined || fields === null) {
      throw new Error('缺少 ruleToc');
    }
    if (optionalText(fields.preUpdateJs).length > 0 || optionalText(fields.formatJs).length > 0) {
      throw new Error('ruleToc 包含目录脚本');
    }
    const rule: TocRule = new TocRule(
      requiredRule(fields.chapterList, 'ruleToc.chapterList', 'text', true, true),
      requiredRule(fields.chapterName, 'ruleToc.chapterName'),
      requiredRule(fields.chapterUrl, 'ruleToc.chapterUrl', 'href')
    );
    rule.next = optionalRule(fields.nextTocUrl, 'ruleToc.nextTocUrl', 'href');
    return rule;
  }

  compileContent(): ContentRule {
    const fields: LegadoContentRule | null | undefined = this.document.ruleContent;
    if (fields === undefined || fields === null) {
      throw new Error('缺少 ruleContent');
    }
    if (optionalText(fields.webJs).length > 0 || optionalText(fields.sourceRegex).length > 0) {
      throw new Error('ruleContent.webJs 或 sourceRegex 需要网页脚本取数');
    }
    const rule: ContentRule = new ContentRule(requiredRule(fields.content, 'ruleContent.content'));
    rule.next = optionalRule(fields.nextContentUrl, 'ruleContent.nextContentUrl', 'href');
    const cleanup: string = optionalText(fields.replaceRegex);
    if (cleanup.length > 0) {
      try {
        if (/@js:|<\s*\/?js\b/i.test(cleanup)) {
          throw new Error('清理规则需要执行书源脚本');
        }
        rule.cleanup = compileTextCleanup(cleanup.startsWith('##') ? cleanup.slice(2) : cleanup);
      } catch (error) {
        rule.cleanupIssue = 'ruleContent.replaceRegex · ' + ((error as Error).message || '正文清理规则暂不能运行');
      }
    }
    return rule;
  }
}

export class SourceAvailability {
  readonly source: LegadoBookSource;
  readonly hasSearch: boolean;
  readonly searchIssue: string;
  readonly detailIssue: string;
  readonly tocIssue: string;
  readonly contentIssue: string;

  constructor(source: LegadoBookSource, hasSearch: boolean, searchIssue: string,
    detailIssue: string, tocIssue: string, contentIssue: string) {
    this.source = source;
    this.hasSearch = hasSearch;
    this.searchIssue = searchIssue;
    this.detailIssue = detailIssue;
    this.tocIssue = tocIssue;
    this.contentIssue = contentIssue;
  }

  get readingIssue(): string {
    return this.detailIssue || this.tocIssue || this.contentIssue;
  }
}

export function assessSource(source: LegadoBookSource): SourceAvailability {
  const hasSearch: boolean = optionalText(source.searchUrl).length > 0 && !!source.ruleSearch;
  const missing: string = '缺少 searchUrl 或 ruleSearch';
  let runtime: BookSource;
  try {
    runtime = new BookSource(source);
  } catch (error) {
    const issue: string = (error as Error).message || '书源设置暂不能运行';
    return new SourceAvailability(source, hasSearch, hasSearch ? issue : missing, issue, issue, issue);
  }
  return new SourceAvailability(source, hasSearch,
    hasSearch ? ruleIssue(() => { runtime.compileSearch(); }) : missing,
    ruleIssue(() => { runtime.compileDetails(); }),
    ruleIssue(() => { runtime.compileToc(); }),
    ruleIssue(() => { runtime.compileContent(); }));
}

function ruleIssue(compile: () => void): string {
  try {
    compile();
    return '';
  } catch (error) {
    return (error as Error).message || '规则暂不能运行';
  }
}

function requiredRule(raw: string | null | undefined, path: string, output: string = 'text',
  list: boolean = false, reverse: boolean = false): SourceField {
  const expression: string = optionalText(raw);
  if (expression.length === 0) {
    throw new Error('缺少 ' + path);
  }
  try {
    return compileSourceField(expression, output, list, reverse);
  } catch (error) {
    throw new Error(path + ' · ' + ((error as Error).message || '规则暂不能运行'));
  }
}

function optionalRule(raw: string | null | undefined, path: string, output: string = 'text',
  list: boolean = false): SourceField | undefined {
  return optionalText(raw).length > 0 ? requiredRule(raw, path, output, list) : undefined;
}

function metadataRule(raw: string | null | undefined): SourceField | undefined {
  const expression: string = optionalText(raw);
  if (expression.length === 0) {
    return undefined;
  }
  try {
    return compileSourceField(expression);
  } catch {
    // Optional display metadata can use the values already available from search.
    return undefined;
  }
}

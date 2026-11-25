export type JsonValue = Object | string | number | boolean | null;
export type JsonObject = Record<string, JsonValue | undefined>;

export interface LegadoListRule {
  bookList?: string | null;
  name?: string | null;
  author?: string | null;
  intro?: string | null;
  kind?: string | null;
  lastChapter?: string | null;
  coverUrl?: string | null;
  bookUrl?: string | null;
  wordCount?: string | null;
}

export interface LegadoSearchRule extends LegadoListRule {
  checkKeyWord?: string | null;
}

export interface LegadoBookInfoRule {
  init?: string | null;
  name?: string | null;
  author?: string | null;
  intro?: string | null;
  kind?: string | null;
  lastChapter?: string | null;
  coverUrl?: string | null;
  tocUrl?: string | null;
  wordCount?: string | null;
  canReName?: string | null;
}

export interface LegadoTocRule {
  chapterList?: string | null;
  chapterName?: string | null;
  chapterUrl?: string | null;
  isVolume?: string | null;
  isVip?: string | null;
  isPay?: string | null;
  updateTime?: string | null;
  nextTocUrl?: string | null;
  preUpdateJs?: string | null;
  formatJs?: string | null;
}

export interface LegadoContentRule {
  content?: string | null;
  nextContentUrl?: string | null;
  webJs?: string | null;
  sourceRegex?: string | null;
  replaceRegex?: string | null;
  imageStyle?: string | null;
  imageDecode?: string | null;
  payAction?: string | null;
}

export interface LegadoBookSource {
  bookSourceUrl: string;
  bookSourceName: string;
  bookSourceGroup?: string | null;
  bookUrlPattern?: string | null;
  jsLib?: string | null;
  concurrentRate?: string | null;
  loginUrl?: string | null;
  loginUi?: string | null;
  loginCheckJs?: string | null;
  coverDecodeJs?: string | null;
  bookSourceComment?: string | null;
  variableComment?: string | null;
  exploreUrl?: string | null;
  exploreScreen?: string | null;
  searchUrl?: string | null;
  mainJs?: string | null;
  enabled?: boolean | null;
  enabledExplore?: boolean | null;
  enabledCookieJar?: boolean | null;
  eventListener?: boolean | null;
  customButton?: boolean | null;
  bookSourceType?: number | null;
  customOrder?: number | null;
  lastUpdateTime?: number | null;
  respondTime?: number | null;
  weight?: number | null;
  header?: string | JsonObject | null;
  ruleSearch?: LegadoSearchRule | null;
  ruleExplore?: LegadoListRule | null;
  ruleBookInfo?: LegadoBookInfoRule | null;
  ruleToc?: LegadoTocRule | null;
  ruleContent?: LegadoContentRule | null;
}

const MAX_SOURCE_COUNT: number = 6000;
const MAX_DOCUMENT_UNITS: number = 450000;
const SOURCE_STRINGS: string[] = ['bookSourceGroup', 'bookUrlPattern', 'jsLib', 'concurrentRate', 'loginUrl', 'loginUi', 'loginCheckJs', 'coverDecodeJs', 'bookSourceComment', 'variableComment', 'exploreUrl', 'exploreScreen', 'searchUrl', 'mainJs'];
const SOURCE_BOOLEANS: string[] = ['enabled', 'enabledExplore', 'enabledCookieJar', 'eventListener', 'customButton'];
const SOURCE_INTEGERS: string[] = ['bookSourceType', 'customOrder', 'lastUpdateTime', 'respondTime', 'weight'];
const LIST_FIELDS: string[] = ['bookList', 'name', 'author', 'intro', 'kind', 'lastChapter', 'coverUrl', 'bookUrl', 'wordCount'];
const BOOK_INFO_FIELDS: string[] = ['init', 'name', 'author', 'intro', 'kind', 'lastChapter', 'coverUrl', 'tocUrl', 'wordCount', 'canReName'];
const TOC_FIELDS: string[] = ['chapterList', 'chapterName', 'chapterUrl', 'isVolume', 'isVip', 'isPay', 'updateTime', 'nextTocUrl', 'preUpdateJs', 'formatJs'];
const CONTENT_FIELDS: string[] = ['content', 'nextContentUrl', 'webJs', 'sourceRegex', 'replaceRegex', 'imageStyle', 'imageDecode', 'payAction'];

export class ImportIssue {
  index: number;
  label: string;
  reason: string;

  constructor(index: number, label: string, reason: string) {
    this.index = index;
    this.label = label;
    this.reason = reason;
  }
}

export class SourceImportReport {
  sources: LegadoBookSource[] = [];
  issues: ImportIssue[] = [];
  repeated: number = 0;
}

export function sourceKey(source: LegadoBookSource): string {
  return source.bookSourceUrl.trim();
}

export function sourceEnabled(source: LegadoBookSource): boolean {
  return source.enabled !== false;
}

export function sourceLabel(source: LegadoBookSource): string {
  return source.bookSourceName.trim();
}

export function optionalText(text: string | null | undefined): string {
  return typeof text === 'string' ? text.trim() : '';
}

export function parseJson(text: string, description: string): JsonValue {
  try {
    return JSON.parse(text.trim()) as JsonValue;
  } catch {
    throw new Error(description);
  }
}

export function jsonRecord(value: JsonValue | undefined): JsonObject | undefined {
  if (value !== undefined && value !== null && typeof value === 'object' && !Array.isArray(value)) {
    return value as JsonObject;
  }
  return undefined;
}

export function decodeSourceDocument(text: string): LegadoBookSource {
  return validateSource(parseJson(text, '书源记录不是有效的 JSON'), false);
}

export function prepareSourceImport(text: string): SourceImportReport {
  const root: JsonValue = parseJson(text, '书源文件不是有效的 JSON。请选用 Legado 3.0 的书源导出文件。');
  const items: JsonValue[] = Array.isArray(root) ? root as JsonValue[] : [root];
  if (items.length === 0) {
    throw new Error('这份 JSON 书源数组为空');
  }
  if (items.length > MAX_SOURCE_COUNT) {
    throw new Error('一次最多导入 6000 条书源');
  }
  const report: SourceImportReport = new SourceImportReport();
  const sources: Map<string, LegadoBookSource> = new Map<string, LegadoBookSource>();
  for (let index: number = 0; index < items.length; index++) {
    const candidate: JsonObject | undefined = jsonRecord(items[index]);
    const name: JsonValue | undefined = candidate?.['bookSourceName'];
    const label: string = typeof name === 'string' && name.trim().length > 0
      ? name.trim().slice(0, 96) : '第 ' + (index + 1) + ' 条';
    try {
      const source: LegadoBookSource = validateSource(items[index]);
      if (JSON.stringify(source).length > MAX_DOCUMENT_UNITS) {
        throw new Error('单条书源配置过大');
      }
      const key: string = sourceKey(source);
      if (sources.has(key)) {
        report.repeated++;
      }
      sources.set(key, source);
    } catch (error) {
      report.issues.push(new ImportIssue(index, label, (error as Error).message || '格式不符合 Legado 3.0'));
    }
  }
  report.sources = Array.from(sources.values());
  return report;
}

function validateSource(input: JsonValue, validateOptional: boolean = true): LegadoBookSource {
  const record: JsonObject | undefined = jsonRecord(input);
  if (record === undefined) {
    throw new Error('每条书源需要是一个 JSON 对象');
  }

  requireText(record['bookSourceUrl'], 'bookSourceUrl');
  requireText(record['bookSourceName'], 'bookSourceName');
  if (!validateOptional) {
    // Older builds accepted additional optional fields without type constraints.
    return input as LegadoBookSource;
  }
  checkFields(record, SOURCE_STRINGS, 'string', '');
  checkFields(record, SOURCE_BOOLEANS, 'boolean', '');
  checkFields(record, SOURCE_INTEGERS, 'integer', '');

  const header: JsonValue | undefined = record['header'];
  if (header !== undefined && header !== null && typeof header !== 'string' && jsonRecord(header) === undefined) {
    throw new Error('header 需要是文本或 JSON 对象');
  }
  checkRule(record, 'ruleSearch', LIST_FIELDS.concat(['checkKeyWord']));
  checkRule(record, 'ruleExplore', LIST_FIELDS);
  checkRule(record, 'ruleBookInfo', BOOK_INFO_FIELDS);
  checkRule(record, 'ruleToc', TOC_FIELDS);
  checkRule(record, 'ruleContent', CONTENT_FIELDS);

  // Keep the validated JSON object itself so optional and extension properties survive persistence.
  return input as LegadoBookSource;
}

function requireText(value: JsonValue | undefined, name: string): void {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new Error('缺少有效的 ' + name);
  }
}

function checkRule(parent: JsonObject, key: string, names: string[]): void {
  const value: JsonValue | undefined = parent[key];
  if (value === undefined || value === null) {
    return;
  }
  const rule: JsonObject | undefined = jsonRecord(value);
  if (rule === undefined) {
    throw new Error(key + ' 需要是 JSON 对象');
  }
  checkFields(rule, names, 'string', key + '.');
}

function checkFields(record: JsonObject, fields: string[], expected: string, prefix: string): void {
  for (const field of fields) {
    const value: JsonValue | undefined = record[field];
    if (value === undefined || value === null) {
      continue;
    }
    const valid: boolean = expected === 'integer'
      ? typeof value === 'number' && Number.isSafeInteger(value)
      : typeof value === expected;
    if (!valid) {
      const typeName: string = expected === 'integer' ? '整数' : expected === 'boolean' ? '布尔值' : '文本';
      throw new Error(prefix + field + ' 需要是' + typeName);
    }
  }
}

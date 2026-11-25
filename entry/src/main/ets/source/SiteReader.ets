import { BusinessError } from '@kit.BasicServicesKit';
import { rcp } from '@kit.RemoteCommunicationKit';
import { OnlineChapter, OnlineListing } from '../model/LibraryModels';
import { decodeText } from '../novel/TextNovel';
import { JsonValue, parseJson } from '../model/LegadoBookSource';
import { LogLevel, newTraceId, SourceTrace } from '../storage/SourceLog';
import { BookSource, ContentRule, DetailRule, SearchRule, TocRule } from './BookSource';
import { BookRequest, compilePageRequest, resolveHttpUrl, tryBookUrl, tryHttpUrl } from './LegadoRequests';
import { RuleTarget, SourceField } from './LegadoRules';
import { RuleVariables } from './RuleVariables';
import { compileRule } from './CssRules';
import { HtmlDocument, nodeText } from './HtmlDocument';

const MAX_PAGE_BYTES: number = 4 * 1024 * 1024;
const MAX_CATALOG_PAGES: number = 40;
const MAX_BODY_PAGES: number = 12;
const MAX_BODY_CHARS: number = 200000;
const MAX_TOC_ITEMS: number = 10000;
const MAX_SEARCH_RESULTS: number = 60;
const BASE_NODE = compileRule('base[href]@href', 'href');

export class RequestGroup {
  readonly id: string = newTraceId();
  private sessions: Set<rcp.Session> = new Set<rcp.Session>();
  private canceled: boolean = false;

  isCanceled(): boolean {
    return this.canceled;
  }

  track(session: rcp.Session): void {
    if (this.canceled) {
      session.close();
      throw new Error('请求已取消');
    }
    this.sessions.add(session);
  }

  release(session: rcp.Session): void {
    if (this.sessions.delete(session)) {
      try {
        session.close();
      } catch {
        // Session cleanup should not replace the result of a request.
      }
    }
  }

  cancel(): void {
    this.canceled = true;
    for (const session of this.sessions) {
      try {
        session.close();
      } catch {
        // An already completed request can be released independently.
      }
    }
    this.sessions.clear();
  }
}

class SitePage {
  root: RuleTarget;
  address: string;
  linkBase: string;

  constructor(root: RuleTarget, address: string) {
    this.root = root.withAddress(address);
    this.address = address;
    const declared: string = root.html !== undefined ? BASE_NODE.first(root.html) : '';
    this.linkBase = tryHttpUrl(declared, address) || address;
  }
}

export class SiteReader {
  private source: BookSource;
  private group: RequestGroup;
  private trace?: SourceTrace;

  constructor(source: BookSource, group: RequestGroup = new RequestGroup(), trace?: SourceTrace) {
    this.source = source;
    this.group = group;
    this.trace = trace;
  }

  async search(keyword: string): Promise<OnlineListing[]> {
    const rule: SearchRule = this.source.compileSearch();
    const page: SitePage = await this.fetch(this.source.searchRequest(rule, keyword), '搜索');
    const results: OnlineListing[] = [];
    const known: Set<string> = new Set<string>();
    const items: RuleTarget[] = rule.list.nodes(page.root);
    let missingTitle: number = 0;
    let invalidLink: number = 0;
    let malformed: number = 0;
    const searchVariables: string = page.root.variables.serialize();
    for (const candidate of items) {
      const item: RuleTarget = candidate.withVariables(new RuleVariables(searchVariables));
      let title: string;
      let link: string;
      const author: string = optionalField(rule.author, item);
      const intro: string = optionalField(rule.intro, item);
      try {
        title = singleLine(rule.title.first(item));
        link = tryBookUrl(rule.link.first(item), page.linkBase);
      } catch {
        malformed++;
        continue;
      }
      if (title.length === 0) {
        missingTitle++;
      }
      if (link.length === 0) {
        invalidLink++;
      }
      if (title.length > 0 && link.length > 0 && !known.has(link)) {
        results.push(new OnlineListing(this.source.key, this.source.label, title.slice(0, 150),
          singleLine(author).slice(0, 100), intro.slice(0, 5000), link, '', item.variables.serialize()));
        known.add(link);
        if (results.length === MAX_SEARCH_RESULTS) {
          break;
        }
      }
    }
    this.trace?.event(results.length > 0 ? LogLevel.Info : LogLevel.Warning, '搜索/提取',
      '候选 ' + items.length + '，有效 ' + results.length + '，缺书名 ' + missingTitle +
      '，缺有效链接 ' + invalidLink + '，提取异常 ' + malformed, page.address);
    if (items.length > 0 && results.length === 0) {
      throw new Error('ruleSearch.name 或 ruleSearch.bookUrl 未提取到有效书名和详情地址');
    }
    return results;
  }

  async details(listing: OnlineListing): Promise<OnlineListing> {
    const rule: DetailRule = this.source.compileDetails();
    const request: BookRequest = compilePageRequest(listing.detailUrl);
    const page: SitePage = await this.fetch(request, '详情');
    const target: RuleTarget = page.root.withVariables(new RuleVariables(listing.ruleValues));
    const selected: RuleTarget | undefined = rule.root?.nodes(target)[0];
    if (rule.root !== undefined && selected === undefined) {
      throw new Error('ruleBookInfo.init 未匹配到详情节点');
    }
    const root: RuleTarget = selected ?? target;
    const title: string = singleLine(optionalField(rule.title, root));
    const author: string = singleLine(optionalField(rule.author, root));
    const introduction: string = optionalField(rule.intro, root);
    const raw: string = rule.tocLink?.first(root) ?? '';
    const defaultToc: string = request.post || request.headers.length > 0 || request.charset.length > 0 ?
      listing.detailUrl : page.address;
    const toc: string = raw.length > 0 ? tryBookUrl(raw, page.linkBase) : defaultToc;
    if (toc.length === 0) {
      throw new Error('ruleBookInfo.tocUrl 提取出的目录地址无效');
    }
    this.trace?.event(LogLevel.Info, '详情/提取', '已解析书籍信息与目录入口', page.address);
    return new OnlineListing(listing.sourceKey, listing.sourceName, (title || listing.title).slice(0, 150),
      (author || listing.author).slice(0, 100), (introduction || listing.description).slice(0, 5000),
      listing.detailUrl, toc, root.variables.serialize());
  }

  async catalog(tocAddress: string, ruleValues: string = ''): Promise<OnlineChapter[]> {
    const rule: TocRule = this.source.compileToc();
    const catalog: OnlineChapter[] = [];
    const visited: Set<string> = new Set<string>();
    const chapters: Set<string> = new Set<string>();
    let current: string = tocAddress;
    const variables: RuleVariables = new RuleVariables(ruleValues);
    while (current.length > 0) {
      if (visited.size >= MAX_CATALOG_PAGES) {
        throw new Error('目录分页超过 40 页，请检查 ruleToc.nextTocUrl');
      }
      if (visited.has(current)) {
        throw new Error('ruleToc.nextTocUrl 出现循环');
      }
      visited.add(current);
      const page: SitePage = await this.fetch(compilePageRequest(current), '目录');
      const target: RuleTarget = page.root.withVariables(variables);
      const items: RuleTarget[] = rule.list.nodes(target, false);
      const saved: string = variables.serialize();
      for (const candidate of items) {
        const item: RuleTarget = candidate.withVariables(new RuleVariables(saved));
        const title: string = singleLine(rule.title.first(item));
        const link: string = tryBookUrl(rule.link.first(item), page.linkBase);
        if (title.length > 0 && link.length > 0 && !chapters.has(link)) {
          catalog.push(new OnlineChapter(title.slice(0, 180), link));
          chapters.add(link);
          if (catalog.length > MAX_TOC_ITEMS) {
            throw new Error('目录提取结果超过 10000 章');
          }
        }
      }
      const next: string = tryBookUrl(rule.next?.first(target) ?? '', page.linkBase);
      current = next === current || next === page.address ? '' : next;
    }
    this.trace?.event(catalog.length > 0 ? LogLevel.Info : LogLevel.Warning, '目录/提取',
      '访问 ' + visited.size + ' 页，得到 ' + catalog.length + ' 章', tocAddress);
    if (catalog.length === 0) {
      throw new Error('ruleToc.chapterList、chapterName 或 chapterUrl 没有提取到可用章节');
    }
    return rule.list.reversesOrder() ? catalog.reverse() : catalog;
  }

  async chapter(address: string, nextChapter: string = '', ruleValues: string = ''): Promise<string> {
    const rule: ContentRule = this.source.compileContent();
    const visited: Set<string> = new Set<string>();
    const body: string[] = [];
    let current: string = address;
    const variables: RuleVariables = new RuleVariables(ruleValues);
    let size: number = 0;
    while (current.length > 0) {
      if (visited.size >= MAX_BODY_PAGES) {
        throw new Error('正文分页超过 12 页，请检查 ruleContent.nextContentUrl');
      }
      if (visited.has(current)) {
        throw new Error('ruleContent.nextContentUrl 出现循环');
      }
      visited.add(current);
      const page: SitePage = await this.fetch(compilePageRequest(current), '正文');
      const target: RuleTarget = page.root.withVariables(variables);
      const raw: string = rule.body.allText(target).trim();
      const segment: string = page.root.html === undefined && /<(?:p\b|br[\s/>]|div\b|article\b)/i.test(raw)
        ? nodeText(HtmlDocument.parse(raw).root) : raw;
      if (segment.length === 0) {
        throw new Error('ruleContent.content 没有匹配到正文');
      }
      size += segment.length;
      if (size > MAX_BODY_CHARS) {
        throw new Error('这一章超过 20 万字，无法载入');
      }
      body.push(segment);
      const next: string = tryBookUrl(rule.next?.first(target) ?? '', page.linkBase);
      current = next === current || next === nextChapter || next === page.address ? '' : next;
    }
    let result: string = body.join('\n\n');
    if (rule.cleanupIssue.length > 0) {
      this.trace?.event(LogLevel.Warning, '正文/清理', rule.cleanupIssue, address);
    }
    try {
      const cleaned: string = rule.cleanup?.apply(result).trim() ?? result;
      if (cleaned.length > 0) {
        result = cleaned;
      }
    } catch {
      this.trace?.event(LogLevel.Warning, '正文/清理', 'ruleContent.replaceRegex 未应用，已保留提取的正文', address);
    }
    this.trace?.event(LogLevel.Info, '正文/提取', '访问 ' + visited.size + ' 页，得到 ' + result.length + ' 字符', address);
    return result;
  }

  private async fetch(request: BookRequest, phase: string): Promise<SitePage> {
    const requested: string = resolveHttpUrl(request.address);
    const method: string = request.post ? 'POST' : 'GET';
    const start: number = Date.now();
    const headers: rcp.RequestHeaders = {
      'accept': 'text/html,application/json,application/xhtml+xml,text/plain;q=0.9,*/*;q=0.2',
      'user-agent': 'Jianyue/0.4.0 (HarmonyOS)'
    };
    for (const header of this.source.headers.concat(request.headers)) {
      headers[header.name] = header.value;
    }
    if (request.post && headers['content-type'] === undefined) {
      headers['content-type'] = 'application/x-www-form-urlencoded';
    }
    const settings: rcp.SessionConfiguration = {
      headers: headers,
      requestConfiguration: {
        transfer: {
          autoRedirect: true,
          maxAutoRedirects: 5,
          timeout: { connectMs: 5500, transferMs: 12000, inactivityMs: 6000 }
        }
      }
    };
    const session: rcp.Session = rcp.createSession(settings);
    this.group.track(session);
    try {
      let received: rcp.Response;
      try {
        received = request.post ? await session.fetch(new rcp.Request(requested, 'POST', headers, request.body))
          : await session.get(requested);
      } catch (error) {
        if (this.group.isCanceled()) {
          throw new Error('请求已取消');
        }
        const failure: string = networkFailure(error as BusinessError);
        this.trace?.event(LogLevel.Error, phase + '/请求', method + ' · ' + failure +
          ' · ' + (Date.now() - start) + ' ms', requested);
        throw new Error(failure);
      }
      const buffer: ArrayBuffer | undefined = received.body;
      const contentType: string = responseHeader(received.headers, 'content-type');
      const mediaType: string = contentType.toLowerCase().match(/^[a-z0-9.+-]+\/[a-z0-9.+-]+/)?.[0] ?? '未知类型';
      const httpOkay: boolean = received.statusCode >= 200 && received.statusCode < 300;
      this.trace?.event(httpOkay ? LogLevel.Info : LogLevel.Warning, phase + '/HTTP', method + ' HTTP ' +
        received.statusCode + ' · ' + mediaType + ' · ' + (buffer?.byteLength ?? 0) + ' 字节 · ' +
        (Date.now() - start) + ' ms', requested);
      if (!httpOkay) {
        throw new Error('站点返回 HTTP ' + received.statusCode);
      }
      if (!buffer || buffer.byteLength === 0) {
        throw new Error('站点返回了空页面');
      }
      if (buffer.byteLength > MAX_PAGE_BYTES) {
        throw new Error('响应页面超过 4 MB');
      }
      const resolved: string = resolveHttpUrl(received.effectiveUrl?.href ?? requested);
      const bytes: Uint8Array = new Uint8Array(buffer);
      const charset: string = findCharset(contentType, bytes) || request.charset;
      let decoded: string;
      try {
        decoded = decodeText(bytes, charset);
      } catch {
        this.trace?.event(LogLevel.Error, phase + '/解码', '无法解码页面 · 声明编码 ' +
          (charset || '未指定'), resolved);
        throw new Error('无法解码站点页面，请检查响应编码');
      }
      let root: RuleTarget;
      try {
        root = pageTarget(decoded, contentType);
      } catch {
        this.trace?.event(LogLevel.Error, phase + '/解析', '响应无法按 ' + mediaType + ' 解析', resolved);
        throw new Error('站点页面格式无法解析');
      }
      this.trace?.event(LogLevel.Info, phase + '/解析', (root.html === undefined ? 'JSON' : 'HTML') +
        ' · 声明编码 ' + (charset || '未指定') + ' · ' + decoded.length + ' 字符', resolved);
      return new SitePage(root, resolved);
    } finally {
      this.group.release(session);
    }
  }
}

function responseHeader(headers: rcp.ResponseHeaders, name: string): string {
  for (const key of Object.keys(headers)) {
    if (key.toLowerCase() !== name) {
      continue;
    }
    // The RCP response header map can contain an array even for Content-Type.
    const raw: string | string[] | undefined = headers[key];
    if (typeof raw === 'string' && raw.trim().length > 0) {
      return raw.trim();
    }
    if (Array.isArray(raw)) {
      for (let index: number = raw.length - 1; index >= 0; index--) {
        const value: string = raw[index];
        if (typeof value === 'string' && value.trim().length > 0) {
          return value.trim();
        }
      }
    }
  }
  return '';
}

function networkFailure(error: BusinessError): string {
  const code: number = Number.isFinite(error.code) ? error.code : 0;
  const message: string = typeof error.message === 'string' ? error.message.toLowerCase() : '';
  let reason: string = '无法连接站点';
  if (code === 1007900201) {
    reason = '设备拒绝此 HTTP 明文请求';
  } else if (code === 1007900028 || message.includes('timeout') || message.includes('timed out')) {
    reason = '站点请求超时';
  } else if (code === 1007900006 || message.includes('resolve')) {
    reason = '无法解析站点域名';
  } else if (code === 1007900060 || message.includes('ssl') || message.includes('certificate')) {
    reason = '站点 TLS 校验失败';
  }
  return '网络请求失败：' + reason + (code !== 0 ? '（' + code + '）' : '');
}

function pageTarget(text: string, contentType: string): RuleTarget {
  const declaredJson: boolean = contentType.toLowerCase().includes('json');
  const head: string = text.trimStart();
  if (declaredJson || head.startsWith('{') || head.startsWith('[')) {
    try {
      const value: JsonValue = parseJson(text, '站点返回的 JSON 格式不正确');
      return RuleTarget.fromJson(value);
    } catch (error) {
      if (declaredJson) {
        throw error as Error;
      }
    }
  }
  return RuleTarget.fromHtml(HtmlDocument.parse(text).root);
}

function optionalField(rule: SourceField | undefined, root: RuleTarget): string {
  try {
    return rule?.first(root) ?? '';
  } catch {
    return '';
  }
}

function singleLine(input: string): string {
  return input.replace(/\s+/g, ' ').trim();
}

function findCharset(contentType: string, bytes: Uint8Array): string {
  const header: RegExpMatchArray | null = contentType.match(/charset\s*=\s*['"]?([a-zA-Z0-9_-]+)/i);
  if (header !== null) {
    return header[1];
  }
  const preview: Uint8Array = bytes.subarray(0, Math.min(bytes.length, 8192));
  let ascii: string = '';
  for (const value of preview) {
    ascii += value < 128 ? String.fromCharCode(value) : ' ';
  }
  const meta: RegExpMatchArray | null = ascii.match(/<meta\b[^>]*charset\s*=\s*['"]?\s*([a-zA-Z0-9_-]+)/i);
  return meta !== null ? meta[1] : '';
}

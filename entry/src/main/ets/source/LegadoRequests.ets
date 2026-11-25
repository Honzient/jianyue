import { url, util } from '@kit.ArkTS';
import { JsonObject, JsonValue, jsonRecord } from '../model/LegadoBookSource';
import { RAW_TEMPLATE, staticOptions } from './RequestOptions';

const BLOCKED_HEADERS: string[] = ['authorization', 'cookie', 'proxy-authorization'];
const MANAGED_HEADERS: string[] = ['connection', 'host', 'content-length', 'transfer-encoding',
  'accept-encoding', 'proxy-connection', 'upgrade', 'trailer', 'te'];
const MAX_DECLARATION: number = 16000;
const TEMPLATE: RegExp = /\{\{\s*([^{}]+?)\s*\}\}/g;

export class RequestHeader {
  name: string;
  value: string;

  constructor(name: string, value: string) {
    this.name = name;
    this.value = value;
  }
}

export class BookRequest {
  address: string;
  post: boolean;
  body: string;
  headers: RequestHeader[];
  charset: string;

  constructor(address: string, post: boolean, body: string, headers: RequestHeader[], charset: string) {
    this.address = address;
    this.post = post;
    this.body = body;
    this.headers = headers;
    this.charset = charset;
  }
}

export class SearchRequestTemplate {
  private address: string;
  private body: string;
  private jsonBody: boolean;
  private post: boolean;
  private charset: string;
  private headers: RequestHeader[];

  constructor(address: string, body: string, jsonBody: boolean, post: boolean, charset: string,
    headers: RequestHeader[]) {
    this.address = address;
    this.body = body;
    this.jsonBody = jsonBody;
    this.post = post;
    this.charset = charset;
    this.headers = headers;
  }

  build(base: string, keyword: string): BookRequest {
    const address: string = resolveHttpUrl(
      expand(this.address, encodeKeyword(keyword, this.charset || 'utf-8')), base);
    const body: string = this.jsonBody ? jsonBodyText(this.body, keyword) :
      expand(this.body, encodeKeyword(keyword, this.charset || 'utf-8', this.post));
    return new BookRequest(address, this.post, body, this.headers, this.charset);
  }
}

export function compileSearchRequest(raw: string, base: string): SearchRequestTemplate {
  // Every fetch uses a fresh session, which already has an empty source cookie jar.
  const input: string = raw.trim().replace(
    /^\{\{\s*cookie\.removeCookie\(\s*source\.getKey\(\s*\)\s*\)\s*;?\s*\}\}\s*/, '');
  return compileRequest(input, base, true);
}

export function compilePageRequest(raw: string): BookRequest {
  return compileRequest(raw.trim(), '', false).build('', '');
}

function compileRequest(input: string, base: string, searching: boolean): SearchRequestTemplate {
  if (input.length === 0 || input.length > MAX_DECLARATION) {
    throw new Error('请求地址为空或过长');
  }
  if (/@js:|<\s*\/?js\b/i.test(input)) {
    throw new Error('请求需要执行书源脚本');
  }

  const separator: number = optionStart(input);
  const address: string = (separator < 0 ? input : input.slice(0, separator)).trim();
  const options: JsonObject = separator < 0 ? {} :
    staticOptions(input.slice(separator + 1), '请求选项需要静态 JSON 对象', searching);
  for (const key of Object.keys(options)) {
    const value: JsonValue | undefined = options[key];
    if (!['method', 'charset', 'body', 'headers', 'header'].includes(key) &&
      value !== undefined && value !== null && value !== '' && value !== false) {
      const name: string = /^[\w-]{1,40}$/.test(key) ? key : '未知选项';
      throw new Error('请求选项 ' + name + ' 暂不能运行');
    }
  }

  const method: string = optionText(options, 'method').toUpperCase() || 'GET';
  if (method !== 'GET' && method !== 'POST') {
    throw new Error('请求方法支持 GET 或 POST');
  }
  const charset: string = pickCharset(optionText(options, 'charset'));
  const rawBody: JsonValue | undefined = options['body'];
  const structured: boolean = rawBody !== null && typeof rawBody === 'object';
  if (rawBody !== undefined && rawBody !== null && !structured && typeof rawBody !== 'string') {
    throw new Error('POST body 需要文本、对象或数组');
  }
  const body: string = structured ? JSON.stringify(rawBody) : (rawBody as string | null | undefined) ?? '';
  const jsonBody: boolean = structured || /^[\[{]/.test(body.trim());
  if (method === 'GET' && body.length > 0) {
    throw new Error('带 body 的请求需要 method=POST');
  }
  if (searching && !hasKeyword(address) && !hasKeyword(body)) {
    throw new Error('搜索地址或 POST body 需要包含 {{key}}');
  }
  if (!searching && (address.includes('{{') || body.includes('{{'))) {
    throw new Error('阅读地址含未解析的模板');
  }
  const headers: RequestHeader[] = headersFrom(options['headers'] ?? options['header'], '请求头');
  if (jsonBody && !headers.some((item: RequestHeader): boolean => item.name === 'content-type')) {
    headers.push(new RequestHeader('content-type', 'application/json; charset=UTF-8'));
  }
  const preview: string = expand(address, 'sample');
  if (/[{}<>\r\n]/.test(preview)) {
    throw new Error('请求地址含无效括号或换行');
  }
  const template: SearchRequestTemplate = new SearchRequestTemplate(address, body, jsonBody, method === 'POST',
    charset, headers);
  if (searching) {
    template.build(base, 'sample');
  }
  return template;
}

export function headersFrom(raw: JsonValue | undefined, label: string = 'header'): RequestHeader[] {
  if (raw === undefined || raw === null || typeof raw === 'string' && raw.trim().length === 0) {
    return [];
  }
  if (typeof raw === 'string' && /@js:|<\s*\/?js\b/i.test(raw)) {
    throw new Error(label + ' 需要执行书源脚本');
  }
  const description: string = label + ' 需要静态 JSON 请求头';
  const headers: JsonObject | undefined = typeof raw === 'string' ? staticOptions(raw, description) : jsonRecord(raw);
  if (headers === undefined) {
    throw new Error(description);
  }
  const items: RequestHeader[] = [];
  for (const key of Object.keys(headers)) {
    const name: string = key.toLowerCase();
    if (MANAGED_HEADERS.includes(name)) {
      continue;
    }
    const header: JsonValue | undefined = headers[key];
    if (header === undefined || header === null || header === '') {
      continue;
    }
    if (BLOCKED_HEADERS.includes(name)) {
      throw new Error(label + '.' + name + ' 需要登录或会话凭据');
    }
    if (typeof header !== 'string' || !/^[a-z0-9-]{1,50}$/.test(name) ||
      header.length > 4096 || /[\u0000-\u001f\u007f]|\{\{|@js:|<js>/i.test(header)) {
      throw new Error(label + ' 的字段需要静态文本值');
    }
    if (header.trim().length > 0) {
      items.push(new RequestHeader(name, header.trim()));
    }
  }
  return items;
}

export function resolveHttpUrl(input: string, base: string = ''): string {
  const value: string = input.trim();
  if (value.length === 0 || value.length > 4096 || /[\u0000-\u001f\u007f\\]/.test(value)) {
    throw new Error('地址为空、过长或包含无效字符');
  }
  let address: url.URL;
  try {
    address = base.length > 0 ? url.URL.parseURL(value, base) : url.URL.parseURL(value);
  } catch {
    throw new Error('HTTP 或 HTTPS 地址无法解析');
  }
  if ((address.protocol !== 'http:' && address.protocol !== 'https:') ||
    address.hostname.length === 0 || address.username.length > 0 || address.password.length > 0) {
    throw new Error('需要无账号密码的 HTTP 或 HTTPS 地址');
  }
  address.hash = '';
  return address.href;
}

export function tryHttpUrl(input: string, base: string): string {
  const value: string = input.trim();
  if (value.length === 0 || value.startsWith('#') || optionStart(value) >= 0) {
    return '';
  }
  try {
    return resolveHttpUrl(value, base);
  } catch {
    return '';
  }
}

export function tryBookUrl(input: string, base: string): string {
  const value: string = input.trim();
  if (value.length === 0 || value.startsWith('#') || value.length > MAX_DECLARATION) {
    return '';
  }
  const separator: number = optionStart(value);
  if (separator < 0) {
    return tryHttpUrl(value, base);
  }
  try {
    const address: string = resolveHttpUrl(value.slice(0, separator), base);
    const canonical: string = address + ',' + JSON.stringify(staticOptions(value.slice(separator + 1),
      '阅读地址的请求选项需要静态 JSON 对象'));
    compilePageRequest(canonical);
    return canonical;
  } catch {
    return '';
  }
}

function optionStart(value: string): number {
  return value.search(/,\s*\{(?!\{)/);
}

function hasKeyword(value: string): boolean {
  return /\{\{\s*(?:key|keyword)\s*\}\}/.test(value);
}

function pageValue(expression: string): string {
  const compact: string = expression.replace(/\s/g, '');
  if (compact === 'page') {
    return '1';
  }
  const arithmetic: RegExpMatchArray | null =
    compact.match(/^(?:page([+-]\d{1,5})|\(page([+-]\d{1,5})\)\*(\d{1,5}))$/);
  if (arithmetic === null) {
    if (/[a-zA-Z_]\w*\s*\(/.test(compact)) {
      throw new Error('请求模板需要调用脚本函数');
    }
    throw new Error('请求模板支持 {{key}}、{{page}} 和固定页码偏移');
  }
  return String((1 + Number(arithmetic[1] ?? arithmetic[2])) * Number(arithmetic[3] ?? '1'));
}

function tokenValue(expression: string, keyword: string): string {
  return expression === 'key' || expression === 'keyword' ? keyword : pageValue(expression);
}

function expand(value: string, keyword: string): string {
  validateTokens(value, TEMPLATE);
  return value.replace(TEMPLATE, (_token: string, expression: string): string =>
    tokenValue(expression.trim(), keyword));
}

function jsonBodyText(value: string, keyword: string): string {
  const tokens: RegExp = /"\ufdd0\{\{\s*([^{}]+?)\s*\}\}"|\{\{\s*([^{}]+?)\s*\}\}/g;
  validateTokens(value, tokens);
  const quoted: string = JSON.stringify(keyword);
  return value.replace(tokens, (_token: string, raw: string | undefined, inner: string | undefined): string => {
    const key: string = (raw ?? inner ?? '').trim();
    if (key === 'key' || key === 'keyword') {
      return raw !== undefined ? quoted : quoted.slice(1, -1);
    }
    return pageValue(key);
  });
}

function validateTokens(value: string, tokens: RegExp): void {
  const literal: string = value.replace(tokens, '');
  if (literal.includes('{{') || literal.includes(RAW_TEMPLATE)) {
    throw new Error('请求模板括号未配对');
  }
}

function optionText(options: JsonObject, key: string): string {
  const value: JsonValue | undefined = options[key];
  if (value === undefined || value === null) {
    return '';
  }
  if (typeof value !== 'string') {
    throw new Error('请求选项 ' + key + ' 需要文本');
  }
  return value.trim();
}

function pickCharset(input: string): string {
  const charset: string = input.toLowerCase();
  if (charset === '') {
    return '';
  }
  if (charset === 'utf-8' || charset === 'utf8') {
    return 'utf-8';
  }
  if (charset === 'gbk' || charset === 'gb2312' || charset === 'gb18030') {
    return 'gb18030';
  }
  throw new Error('请求编码支持 UTF-8、GBK、GB2312 和 GB18030');
}

function encodeKeyword(word: string, charset: string, form: boolean = false): string {
  if (charset === 'utf-8') {
    return form ? encodeURIComponent(word).replace(/%20/g, '+') : encodeURIComponent(word);
  }
  const bytes: Uint8Array = util.TextEncoder.create(charset).encodeInto(word);
  let result: string = '';
  for (const byte of bytes) {
    const char: string = String.fromCharCode(byte);
    result += /[a-zA-Z0-9._~-]/.test(char) ? char : byte === 32 && form ? '+' :
      '%' + byte.toString(16).padStart(2, '0').toUpperCase();
  }
  return result;
}

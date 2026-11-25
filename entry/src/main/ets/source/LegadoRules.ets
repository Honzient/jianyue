import { JsonValue } from '../model/LegadoBookSource';
import { compileRule as compileHtmlRule, compileXPathRule, FieldRule as HtmlFieldRule } from './CssRules';
import { HtmlNode } from './HtmlDocument';
import { compilePageRequest } from './LegadoRequests';
import { staticOptions } from './RequestOptions';
import { JsonPath } from './JsonPath';
import { compileResultTransform } from './ResultTransforms';
import { RuleVariables } from './RuleVariables';
import { compileTextCleanup, TextCleanup, TextTransform } from './SourceTextRule';

const MAX_SELECTED: number = 10000;
type RuleText = (root: RuleTarget) => string;

export class RuleTarget {
  readonly html?: HtmlNode;
  readonly data?: JsonValue;
  readonly variables: RuleVariables;
  readonly baseUrl: string;

  private constructor(variables: RuleVariables, baseUrl: string, html?: HtmlNode, data?: JsonValue) {
    this.baseUrl = baseUrl;
    this.variables = variables;
    this.html = html;
    this.data = data;
  }

  static fromHtml(node: HtmlNode, variables: RuleVariables = new RuleVariables()): RuleTarget {
    return new RuleTarget(variables, '', node);
  }

  static fromJson(value: JsonValue, variables: RuleVariables = new RuleVariables()): RuleTarget {
    return new RuleTarget(variables, '', undefined, value);
  }

  withAddress(address: string): RuleTarget {
    return new RuleTarget(this.variables, address, this.html, this.data);
  }

  withVariables(variables: RuleVariables): RuleTarget {
    return new RuleTarget(variables, this.baseUrl, this.html, this.data);
  }
}

class RuleAssignment {
  readonly name: string;
  readonly field: SourceField;

  constructor(name: string, field: SourceField) {
    this.name = name;
    this.field = field;
  }
}

class RuleBranches {
  readonly fields: SourceField[];
  readonly operator: string;

  constructor(fields: SourceField[], operator: string) {
    this.fields = fields;
    this.operator = operator;
  }
}

export class SourceField {
  private readonly html?: HtmlFieldRule;
  private readonly path?: JsonPath;
  private readonly render?: RuleText;
  private readonly branches?: RuleBranches;
  private reversed: boolean = false;
  private assignments: RuleAssignment[] = [];
  private transforms: TextTransform[] = [];

  constructor(html?: HtmlFieldRule, path?: JsonPath, render?: RuleText, branches?: RuleBranches) {
    this.html = html;
    this.path = path;
    this.render = render;
    this.branches = branches;
  }

  addTransform(transform: TextTransform): void {
    this.transforms.push(transform);
  }

  addAssignments(assignments: RuleAssignment[]): void {
    this.assignments = this.assignments.concat(assignments);
  }

  reverseOrder(): void {
    this.reversed = true;
  }

  reversesOrder(): boolean {
    return this.reversed;
  }

  nodes(root: RuleTarget, applyOrder: boolean = true): RuleTarget[] {
    this.assign(root);
    const nodes: RuleTarget[] = this.selectNodes(root);
    return this.reversed && applyOrder ? nodes.reverse() : nodes;
  }

  first(root: RuleTarget): string {
    this.assign(root);
    return this.transform(this.textValue(root, false));
  }

  allText(root: RuleTarget): string {
    this.assign(root);
    return this.transform(this.textValue(root, true));
  }

  private selectNodes(root: RuleTarget): RuleTarget[] {
    if (this.branches !== undefined) {
      const groups: RuleTarget[][] = [];
      let count: number = 0;
      for (const field of this.branches.fields) {
        const selected: RuleTarget[] = field.nodes(root, false);
        if (selected.length > 0) {
          if (this.branches.operator === '||') {
            return selected;
          }
          groups.push(selected);
          count += selected.length;
          if (count >= MAX_SELECTED && this.branches.operator === '&&') {
            break;
          }
        }
      }
      return combine(groups, this.branches.operator);
    }
    const nodes: RuleTarget[] = [];
    if (root.html !== undefined && this.html !== undefined) {
      return this.html.nodes(root.html).slice(0, MAX_SELECTED)
        .map((node: HtmlNode): RuleTarget => RuleTarget.fromHtml(node, root.variables).withAddress(root.baseUrl));
    }
    if (root.data !== undefined && this.path !== undefined) {
      for (const value of this.path.select(root.data)) {
        if (value === null) {
          continue;
        }
        if (Array.isArray(value)) {
          for (const element of (value as JsonValue[]).slice(0, MAX_SELECTED - nodes.length)) {
            nodes.push(RuleTarget.fromJson(element, root.variables).withAddress(root.baseUrl));
          }
        } else {
          nodes.push(RuleTarget.fromJson(value, root.variables).withAddress(root.baseUrl));
        }
        if (nodes.length >= MAX_SELECTED) {
          break;
        }
      }
    }
    return nodes;
  }

  private textValue(root: RuleTarget, all: boolean): string {
    if (this.branches !== undefined) {
      return this.branchText(root, all);
    }
    if (this.render !== undefined) {
      return this.render(root);
    }
    if (root.html !== undefined && this.html !== undefined) {
      return all ? this.html.allText(root.html) : this.html.first(root.html);
    }
    if (root.data !== undefined && this.path !== undefined) {
      const values: string[] = [];
      for (const value of this.path.select(root.data)) {
        const text: string = valueText(value);
        if (text.length > 0) {
          if (!all) {
            return text;
          }
          values.push(text);
        }
      }
      return values.join('\n');
    }
    return '';
  }

  private branchText(root: RuleTarget, all: boolean): string {
    const branches: RuleBranches | undefined = this.branches;
    if (branches === undefined) {
      return '';
    }
    const groups: string[][] = [];
    for (const field of branches.fields) {
      const value: string = all ? field.allText(root) : field.first(root);
      if (value.length > 0) {
        if (branches.operator === '||') {
          return value;
        }
        groups.push(all && branches.operator === '%%' ? value.split('\n') : [value]);
      }
    }
    return combine(groups, branches.operator).join('\n');
  }

  private assign(root: RuleTarget): void {
    for (const assignment of this.assignments) {
      root.variables.put(assignment.name, assignment.field.first(root));
    }
  }

  private transform(value: string): string {
    let result: string = value;
    for (const transform of this.transforms) {
      result = transform(result).trim();
    }
    return result;
  }
}

function combine<T>(groups: T[][], operator: string): T[] {
  const combined: T[] = [];
  if (operator === '%%') {
    const width: number = groups.reduce((largest: number, group: T[]): number => Math.max(largest, group.length), 0);
    for (let index: number = 0; index < width && combined.length < MAX_SELECTED; index++) {
      for (const group of groups) {
        if (index < group.length && combined.length < MAX_SELECTED) {
          combined.push(group[index]);
        }
      }
    }
  } else {
    for (const group of groups) {
      for (const item of group.slice(0, MAX_SELECTED - combined.length)) {
        combined.push(item);
      }
    }
  }
  return combined;
}

function scalarText(value: JsonValue): string {
  if (typeof value === 'string') {
    return value.trim();
  }
  return typeof value === 'number' || typeof value === 'boolean' ? String(value) : '';
}

function valueText(value: JsonValue): string {
  if (!Array.isArray(value)) {
    return scalarText(value);
  }
  return (value as JsonValue[]).slice(0, MAX_SELECTED).map((item: JsonValue): string => scalarText(item))
    .filter((part: string): boolean => part.length > 0).join('\n');
}

export function compileSourceField(expression: string, output: string = 'text', list: boolean = false,
  allowReverse: boolean = false, depth: number = 0): SourceField {
  let rule: string = expression.trim();
  const ordered: boolean = allowReverse && (rule.startsWith('-') || rule.startsWith('+'));
  const reverse: boolean = ordered && rule.startsWith('-');
  if (ordered) {
    rule = rule.slice(1).trim();
  }
  if (rule.length === 0 || rule.length > 1800 || depth > 12) {
    throw new Error('规则为空、过长或嵌套过深');
  }
  const assignments: RuleAssignment[] = [];
  rule = rule.replace(/\s*@put:\s*\{([^{}]*)\}/gi, (_raw: string, fields: string): string => {
    parseAssignments(fields, assignments, depth + 1);
    return '';
  }).trim();
  const compiled: SourceField = compileExpression(rule, output, list, depth);
  compiled.addAssignments(assignments);
  if (reverse) {
    compiled.reverseOrder();
  }
  return compiled;
}

function compileExpression(rule: string, output: string, list: boolean, depth: number): SourceField {
  const script: RegExpMatchArray | null = rule.match(/(?:@js:|<\s*\/?js\b)/i);
  if (script !== null) {
    const prefix: string = rule.slice(0, script.index).trim();
    if (list || prefix.length === 0 || script[0].toLowerCase() !== '@js:') {
      throw new Error('当前规则需要执行书源脚本');
    }
    const base: SourceField = compileSourceField(prefix, output, false, false, depth + 1);
    base.addTransform(compileResultTransform(rule.slice((script.index ?? 0) + script[0].length)));
    return base;
  }
  if (/@put:/i.test(rule)) {
    throw new Error('书籍变量需要 @put:{名称:规则}');
  }

  const options: number = output === 'href' ? rule.search(/,\s*\{(?!\{)/) : -1;
  const cleanupAt: number = (options < 0 ? rule : rule.slice(0, options)).indexOf('##');
  if (cleanupAt >= 0) {
    if (list) {
      throw new Error('节点列表不支持文本清理');
    }
    const base: SourceField = compileSourceField(cleanupAt === 0 ? 'text' : rule.slice(0, cleanupAt),
      output, false, false, depth + 1);
    const cleanup: TextCleanup = compileTextCleanup(rule.slice(cleanupAt + 2));
    base.addTransform((value: string): string => cleanup.apply(value));
    return base;
  }

  let branches: RuleBranches | undefined;
  for (const operator of ['||', '&&', '%%']) {
    branches = compileBranches(rule, operator, output, list, depth);
    if (branches !== undefined) {
      return new SourceField(undefined, undefined, undefined, branches);
    }
  }
  if (/\{\{|\{\$|@get:/i.test(rule)) {
    if (list) {
      throw new Error('节点列表不支持文本模板');
    }
    const render: RuleText = compileTemplate(rule, depth + 1);
    if (options >= 0) {
      checkLinkOptions(rule.slice(options + 1));
    }
    return new SourceField(undefined, undefined, render);
  }
  if (/^(?:\$|@json:)/i.test(rule)) {
    return new SourceField(undefined, new JsonPath(rule));
  }
  if (!list && output === 'href' && /^(?:https?:\/\/|\/\/[^/ [\]]+\.[a-z]|\/[^?[\]@]*\?)/i.test(rule)) {
    if (options >= 0) {
      checkLinkOptions(rule.slice(options + 1));
    }
    return new SourceField(undefined, undefined, (_root: RuleTarget): string => rule);
  }
  if (/^(?:@xpath:|\/|\.\/)/i.test(rule)) {
    return new SourceField(compileXPathRule(rule, output, list));
  }
  if (rule === 'text') {
    const html: HtmlFieldRule = compileHtmlRule(rule, output, list);
    return new SourceField(html, new JsonPath('$'));
  }

  let path: JsonPath | undefined;
  if (/^[\w\u0080-\uffff-]+(?:\.[\w\u0080-\uffff-]+|\[[\d*,: -]+\])*$/.test(rule)) {
    path = new JsonPath(rule);
  }
  let html: HtmlFieldRule | undefined;
  try {
    html = compileHtmlRule(rule.startsWith('@@') ? rule.slice(2).trim() : rule, output, list);
  } catch (error) {
    if (path === undefined) {
      throw error as Error;
    }
  }
  return new SourceField(html, path);
}

function checkLinkOptions(tail: string): void {
  // Validate the request shape with placeholders. The actual link is resolved after extraction.
  const preview: string = tail.replace(/\{\{[^{}]+\}\}|\{\$[^{}]+\}|@get:\s*\{[\w-]+\}/gi, '1');
  compilePageRequest('https://example.invalid/,' + preview);
}

function parseAssignments(raw: string, out: RuleAssignment[], depth: number): void {
  for (const item of raw.split(',')) {
    const matched: RegExpMatchArray | null = item.trim().match(
      /^["']?([\w-]{1,48})["']?\s*:\s*(?:"([^"]+)"|'([^']+)'|([^\s,{}]+))$/);
    if (matched === null || out.length >= 12) {
      throw new Error('书籍变量需要 1 至 12 个 @put:{名称:规则} 项');
    }
    const field: string = matched[2] ?? matched[3] ?? matched[4];
    out.push(new RuleAssignment(matched[1], compileSourceField(field, 'text', false, false, depth)));
  }
}

function compileBranches(rule: string, operator: string, output: string, list: boolean,
  depth: number): RuleBranches | undefined {
  const slices: string[] = [];
  let quote: string = '';
  let nested: number = 0;
  let start: number = 0;
  for (let index: number = 0; index < rule.length - 1; index++) {
    const char: string = rule.charAt(index);
    if (char === '\\') {
      index++;
    } else if (quote.length > 0) {
      if (char === quote) {
        quote = '';
      }
    } else if (char === '"' || char === "'") {
      quote = char;
    } else if ('[{('.includes(char)) {
      nested++;
    } else if (']})'.includes(char)) {
      nested--;
    } else if (nested === 0 && rule.startsWith(operator, index)) {
      slices.push(rule.slice(start, index).trim());
      start = index + 2;
      index++;
    }
  }
  if (slices.length === 0) {
    return undefined;
  }
  slices.push(rule.slice(start).trim());
  if (slices.length > 8 || slices.some((part: string): boolean => part.length === 0)) {
    throw new Error('组合规则需要 2 至 8 个有效分支');
  }
  const mode: string = slices[0].match(/^@(?:css|json|xpath):/i)?.[0] ?? '';
  const fields: SourceField[] = slices.map((part: string): SourceField => compileSourceField(
    mode.length > 0 && !/^(?:[@$/\{]|https?:\/\/)/i.test(part) ? mode + part : part,
    output, list, false, depth + 1));
  return new RuleBranches(fields, operator);
}

function compileTemplate(rule: string, depth: number): RuleText {
  const parts: RuleText[] = [];
  const tokens: RegExp = /\{\{\s*([^{}]+?)\s*\}\}|\{(\$[^{}]+?)\}|@get:\s*\{\s*([\w-]{1,48})\s*\}/gi;
  let end: number = 0;
  let match: RegExpExecArray | null = tokens.exec(rule);
  while (match !== null) {
    appendLiteral(parts, rule.slice(end, match.index));
    const variable: string | undefined = match[3];
    if (variable !== undefined) {
      parts.push((root: RuleTarget): string => root.variables.get(variable));
    } else {
      const field: string = (match[1] ?? match[2]).trim();
      parts.push(compileTemplateField(field, depth));
    }
    end = match.index + match[0].length;
    match = tokens.exec(rule);
  }
  appendLiteral(parts, rule.slice(end));
  return (root: RuleTarget): string => {
    let result: string = '';
    for (const part of parts) {
      const raw: string = part(root);
      if (raw.length === 0) {
        return '';
      }
      result += raw;
    }
    return result;
  };
}

function compileTemplateField(field: string, depth: number): RuleText {
  if (field === 'baseUrl') {
    return (root: RuleTarget): string => root.baseUrl;
  }
  const address: RegExpMatchArray | null = field.match(
    /^baseUrl\.replace\(\s*("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')\s*,\s*("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')\s*\)$/);
  if (address !== null) {
    const options = staticOptions('{from:' + address[1] + ',to:' + address[2] + '}', '地址替换需要两个静态字符串');
    const from: JsonValue | undefined = options['from'];
    const to: JsonValue | undefined = options['to'];
    if (typeof from === 'string' && typeof to === 'string' && from.length > 0) {
      return (root: RuleTarget): string => {
        const at: number = root.baseUrl.indexOf(from);
        return at < 0 ? root.baseUrl : root.baseUrl.slice(0, at) + to + root.baseUrl.slice(at + from.length);
      };
    }
    throw new Error('地址替换需要静态的原值和替换文本');
  }
  if (!/^(?:\$|@json:|@css:|@xpath:|\/\/|tag\.|class\.|id\.)/i.test(field) &&
    !/^[a-zA-Z_][\w-]*(?:\.[a-zA-Z_][\w-]*|\[-?\d+\])*$/.test(field)) {
    throw new Error('模板中需要属性路径、选择器或当前页面地址');
  }
  const compiled: SourceField = compileSourceField(field, 'text', false, false, depth);
  return (root: RuleTarget): string => compiled.first(root);
}

function appendLiteral(parts: RuleText[], value: string): void {
  if (/\{\{|\{\$|@get:/i.test(value)) {
    throw new Error('模板格式无效或括号未配对');
  }
  if (value.length > 0) {
    parts.push((_root: RuleTarget): string => value);
  }
}

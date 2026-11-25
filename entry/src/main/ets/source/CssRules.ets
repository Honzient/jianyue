import { HtmlNode, nodeText } from './HtmlDocument';

const NAME: RegExp = /^[a-zA-Z_][\w-]*/;
const CLASS_NAME: RegExp = /^[\w-]+/;
const MAX_SELECTED: number = 10000;

class NodeRange {
  start?: number;
  end?: number;
  step: number;
  single: boolean;

  constructor(start: number | undefined, end: number | undefined, step: number, single: boolean) {
    this.start = start;
    this.end = end;
    this.step = step;
    this.single = single;
  }
}

class NodePositions {
  private readonly ranges: NodeRange[];
  private readonly exclude: boolean;

  constructor(parts: NodeRange[], exclude: boolean) {
    this.ranges = parts;
    this.exclude = exclude;
  }

  select(nodes: HtmlNode[]): HtmlNode[] {
    const length: number = nodes.length;
    const indexes: Set<number> = new Set<number>();
    for (const part of this.ranges) {
      let start: number = part.start ?? 0;
      let end: number = part.end ?? length - 1;
      start = start < 0 ? length + start : start;
      end = end < 0 ? length + end : end;
      if (part.single) {
        if (start >= 0 && start < length) {
          indexes.add(start);
        }
        continue;
      }
      if (length === 0 || start < 0 && end < 0 || start >= length && end >= length) {
        continue;
      }
      start = Math.min(length - 1, Math.max(0, start));
      end = Math.min(length - 1, Math.max(0, end));
      const magnitude: number = part.step > 0 ? part.step : Math.max(1, length + part.step);
      const step: number = start <= end ? magnitude : -magnitude;
      for (let index: number = start; (step > 0 ? index <= end : index >= end); index += step) {
        indexes.add(index);
      }
    }
    if (this.exclude) {
      return nodes.filter((_node: HtmlNode, index: number): boolean => !indexes.has(index));
    }
    return Array.from(indexes).map((index: number): HtmlNode => nodes[index]);
  }
}

function positions(raw: string, exclude: boolean, ranges: boolean): NodePositions {
  const pieces: string[] = raw.split(ranges ? /[,，]/ : /:/);
  if (pieces.length > 32) {
    throw new Error('节点下标超过 32 项');
  }
  const parts: NodeRange[] = [];
  for (const piece of pieces) {
    const token: string = piece.trim();
    const interval: RegExpMatchArray | null =
      ranges ? token.match(/^(-?\d{1,6})?\s*:\s*(-?\d{1,6})?(?:\s*:\s*(-?\d{1,6}))?$/) : null;
    if (/^-?\d{1,6}$/.test(token)) {
      parts.push(new NodeRange(Number(token), undefined, 1, true));
    } else if (interval !== null && interval[3] !== '0') {
      parts.push(new NodeRange(interval[1] === undefined ? undefined : Number(interval[1]),
        interval[2] === undefined ? undefined : Number(interval[2]), Number(interval[3] ?? '1'), false));
    } else {
      throw new Error('节点下标或区间无效');
    }
  }
  return new NodePositions(parts, exclude);
}

enum ChildFilter {
  All,
  First,
  Last,
  Numbered,
  Below,
  Above
}

class AttributeCheck {
  name: string;
  operation: string;
  value: string;

  constructor(name: string, operation: string, value: string) {
    this.name = name;
    this.operation = operation;
    this.value = value;
  }

  matches(node: HtmlNode): boolean {
    if (!node.attrs.has(this.name)) {
      return false;
    }
    const actual: string = node.attr(this.name);
    switch (this.operation) {
      case '': return true;
      case '=': return actual === this.value;
      case '^=': return actual.startsWith(this.value);
      case '$=': return actual.endsWith(this.value);
      case '*=': return actual.includes(this.value);
      case '~=': return actual.split(/\s+/).includes(this.value);
      case '|=': return actual === this.value || actual.startsWith(this.value + '-');
      default: return false;
    }
  }
}

class SelectorStep {
  direct: boolean;
  tag: string = '';
  id: string = '';
  classes: string[] = [];
  attributes: AttributeCheck[] = [];
  childFilter: ChildFilter = ChildFilter.All;
  childNumber: number = 0;
  positions?: NodePositions;
  perParent: boolean = false;
  sibling: string = '';
  childStep: number = 0;
  contains: string = '';
  ownText: string = '';
  negation?: SelectorStep;

  constructor(direct: boolean) {
    this.direct = direct;
  }

  matches(node: HtmlNode): boolean {
    if (node.tag.length === 0 || node.tag.startsWith('#') ||
      this.tag.length > 0 && node.tag !== this.tag || this.id.length > 0 && node.attr('id') !== this.id) {
      return false;
    }
    if (this.classes.length > 0) {
      const actual: string[] = node.attr('class').split(/\s+/);
      for (const token of this.classes) {
        if (!actual.includes(token)) {
          return false;
        }
      }
    }
    for (const check of this.attributes) {
      if (!check.matches(node)) {
        return false;
      }
    }
    if (this.contains.length > 0 && !nodeText(node).toLowerCase().includes(this.contains) ||
      this.ownText.length > 0 && !nodeText(node, true).toLowerCase().includes(this.ownText)) {
      return false;
    }
    return (this.negation === undefined || !this.negation.matches(node)) && this.matchesPosition(node);
  }

  private matchesPosition(node: HtmlNode): boolean {
    if (this.childFilter === ChildFilter.All) {
      return true;
    }
    const parent: HtmlNode | undefined = node.parent;
    if (!parent) {
      return false;
    }
    if (this.childFilter === ChildFilter.Last) {
      return node.elementIndex === parent.elementChildren;
    }
    if (this.childFilter === ChildFilter.Below || this.childFilter === ChildFilter.Above) {
      const index: number = node.elementIndex - 1;
      return this.childFilter === ChildFilter.Below ? index < this.childNumber : index > this.childNumber;
    }
    const expected: number = this.childFilter === ChildFilter.First ? 1 : this.childNumber;
    const offset: number = node.elementIndex - expected;
    return this.childStep === 0 ? offset === 0 : offset / this.childStep >= 0 && offset % this.childStep === 0;
  }
}

export class FieldRule {
  private groups: SelectorStep[][];
  private output: string;
  private reversed: boolean;

  constructor(groups: SelectorStep[][], output: string, reversed: boolean) {
    this.groups = groups;
    this.output = output;
    this.reversed = reversed;
  }

  nodes(root: HtmlNode, applyOrder: boolean = true): HtmlNode[] {
    if (this.groups.length === 0) {
      return [root];
    }
    const selected: Set<HtmlNode> = new Set<HtmlNode>();
    for (const group of this.groups) {
      let candidates: HtmlNode[] = [root];
      for (let index: number = 0; index < group.length; index++) {
        candidates = this.step(candidates, group[index], index === 0);
        if (candidates.length === 0) {
          break;
        }
      }
      for (const node of candidates) {
        selected.add(node);
      }
    }
    const result: HtmlNode[] = Array.from(selected);
    if (this.groups.length > 1) {
      result.sort((a: HtmlNode, b: HtmlNode): number => a.order - b.order);
    }
    return this.reversed && applyOrder ? result.reverse() : result;
  }

  reversesOrder(): boolean {
    return this.reversed;
  }

  first(root: HtmlNode): string {
    for (const node of this.nodes(root)) {
      const value: string = this.read(node);
      if (value.length > 0) {
        return value;
      }
    }
    return '';
  }

  allText(root: HtmlNode): string {
    return this.nodes(root).map((node: HtmlNode): string => this.read(node))
      .filter((value: string): boolean => value.length > 0).join('\n');
  }

  private read(node: HtmlNode): string {
    if (this.output === 'text' || this.output === 'html') {
      return nodeText(node);
    }
    if (this.output === 'owntext' || this.output === 'textnodes') {
      return nodeText(node, true);
    }
    return node.attr(this.output).trim();
  }

  private step(roots: HtmlNode[], rule: SelectorStep, includeRoot: boolean): HtmlNode[] {
    const visited: Set<HtmlNode> = new Set<HtmlNode>();
    const matches: Set<HtmlNode> = new Set<HtmlNode>();
    let visits: number = 0;
    for (const root of roots) {
      const local: HtmlNode[] = [];
      const queue: HtmlNode[] = [];
      if (rule.sibling.length > 0) {
        const siblings: HtmlNode[] = root.parent?.children ?? [];
        for (let index: number = siblings.length - 1; index >= 0; index--) {
          const node: HtmlNode = siblings[index];
          if (node.elementIndex > root.elementIndex &&
            (rule.sibling === '~' || node.elementIndex === root.elementIndex + 1)) {
            queue.push(node);
          }
        }
      } else if (includeRoot && !rule.direct) {
        queue.push(root);
      } else {
        for (let index: number = root.children.length - 1; index >= 0; index--) {
          queue.push(root.children[index]);
        }
      }

      while (queue.length > 0 && local.length < MAX_SELECTED) {
        const node: HtmlNode | undefined = queue.pop();
        if (node === undefined || visited.has(node)) {
          continue;
        }
        if (++visits > 300000) {
          throw new Error('HTML 选择器遍历超过节点数限制');
        }
        if (rule.positions === undefined) {
          visited.add(node);
        }
        if (rule.matches(node)) {
          local.push(node);
        }
        if (!rule.direct && rule.sibling.length === 0) {
          for (let index: number = node.children.length - 1; index >= 0; index--) {
            queue.push(node.children[index]);
          }
        }
      }
      const selected: HtmlNode[] = this.filterPositions(local, rule);
      for (const result of selected) {
        matches.add(result);
        if (matches.size >= MAX_SELECTED) {
          return Array.from(matches);
        }
      }
    }
    return Array.from(matches);
  }

  private filterPositions(nodes: HtmlNode[], rule: SelectorStep): HtmlNode[] {
    const positions: NodePositions | undefined = rule.positions;
    if (positions === undefined) {
      return nodes;
    }
    if (!rule.perParent) {
      return positions.select(nodes);
    }
    const families: Map<HtmlNode, HtmlNode[]> = new Map<HtmlNode, HtmlNode[]>();
    for (const node of nodes) {
      const parent: HtmlNode | undefined = node.parent;
      if (parent !== undefined) {
        const siblings: HtmlNode[] = families.get(parent) ?? [];
        siblings.push(node);
        families.set(parent, siblings);
      }
    }
    const matched: Set<HtmlNode> = new Set<HtmlNode>();
    for (const siblings of families.values()) {
      for (const node of positions.select(siblings)) {
        matched.add(node);
      }
    }
    return nodes.filter((node: HtmlNode): boolean => matched.has(node));
  }
}

export function compileRule(expression: string, defaultOutput: string = 'text', list: boolean = false,
  allowReverse: boolean = false): FieldRule {
  let input: string = expression.trim();
  let reversed: boolean = false;
  if (allowReverse && input.startsWith('-')) {
    reversed = true;
    input = input.slice(1).trimStart();
  }
  if (input.length === 0 || input.length > 1000) {
    throw new Error('规则为空或过长');
  }
  if (/(?:<\s*\/?js\b|@js:|@xpath:|@json:|@put:|@get:|\{\{|##|&&|\|\||%%|^\/|^\$\.)/i.test(input)) {
    throw new Error('仅支持 CSS 和基本的 tag/class/id 节点规则');
  }

  const explicitCss: boolean = input.toLowerCase().startsWith('@css:');
  if (explicitCss) {
    input = input.slice(5).trim();
  }
  const pieces: string[] = splitParts(input, '@');
  const tail: string = pieces[pieces.length - 1].trim();
  let output: string = defaultOutput;
  if (!list && (pieces.length > 1 && isOutput(tail) || pieces.length === 1 && isBareOutput(tail, defaultOutput))) {
    output = tail.toLowerCase();
    pieces.pop();
  }
  if (pieces.length === 0) {
    return new FieldRule([], output, reversed);
  }
  if (explicitCss) {
    if (pieces.length > 1) {
      throw new Error('CSS 选择器包含无法识别的后缀');
    }
    return new FieldRule(parseCss(pieces[0].trim()), output, reversed);
  }
  return new FieldRule(parseLegacy(pieces), output, reversed);
}

function isBareOutput(token: string, defaultOutput: string): boolean {
  const key: string = token.toLowerCase();
  return key === 'text' || key === 'owntext' || key === 'textnodes' || key === defaultOutput && key !== 'text';
}

function isOutput(input: string): boolean {
  return /^[a-zA-Z_][\w:-]*$/.test(input) && input.toLowerCase() !== 'children';
}

function splitParts(input: string, separator: string): string[] {
  const parts: string[] = [];
  let brackets: number = 0;
  let parentheses: number = 0;
  let quote: string = '';
  let start: number = 0;
  for (let index: number = 0; index < input.length; index++) {
    const char: string = input.charAt(index);
    if (quote.length > 0) {
      if (char === quote) {
        quote = '';
      }
    } else if (char === '"' || char === "'") {
      quote = char;
    } else if (char === '[') {
      brackets++;
    } else if (char === ']') {
      brackets--;
    } else if (brackets === 0 && char === '(') {
      parentheses++;
    } else if (brackets === 0 && char === ')') {
      parentheses--;
    } else if (brackets === 0 && parentheses === 0 && char === separator) {
      parts.push(input.slice(start, index));
      start = index + 1;
    }
    if (brackets < 0 || parentheses < 0) {
      throw new Error('选择器方括号未配对');
    }
  }
  if (brackets !== 0 || parentheses !== 0 || quote.length > 0) {
    throw new Error('选择器方括号或引号未配对');
  }
  parts.push(input.slice(start));
  return parts;
}

function parseLegacy(parts: string[]): SelectorStep[][] {
  let chains: SelectorStep[][] = [[]];
  for (const part of parts) {
    const piece: string = part.trim();
    const bracket: RegExpMatchArray | null = piece.match(/\[\s*(!)?\s*([\d\s,:，-]+)\]$/);
    const old: RegExpMatchArray | null = bracket === null ? piece.match(/([.!])(-?\d{1,6}(?::-?\d{1,6})*)$/) : null;
    const suffix: RegExpMatchArray | null = bracket ?? old;
    const selector: string = suffix === null ? piece : piece.slice(0, suffix.index).trim();
    const legacy: RegExpMatchArray | null = selector.match(/^(tag|class|id)\.([\w-]+)$/);
    const text: RegExpMatchArray | null = selector.match(/^text\.(.+)$/);
    let groups: SelectorStep[][];
    if (legacy !== null || text !== null || selector === 'children' || selector.length === 0 && suffix !== null) {
      const step: SelectorStep = new SelectorStep(selector === 'children' || selector.length === 0);
      if (legacy !== null) {
        if (legacy[1] === 'tag') {
          step.tag = legacy[2].toLowerCase();
        } else if (legacy[1] === 'class') {
          step.classes.push(legacy[2]);
        } else {
          step.id = legacy[2];
        }
      }
      if (text !== null) {
        step.ownText = text[1].trim().toLowerCase();
      }
      groups = [[step]];
    } else {
      groups = parseCss(selector);
    }
    if (suffix !== null) {
      const selection: NodePositions = positions(suffix[2], suffix[1] === '!', bracket !== null);
      for (const group of groups) {
        group[group.length - 1].positions = selection;
      }
    }
    const joined: SelectorStep[][] = [];
    for (const chain of chains) {
      for (const group of groups) {
        if (joined.length >= 12 || chain.length + group.length > 12) {
          throw new Error('节点规则超过 12 层或 12 组');
        }
        joined.push(chain.concat(group));
      }
    }
    chains = joined;
  }
  return chains;
}

function parseCss(input: string): SelectorStep[][] {
  const groups: string[] = splitParts(input, ',');
  if (groups.length > 6) {
    throw new Error('并列选择器超过 6 组');
  }
  return groups.map((group: string): SelectorStep[] => parseCssChain(group.trim()));
}

function parseCssChain(input: string): SelectorStep[] {
  const chain: SelectorStep[] = [];
  let index: number = 0;
  let combinator: string = '';
  while (index < input.length) {
    if ('>+~'.includes(input.charAt(index))) {
      throw new Error('选择器缺少前一个节点');
    }
    const end: number = compoundEnd(input, index);
    const step: SelectorStep = parseCompound(input.slice(index, end), combinator === '>');
    step.sibling = combinator === '+' || combinator === '~' ? combinator : '';
    chain.push(step);
    if (chain.length > 10) {
      throw new Error('选择器层数超过 10 层');
    }
    index = skipSpaces(input, end);
    combinator = index < input.length && '>+~'.includes(input.charAt(index)) ? input.charAt(index) : '';
    if (combinator.length > 0) {
      index = skipSpaces(input, index + 1);
      if (index === input.length) {
        throw new Error('子节点选择器缺少目标');
      }
    }
  }
  if (chain.length === 0) {
    throw new Error('选择器为空');
  }
  return chain;
}

function skipSpaces(input: string, index: number): number {
  while (index < input.length && /\s/.test(input.charAt(index))) {
    index++;
  }
  return index;
}

function compoundEnd(input: string, start: number): number {
  let brackets: number = 0;
  let parentheses: number = 0;
  let quote: string = '';
  for (let index: number = start; index < input.length; index++) {
    const char: string = input.charAt(index);
    if (quote.length > 0) {
      if (char === quote) {
        quote = '';
      }
    } else if (char === '[') {
      brackets++;
    } else if (char === ']') {
      brackets--;
    } else if (char === '"' || char === "'") {
      quote = char;
    } else if (brackets === 0 && char === '(') {
      parentheses++;
    } else if (brackets === 0 && char === ')') {
      parentheses--;
    } else if (brackets === 0 && parentheses === 0 && (/\s/.test(char) || '>+~'.includes(char))) {
      return index;
    }
  }
  return input.length;
}

function parseCompound(input: string, direct: boolean, nested: boolean = false): SelectorStep {
  const rule: SelectorStep = new SelectorStep(direct);
  const tag: RegExpMatchArray | null = input.match(NAME);
  let at: number = 0;
  if (tag !== null) {
    rule.tag = tag[0].toLowerCase();
    at = tag[0].length;
  } else if (input.startsWith('*')) {
    at = 1;
  }
  while (at < input.length) {
    const char: string = input.charAt(at);
    const tail: string = input.slice(at);
    if (char === '#' || char === '.') {
      const name: RegExpMatchArray | null = tail.slice(1).match(CLASS_NAME);
      if (name === null) {
        throw new Error('类名或 ID 为空');
      }
      if (char === '#') {
        if (rule.id.length > 0) {
          throw new Error('单个节点选择器只能包含一个 ID');
        }
        rule.id = name[0];
      } else {
        rule.classes.push(name[0]);
      }
      at += name[0].length + 1;
    } else if (char === '[') {
      const attribute: RegExpMatchArray | null =
        tail.match(/^\[\s*([\w:-]+)\s*(?:(=|\^=|\$=|\*=|~=|\|=)\s*(?:"([^"]*)"|'([^']*)'|([^\]\s]+)))?\s*\]/);
      if (attribute === null) {
        throw new Error('属性选择器语法不受支持');
      }
      rule.attributes.push(new AttributeCheck(attribute[1].toLowerCase(), attribute[2] ?? '',
        attribute[3] ?? attribute[4] ?? attribute[5] ?? ''));
      at += attribute[0].length;
    } else if (char === ':') {
      at += readPseudo(rule, tail, nested);
    } else {
      throw new Error('无法识别选择器 ' + tail.slice(0, 50));
    }
  }
  return rule;
}

function readPseudo(rule: SelectorStep, tail: string, nested: boolean): number {
  const simple: RegExpMatchArray | null = tail.match(/^:(first-child|last-child)(?![\w-])/);
  const position: RegExpMatchArray | null = tail.match(/^:(nth-child|eq|lt|gt)\(\s*([^()]+?)\s*\)/);
  const filter: RegExpMatchArray | null = tail.match(/^:(contains|not)\(\s*([^()]+?)\s*\)/);
  if (filter !== null && filter[1] === 'contains' && rule.contains.length === 0) {
    rule.contains = filter[2].replace(/^(["'])(.*)\1$/, '$2').toLowerCase();
    return filter[0].length;
  }
  if (filter !== null && filter[1] === 'not' && !nested && rule.negation === undefined) {
    rule.negation = parseCompound(filter[2], false, true);
    return filter[0].length;
  }
  if (rule.childFilter !== ChildFilter.All) {
    throw new Error('同一节点包含多个位置条件');
  }
  if (simple !== null) {
    rule.childFilter = simple[1] === 'first-child' ? ChildFilter.First : ChildFilter.Last;
    return simple[0].length;
  }
  if (position !== null) {
    const value: string = position[2].toLowerCase().replace(/\s/g, '');
    if (position[1] !== 'nth-child' && /^\d{1,6}$/.test(value)) {
      rule.childFilter = position[1] === 'lt' ? ChildFilter.Below : position[1] === 'gt' ? ChildFilter.Above :
        ChildFilter.Numbered;
      rule.childNumber = Number(value) + (position[1] === 'eq' ? 1 : 0);
      return position[0].length;
    }
    if (position[1] === 'nth-child') {
      const sequence: RegExpMatchArray | null = value.match(/^([+-]?\d{0,6})n([+-]\d{1,6})?$/);
      rule.childFilter = ChildFilter.Numbered;
      if (value === 'odd' || value === 'even') {
        rule.childStep = 2;
        rule.childNumber = value === 'odd' ? 1 : 0;
        return position[0].length;
      }
      if (/^[+-]?\d{1,6}$/.test(value)) {
        rule.childNumber = Number(value);
        return position[0].length;
      }
      if (sequence !== null) {
        rule.childStep = sequence[1] === '' || sequence[1] === '+' ? 1 :
          sequence[1] === '-' ? -1 : Number(sequence[1]);
        rule.childNumber = Number(sequence[2] ?? '0');
        return position[0].length;
      }
    }
  }
  throw new Error('CSS 伪类或位置参数暂不能运行');
}

export function compileXPathRule(raw: string, defaultOutput: string, list: boolean): FieldRule {
  let expression: string = raw.replace(/^@xpath:\s*/i, '').trim();
  if (expression.startsWith('./')) {
    expression = expression.slice(1);
  }
  if (!expression.startsWith('/')) {
    expression = '/' + expression;
  }
  let output: string = defaultOutput;
  const steps: SelectorStep[] = [];
  const segments: string[] = splitParts(expression.slice(1), '/');
  let descendant: boolean = false;
  let terminal: boolean = false;
  for (let index: number = 0; index < segments.length; index++) {
    const item: string = segments[index].trim();
    if (item.length === 0 && !descendant && index < segments.length - 1) {
      descendant = true;
      continue;
    }
    const attribute: RegExpMatchArray | null = item.match(/^@([\w:-]+)$/);
    if (!list && index === segments.length - 1 && (attribute !== null || item === 'text()')) {
      output = attribute === null ? 'owntext' : attribute[1].toLowerCase();
      terminal = true;
      break;
    }
    if (steps.length >= 12) {
      throw new Error('XPath 层数超过 12 层');
    }
    const step: SelectorStep = parseXPathStep(item, descendant);
    steps.push(step);
    descendant = false;
  }
  if (steps.length === 0 && list) {
    throw new Error('XPath 列表需要元素节点');
  }
  if (steps.length === 0 && !terminal) {
    throw new Error('XPath 缺少有效节点或属性');
  }
  return new FieldRule(steps.length === 0 ? [] : [steps], output, false);
}

function parseXPathStep(input: string, descendant: boolean): SelectorStep {
  const name: RegExpMatchArray | null = input.match(/^(\*|[a-zA-Z_][\w:-]*)/);
  if (name === null) {
    throw new Error('XPath 需要元素名、*、属性或 text()');
  }
  const step: SelectorStep = new SelectorStep(!descendant);
  step.tag = name[1] === '*' ? '' : name[1].toLowerCase();
  let tail: string = input.slice(name[0].length).trimStart();
  while (tail.length > 0) {
    const attr: RegExpMatchArray | null = tail.match(/^\[\s*@([\w:-]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'))?\s*\]/);
    const contains: RegExpMatchArray | null =
      tail.match(/^\[\s*contains\(\s*@([\w:-]+)\s*,\s*(?:"([^"]*)"|'([^']*)')\s*\)\s*\]/);
    const position: RegExpMatchArray | null = tail.match(/^\[\s*([1-9]\d{0,5}|last\(\))\s*\]$/);
    if (attr !== null) {
      step.attributes.push(new AttributeCheck(attr[1].toLowerCase(), attr[2] === undefined && attr[3] === undefined ?
        '' : '=', attr[2] ?? attr[3] ?? ''));
      tail = tail.slice(attr[0].length).trimStart();
    } else if (contains !== null) {
      step.attributes.push(new AttributeCheck(contains[1].toLowerCase(), '*=', contains[2] ?? contains[3]));
      tail = tail.slice(contains[0].length).trimStart();
    } else if (position !== null) {
      const index: string = position[1] === 'last()' ? '-1' : String(Number(position[1]) - 1);
      step.positions = positions(index, false, false);
      step.perParent = descendant;
      tail = '';
    } else {
      throw new Error('XPath 谓词支持属性存在、等值、contains() 或位置');
    }
  }
  return step;
}

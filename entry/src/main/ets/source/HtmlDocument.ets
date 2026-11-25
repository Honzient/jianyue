const VOID_TAGS: string[] = [
  'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'param', 'source', 'track', 'wbr'
];
const INVISIBLE_TAGS: string[] = ['script', 'style', 'noscript', 'template'];
const BLOCK_TAGS: string[] = [
  'address', 'article', 'aside', 'blockquote', 'div', 'dl', 'dd', 'dt', 'figcaption', 'figure', 'footer',
  'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'header', 'hr', 'li', 'main', 'nav', 'ol', 'p', 'pre', 'section',
  'table', 'td', 'th', 'tr', 'ul'
];
const TABLE_SECTIONS: string[] = ['thead', 'tbody', 'tfoot'];
const OPTIONAL_CLOSE: string[] = ['li', 'p', 'option', 'tr', 'td', 'th', 'dt', 'dd'];
const MAX_NODES: number = 96000;

export class HtmlNode {
  tag: string;
  order: number;
  text: string;
  parent?: HtmlNode;
  children: HtmlNode[] = [];
  elementIndex: number = 0;
  elementChildren: number = 0;
  attrs: Map<string, string> = new Map<string, string>();

  constructor(tag: string, order: number, text: string = '', parent?: HtmlNode) {
    this.tag = tag;
    this.order = order;
    this.text = text;
    this.parent = parent;
  }

  attr(name: string): string {
    return this.attrs.get(name.toLowerCase()) ?? '';
  }
}

export function decodeEntities(input: string): string {
  return input.replace(/&(#(?:[xX][\da-fA-F]+|\d+)|[a-zA-Z][a-zA-Z0-9]+);/g, (raw: string, entity: string): string => {
    if (entity.startsWith('#')) {
      const hex: boolean = entity[1] === 'x' || entity[1] === 'X';
      const value: number = Number.parseInt(entity.slice(hex ? 2 : 1), hex ? 16 : 10);
      if (value > 0 && value <= 0x10ffff && !(value >= 0xd800 && value <= 0xdfff)) {
        return String.fromCodePoint(value);
      }
      return '\ufffd';
    }
    switch (entity.toLowerCase()) {
      case 'amp': return '&';
      case 'lt': return '<';
      case 'gt': return '>';
      case 'quot': return '"';
      case 'apos': return "'";
      case 'nbsp': return '\u00a0';
      case 'ensp': return '\u2002';
      case 'emsp': return '\u2003';
      case 'thinsp': return '\u2009';
      case 'hellip': return '…';
      case 'middot': return '·';
      case 'mdash': return '—';
      case 'ndash': return '–';
      case 'lsquo': return '‘';
      case 'rsquo': return '’';
      case 'ldquo': return '“';
      case 'rdquo': return '”';
      case 'laquo': return '«';
      case 'raquo': return '»';
      case 'copy': return '©';
      case 'reg': return '®';
      case 'bull': return '•';
      default: return raw;
    }
  });
}

export class HtmlDocument {
  readonly root: HtmlNode = new HtmlNode('#document', 0);
  private current: HtmlNode = this.root;
  private sequence: number = 0;

  static parse(html: string): HtmlDocument {
    const document: HtmlDocument = new HtmlDocument();
    document.scan(html);
    return document;
  }

  private scan(html: string): void {
    const lower: string = html.replace(/[A-Z]/g, (letter: string): string => letter.toLowerCase());
    let offset: number = 0;
    while (offset < html.length) {
      const start: number = html.indexOf('<', offset);
      if (start < 0) {
        this.appendText(html.slice(offset));
        break;
      }
      this.appendText(html.slice(offset, start));
      if (html.startsWith('<!--', start)) {
        const end: number = html.indexOf('-->', start + 4);
        offset = end < 0 ? html.length : end + 3;
        continue;
      }
      const next: string = html.charAt(start + 1);
      if (!/[A-Za-z/!?]/.test(next)) {
        this.appendText('<');
        offset = start + 1;
        continue;
      }
      const end: number = this.tagEnd(html, start + 1);
      if (end < 0) {
        this.appendText(html.slice(start));
        break;
      }

      const token: string = html.slice(start + 1, end);
      offset = end + 1;
      const open: RegExpMatchArray | null = token.match(/^([a-zA-Z][\w:-]*)/);
      if (open !== null) {
        const tag: string = open[1].toLowerCase();
        this.open(tag, token.slice(open[0].length), token.endsWith('/'));
        if (!token.endsWith('/') && (INVISIBLE_TAGS.includes(tag) || tag === 'title' || tag === 'textarea')) {
          const close: number = this.rawTagClose(lower, tag, offset);
          if (close < 0) {
            offset = html.length;
          } else {
            if (tag === 'title' || tag === 'textarea') {
              this.appendText(html.slice(offset, close));
            }
            offset = close;
          }
        }
      } else {
        const closing: RegExpMatchArray | null = token.match(/^\/\s*([a-zA-Z][\w:-]*)/);
        if (closing !== null) {
          this.close(closing[1].toLowerCase());
        }
      }
    }
  }

  private rawTagClose(lower: string, tag: string, from: number): number {
    const pattern: string = '</' + tag;
    let at: number = lower.indexOf(pattern, from);
    while (at >= 0) {
      if (/[\s>\/]/.test(lower.charAt(at + pattern.length))) {
        return at;
      }
      at = lower.indexOf(pattern, at + pattern.length);
    }
    return -1;
  }

  private tagEnd(html: string, start: number): number {
    let quote: string = '';
    let expectingValue: boolean = false;
    let unquotedValue: boolean = false;
    for (let index: number = start; index < html.length; index++) {
      const char: string = html.charAt(index);
      if (quote.length > 0) {
        if (char === quote) {
          quote = '';
        }
        continue;
      }
      if (char === '>') {
        return index;
      }
      if (unquotedValue) {
        if (/\s/.test(char)) {
          unquotedValue = false;
        }
        continue;
      }
      if (expectingValue) {
        if (/\s/.test(char)) {
          continue;
        }
        expectingValue = false;
        if (char === '"' || char === "'") {
          quote = char;
        } else {
          unquotedValue = true;
        }
      } else if (char === '=') {
        // A stray quote outside an attribute value must not consume later tags.
        expectingValue = true;
      }
    }
    return -1;
  }

  private open(tag: string, attributeText: string, selfClosing: boolean): void {
    if (this.current.tag === 'p' && BLOCK_TAGS.includes(tag) ||
      this.current.tag === tag && OPTIONAL_CLOSE.includes(tag) ||
      (this.current.tag === 'td' || this.current.tag === 'th') && (tag === 'td' || tag === 'th')) {
      this.current = this.current.parent ?? this.root;
    }

    if (tag === 'tr') {
      this.startTableRow();
    } else if (TABLE_SECTIONS.includes(tag) && TABLE_SECTIONS.includes(this.current.tag)) {
      this.current = this.current.parent ?? this.root;
    }

    const node: HtmlNode = new HtmlNode(tag, this.nextOrder(), '', this.current);
    const attributes: RegExp = /(?:^|\s)([^\s=\/"'<>]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>]+)))?/g;
    let matched: RegExpExecArray | null = attributes.exec(attributeText);
    while (matched !== null) {
      const name: string = matched[1].toLowerCase();
      if (!node.attrs.has(name)) {
        node.attrs.set(name, decodeEntities(matched[2] ?? matched[3] ?? matched[4] ?? ''));
      }
      matched = attributes.exec(attributeText);
    }
    node.elementIndex = ++this.current.elementChildren;
    this.current.children.push(node);
    if (!selfClosing && !VOID_TAGS.includes(tag)) {
      this.current = node;
    }
  }

  private startTableRow(): void {
    let ancestor: HtmlNode | undefined = this.current;
    while (ancestor !== undefined && ancestor.tag !== 'table' && !TABLE_SECTIONS.includes(ancestor.tag)) {
      if (ancestor.tag === 'tr') {
        this.current = ancestor.parent ?? this.root;
        break;
      }
      ancestor = ancestor.parent;
    }
    if (this.current.tag === 'table') {
      const body: HtmlNode = new HtmlNode('tbody', this.nextOrder(), '', this.current);
      body.elementIndex = ++this.current.elementChildren;
      this.current.children.push(body);
      this.current = body;
    }
  }

  private close(tag: string): void {
    let node: HtmlNode | undefined = this.current;
    while (node !== undefined) {
      if (node.tag === tag) {
        this.current = node.parent ?? this.root;
        return;
      }
      node = node.parent;
    }
  }

  private appendText(text: string): void {
    if (text.length > 0) {
      this.current.children.push(new HtmlNode('', this.nextOrder(), decodeEntities(text), this.current));
    }
  }

  private nextOrder(): number {
    if (++this.sequence > MAX_NODES) {
      throw new Error('页面节点过多，无法提取小说内容');
    }
    return this.sequence;
  }
}

class TextVisit {
  node: HtmlNode;
  closing: boolean;

  constructor(node: HtmlNode, closing: boolean = false) {
    this.node = node;
    this.closing = closing;
  }
}

export function nodeText(root: HtmlNode, ownOnly: boolean = false): string {
  if (ownOnly) {
    const pieces: string[] = [];
    for (const child of root.children) {
      if (child.tag.length === 0) {
        pieces.push(child.text);
      }
    }
    return pieces.join(' ').replace(/\s+/g, ' ').trim();
  }

  const result: string[] = [];
  const queue: TextVisit[] = [new TextVisit(root)];
  while (queue.length > 0) {
    const visit: TextVisit | undefined = queue.pop();
    if (visit === undefined) {
      break;
    }
    const node: HtmlNode = visit.node;
    if (visit.closing || node.tag === 'br') {
      result.push('\n');
    } else if (node.tag.length === 0) {
      result.push(node.text.replace(/[ \t\f\v\r\n]+/g, ' '));
    } else if (!INVISIBLE_TAGS.includes(node.tag)) {
      if (BLOCK_TAGS.includes(node.tag)) {
        result.push('\n');
        queue.push(new TextVisit(node, true));
      }
      for (let index: number = node.children.length - 1; index >= 0; index--) {
        queue.push(new TextVisit(node.children[index]));
      }
    }
  }

  return result.join('').split('\n').map((line: string) => line.trim())
    .filter((line: string) => line.length > 0).join('\n');
}

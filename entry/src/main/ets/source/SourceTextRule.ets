const MAX_TEXT: number = 240000;
const MAX_COMPLEX_INPUT: number = 512;

export type TextTransform = (value: string) => string;

export class TextCleanup {
  private readonly pattern: RegExp;
  private readonly substitution: string;
  private readonly firstOnly: boolean;
  private readonly complex: boolean;
  private readonly lineLocal: boolean;

  constructor(pattern: RegExp, substitution: string, firstOnly: boolean, complex: boolean, lineLocal: boolean) {
    this.pattern = pattern;
    this.substitution = substitution;
    this.firstOnly = firstOnly;
    this.complex = complex;
    this.lineLocal = lineLocal;
  }

  apply(value: string): string {
    if (value.length > MAX_TEXT) {
      throw new Error('文本清理输入超过长度限制');
    }
    if (!this.complex || value.length <= MAX_COMPLEX_INPUT) {
      return this.replace(value);
    }
    if (!this.lineLocal || this.firstOnly) {
      throw new Error('复杂文本清理规则的输入超过 ' + MAX_COMPLEX_INPUT + ' 字符');
    }
    const lines: string[] = value.split('\n');
    for (let index: number = 0; index < lines.length; index++) {
      if (lines[index].length > MAX_COMPLEX_INPUT) {
        throw new Error('复杂文本清理规则的单行输入超过 ' + MAX_COMPLEX_INPUT + ' 字符');
      }
      lines[index] = this.replace(lines[index]);
    }
    return lines.join('\n');
  }

  private replace(value: string): string {
    if (!this.firstOnly) {
      return value.replace(this.pattern, this.substitution);
    }
    const match: RegExpExecArray | null = this.pattern.exec(value);
    return match === null ? '' : match[0].replace(this.pattern, this.substitution);
  }
}

export function compileTextCleanup(tail: string): TextCleanup {
  const parts: string[] = tail.split('##');
  if (parts.length > 3 || parts[0].length === 0 || parts[0].length > 320 ||
    (parts[1]?.length ?? 0) > 240 || parts.length === 3 && parts[2] !== '' && parts[2] !== '#') {
    throw new Error('文本清理需要 ##表达式、##表达式##替换内容 或末尾 ###');
  }
  return compileReplacement(parts[0], parts[1] ?? '', parts.length === 3);
}

export function compileReplacement(raw: string, replacement: string, firstOnly: boolean = false,
  ignoreCase: boolean = false, single: boolean = false): TextCleanup {
  const insensitive: boolean = ignoreCase || raw.startsWith('(?i)');
  const pattern: string = raw.startsWith('(?i)') ? raw.slice(4) : raw;
  const complex: boolean = validatePattern(pattern);
  const lines: boolean = !/\\[sSrnvxucDWB]|\[\^|[\r\n^$]/.test(pattern) &&
    !/\$[\x60']/.test(replacement);
  try {
    const flags: string = (firstOnly || single ? '' : 'g') + (insensitive ? 'i' : '');
    return new TextCleanup(new RegExp(pattern, flags), replacement, firstOnly, complex, lines && !single);
  } catch {
    throw new Error('文本清理正则表达式无效');
  }
}

function validatePattern(pattern: string): boolean {
  if (pattern.length === 0 || pattern.length > 320 || pattern.includes('{{')) {
    throw new Error('文本清理正则表达式为空、过长或含动态模板');
  }
  let inClass: boolean = false;
  let depth: number = 0;
  let alternatives: number = 0;
  let groups: number = 0;
  let innerAlternatives: number = 0;
  let branchStart: number = 0;
  let repeats: number = 0;
  let broad: number = 0;
  let complex: boolean = false;
  let atom: string = '';
  let repeatBefore: boolean = false;
  for (let index: number = 0; index < pattern.length; index++) {
    const char: string = pattern.charAt(index);
    if (char === '\\') {
      const escaped: string = pattern.charAt(++index);
      if (/[1-9k]/.test(escaped) || escaped.length === 0) {
        throw new Error('文本清理正则表达式不支持反向引用');
      }
      if (!inClass) {
        atom = escaped === 'b' || escaped === 'B' ? '' : 'escape';
      }
    } else if (inClass) {
      if (char === ']') {
        inClass = false;
        atom = 'class';
      }
    } else if (char === '[') {
      inClass = true;
    } else if (char === '(') {
      if (pattern.startsWith('(?:', index)) {
        index += 2;
      } else if (pattern.charAt(index + 1) === '?') {
        throw new Error('文本清理正则表达式不支持查找断言');
      }
      if (++depth > 3 || ++groups > 8) {
        throw new Error('文本清理正则表达式分组过多');
      }
      atom = '';
    } else if (char === ')') {
      depth--;
      atom = 'group';
    } else if (char === '|') {
      if (++alternatives > 48 || depth > 0 && ++innerAlternatives > 6) {
        throw new Error('文本清理正则表达式备选分支过多');
      }
      if (depth === 0) {
        branchStart = index + 1;
        repeats = 0;
        broad = 0;
        repeatBefore = false;
      }
      atom = '';
    } else if ('*+?{'.includes(char)) {
      if (char === '?' && repeatBefore) {
        repeatBefore = false;
        continue;
      }
      const anchored: boolean = pattern.charAt(branchStart) === '^';
      if (atom.length === 0 || atom === 'group' || ++repeats > (anchored ? 4 : 2)) {
        throw new Error('文本清理正则表达式含过于复杂的重复');
      }
      if (char === '{') {
        const range: RegExpMatchArray | null = pattern.slice(index).match(/^\{(\d{1,3})(?:,(\d{0,3}))?\}/);
        if (range === null || Number(range[1]) > 160 || Number(range[2] ?? 0) > 160) {
          throw new Error('文本清理正则表达式的范围量词无效');
        }
        index += range[0].length - 1;
      }
      if (atom === '.' && ++broad > 2) {
        throw new Error('文本清理正则表达式包含过多重复通配符');
      }
      complex = complex || repeats > 1 || !anchored && (char !== '?' || atom === '.');
      repeatBefore = true;
      atom = '';
    } else {
      atom = char === '^' || char === '$' ? '' : char;
      repeatBefore = false;
    }
  }
  return complex;
}

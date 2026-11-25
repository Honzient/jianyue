import { JsonObject, JsonValue, jsonRecord } from '../model/LegadoBookSource';

const MAX_RESULTS: number = 10000;
const MAX_VISITS: number = 120000;

type SelectValues = (value: JsonValue, result: JsonValue[]) => void;

class PathStep {
  readonly select: SelectValues;
  readonly deep: boolean;

  constructor(select: SelectValues, deep: boolean) {
    this.select = select;
    this.deep = deep;
  }
}

export class JsonPath {
  private readonly steps: PathStep[];

  constructor(expression: string) {
    this.steps = parsePath(expression);
  }

  select(root: JsonValue): JsonValue[] {
    let current: JsonValue[] = [root];
    let visits: number = 0;
    for (const step of this.steps) {
      const next: JsonValue[] = [];
      const pending: JsonValue[] = current.slice().reverse();
      while (pending.length > 0 && next.length < MAX_RESULTS) {
        const value: JsonValue = pending.pop() as JsonValue;
        if (++visits > MAX_VISITS) {
          throw new Error('JSONPath 遍历超过节点数限制');
        }
        step.select(value, next);
        if (step.deep && value !== null && typeof value === 'object') {
          const children: JsonValue[] = [];
          appendChildren(value, children);
          for (let index: number = children.length - 1; index >= 0; index--) {
            if (typeof children[index] === 'object' && children[index] !== null) {
              pending.push(children[index]);
            }
          }
        }
      }
      if (next.length === 0) {
        return next;
      }
      current = next.slice(0, MAX_RESULTS);
    }
    return current;
  }
}

function propertyValue(value: JsonValue, name: string): JsonValue | undefined {
  const record: JsonObject | undefined = jsonRecord(value);
  return record !== undefined && Object.keys(record).includes(name) ? record[name] : undefined;
}

function appendChildren(value: JsonValue, output: JsonValue[]): void {
  if (Array.isArray(value)) {
    const values: JsonValue[] = value as JsonValue[];
    for (let index: number = 0; index < values.length && output.length < MAX_RESULTS; index++) {
      output.push(values[index]);
    }
    return;
  }
  const record: JsonObject | undefined = jsonRecord(value);
  if (record !== undefined) {
    for (const key of Object.keys(record)) {
      const child: JsonValue | undefined = record[key];
      if (child !== undefined && output.length < MAX_RESULTS) {
        output.push(child);
      }
    }
  }
}

function propertySelector(name: string): SelectValues {
  return (value: JsonValue, output: JsonValue[]): void => {
    const item: JsonValue | undefined = propertyValue(value, name);
    if (item !== undefined) {
      output.push(item);
    }
  };
}

function indexSelector(index: number): SelectValues {
  return (value: JsonValue, output: JsonValue[]): void => {
    if (Array.isArray(value)) {
      const entries: JsonValue[] = value as JsonValue[];
      const actual: number = index < 0 ? entries.length + index : index;
      if (actual >= 0 && actual < entries.length) {
        output.push(entries[actual]);
      }
    }
  };
}

function sliceOffset(value: string, length: number, defaultIndex: number, minimum: number, maximum: number): number {
  if (value.length === 0) {
    return defaultIndex;
  }
  const index: number = Number(value);
  return Math.min(maximum, Math.max(minimum, index < 0 ? length + index : index));
}

function sliceSelector(first: string, last: string, step: number): SelectValues {
  if (step === 0) {
    throw new Error('JSONPath 切片步长需为非零整数');
  }
  return (value: JsonValue, output: JsonValue[]): void => {
    if (!Array.isArray(value)) {
      return;
    }
    const entries: JsonValue[] = value as JsonValue[];
    const length: number = entries.length;
    const forward: boolean = step > 0;
    const begin: number = sliceOffset(first, length, forward ? 0 : length - 1, forward ? 0 : -1,
      forward ? length : length - 1);
    const end: number = sliceOffset(last, length, forward ? length : -1, forward ? 0 : -1,
      forward ? length : length - 1);
    for (let index: number = begin; (forward ? index < end : index > end) && output.length < MAX_RESULTS;
      index += step) {
      output.push(entries[index]);
    }
  };
}

function filterSelector(property: string, operation: string, expected: JsonValue): SelectValues {
  return (value: JsonValue, output: JsonValue[]): void => {
    const items: JsonValue[] = [];
    appendChildren(value, items);
    for (const item of items) {
      const actual: JsonValue | undefined = propertyValue(item, property);
      if (actual !== undefined && (operation === '' || (operation === '==' ? actual === expected : actual !== expected))) {
        output.push(item);
        if (output.length >= MAX_RESULTS) {
          break;
        }
      }
    }
  };
}

function segmentSelector(raw: string): SelectValues {
  const value: string = raw.trim();
  if (value === '*') {
    return appendChildren;
  }
  if (/^-?\d{1,8}$/.test(value)) {
    return indexSelector(Number(value));
  }
  const property: RegExpMatchArray | null = value.match(/^(?:"([^"\\]*)"|'([^'\\]*)')$/);
  if (property !== null) {
    return propertySelector(property[1] ?? property[2]);
  }
  const slice: RegExpMatchArray | null = value.match(/^(-?\d{1,8})?\s*:\s*(-?\d{1,8})?(?:\s*:\s*(-?\d{1,8}))?$/);
  if (slice !== null) {
    return sliceSelector(slice[1] ?? '', slice[2] ?? '', Number(slice[3] ?? '1'));
  }
  const filter: RegExpMatchArray | null =
    value.match(/^\?\(\s*@\.([\w\u0080-\uffff-]+)(?:\s*(==|!=)\s*("[^"\\]*"|'[^'\\]*'|true|false|null|-?\d+(?:\.\d+)?))?\s*\)$/);
  if (filter !== null) {
    const constant: string = filter[3] ?? 'null';
    const expected: JsonValue = /^["']/.test(constant) ? constant.slice(1, -1) : JSON.parse(constant) as JsonValue;
    return filterSelector(filter[1], filter[2] ?? '', expected);
  }
  throw new Error('JSONPath 下标需要属性名、整数、切片、通配符或简单属性条件');
}

function bracketSelector(raw: string): SelectValues {
  const entries: string[] = [];
  let quote: string = '';
  let from: number = 0;
  for (let index: number = 0; index < raw.length; index++) {
    const char: string = raw.charAt(index);
    if (quote.length > 0) {
      if (char === quote) {
        quote = '';
      }
    } else if (char === '"' || char === "'") {
      quote = char;
    } else if (char === ',') {
      entries.push(raw.slice(from, index));
      from = index + 1;
    }
  }
  entries.push(raw.slice(from));
  if (entries.length > 16) {
    throw new Error('JSONPath 并列下标超过 16 项');
  }
  if (entries.length === 1) {
    return segmentSelector(entries[0]);
  }
  const selectors: SelectValues[] = entries.map((entry: string): SelectValues => segmentSelector(entry));
  return (value: JsonValue, output: JsonValue[]): void => {
    for (const select of selectors) {
      if (output.length >= MAX_RESULTS) {
        break;
      }
      select(value, output);
    }
  };
}

function bracketEnd(input: string): number {
  let quote: string = '';
  for (let index: number = 1; index < input.length; index++) {
    const char: string = input.charAt(index);
    if (quote.length > 0) {
      if (char === quote) {
        quote = '';
      }
    } else if (char === "'" || char === '"') {
      quote = char;
    } else if (char === ']') {
      return index;
    }
  }
  return -1;
}

function parsePath(expression: string): PathStep[] {
  const raw: string = expression.replace(/^@json:\s*/i, '');
  let rest: string = raw.startsWith('$') ? raw.slice(1) : raw.startsWith('[') ? raw : '.' + raw;
  const steps: PathStep[] = [];
  while (rest.length > 0) {
    const deep: boolean = rest.startsWith('..');
    const dot: boolean = deep || rest.startsWith('.');
    if (dot) {
      rest = rest.slice(deep ? 2 : 1);
    }
    if (rest.startsWith('[')) {
      const end: number = bracketEnd(rest);
      if (end < 0) {
        throw new Error('JSONPath 方括号未配对');
      }
      steps.push(new PathStep(bracketSelector(rest.slice(1, end)), deep));
      rest = rest.slice(end + 1);
    } else {
      const name: RegExpMatchArray | null = dot ? rest.match(/^(?:[\w\u0080-\uffff-]+|\*)/) : null;
      if (name === null) {
        throw new Error('JSONPath 属性或下标格式无效');
      }
      steps.push(new PathStep(name[0] === '*' ? appendChildren : propertySelector(name[0]), deep));
      rest = rest.slice(name[0].length);
    }
    if (steps.length > 24) {
      throw new Error('JSONPath 层数超过 24 层');
    }
  }
  return steps;
}

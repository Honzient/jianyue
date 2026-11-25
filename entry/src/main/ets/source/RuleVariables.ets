import { JsonValue, parseJson } from '../model/LegadoBookSource';

const MAX_VARIABLES: number = 32;

export class RuleVariables {
  private readonly values: Map<string, string> = new Map<string, string>();

  constructor(serialized: string = '') {
    if (serialized.length === 0 || serialized.length > 130000) {
      return;
    }
    try {
      const data: JsonValue = parseJson(serialized, '无效书籍变量');
      if (Array.isArray(data)) {
        for (const entry of (data as JsonValue[]).slice(0, MAX_VARIABLES)) {
          if (Array.isArray(entry)) {
            const pair: JsonValue[] = entry as JsonValue[];
            if (pair.length === 2 && typeof pair[0] === 'string' && typeof pair[1] === 'string') {
              this.put(pair[0], pair[1]);
            }
          }
        }
      }
    } catch {
      // A book saved before variable support can open with an empty scope.
    }
  }

  get(key: string): string {
    return this.values.get(key) ?? '';
  }

  put(key: string, value: string): void {
    if (/^[\w-]{1,48}$/.test(key) && value.trim().length > 0 && value.length <= 2000 &&
      (this.values.has(key) || this.values.size < MAX_VARIABLES)) {
      this.values.set(key, value);
    }
  }

  serialize(): string {
    if (this.values.size === 0) {
      return '';
    }
    const pairs: string[][] = [];
    this.values.forEach((value: string, key: string): void => {
      pairs.push([key, value]);
    });
    return JSON.stringify(pairs);
  }
}

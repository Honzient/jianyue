import { JsonObject, JsonValue, jsonRecord, parseJson } from '../model/LegadoBookSource';

export const RAW_TEMPLATE: string = '\ufdd0';

export function staticOptions(raw: string, message: string, templates: boolean = false): JsonObject {
  if (raw.includes(RAW_TEMPLATE) || /\\ufdd0/i.test(raw)) {
    throw new Error(message);
  }
  try {
    const value: JsonValue = parseJson(normalizeOptions(raw, templates), message);
    const options: JsonObject | undefined = jsonRecord(value);
    if (options !== undefined) {
      return options;
    }
  } catch {
    // The declaration is data. A malformed option cannot be executed.
  }
  throw new Error(message);
}

function normalizeOptions(raw: string, templates: boolean): string {
  let result: string = '';
  let index: number = 0;
  while (index < raw.length) {
    const value: string = raw.charAt(index);
    if (value === '"' || value === "'") {
      const end: number = endQuote(raw, index);
      const text: string = raw.slice(index + 1, end);
      result += value === '"' ? raw.slice(index, end + 1) :
        '"' + text.replace(/\\'|\\.|"/g, (token: string): string => token === "\\'" ? "'" :
          token === '"' ? '\\"' : token) + '"';
      index = end + 1;
    } else if (templates && raw.startsWith('{{', index)) {
      const end: number = raw.indexOf('}}', index + 2);
      if (end < 0) {
        throw new Error('请求选项的模板括号未配对');
      }
      result += JSON.stringify(RAW_TEMPLATE + raw.slice(index, end + 2));
      index = end + 2;
    } else if (value === ',' && /^\s*[}\]]/.test(raw.slice(index + 1))) {
      index++;
    } else {
      const name: RegExpMatchArray | null = /[a-zA-Z_]/.test(value) ?
        raw.slice(index).match(/^([a-zA-Z_][\w-]*)\s*(?=:)/) : null;
      if (name !== null) {
        result += JSON.stringify(name[1]);
        index += name[0].length;
      } else {
        result += value;
        index++;
      }
    }
  }
  return result;
}

function endQuote(input: string, from: number): number {
  const quote: string = input.charAt(from);
  for (let index: number = from + 1; index < input.length; index++) {
    const current: string = input.charAt(index);
    if (current === '\\') {
      index++;
    } else if (current === quote) {
      return index;
    }
  }
  throw new Error('请求选项的引号未配对');
}

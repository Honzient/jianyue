import { util } from '@kit.ArkTS';
import { decodeText } from '../novel/TextNovel';
import { staticOptions } from './RequestOptions';
import { compileReplacement, TextCleanup, TextTransform } from './SourceTextRule';

export function compileResultTransform(raw: string): TextTransform {
  const expression: string = raw.trim().replace(/;\s*$/, '');
  if (expression === 'result') {
    return (value: string): string => value;
  }
  if (/^java\.base64Decode\(\s*result\s*\)$/.test(expression)) {
    return (value: string): string => decodeText(new util.Base64Helper().decodeSync(value));
  }
  const replace: RegExpMatchArray | null = expression.match(
    /^result\.replace\(\s*\/((?:\\.|[^/\\])+)\s*\/(gi|ig|g|i)?\s*,\s*((?:"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'))\s*\)$/);
  if (replace !== null) {
    const flags: string = replace[2] ?? '';
    const rule: TextCleanup = compileReplacement(replace[1], quotedText(replace[3]), false,
      flags.includes('i'), !flags.includes('g'));
    return (value: string): string => rule.apply(value);
  }
  return compileJoin(expression);
}

function compileJoin(expression: string): TextTransform {
  const quoted: string = "(?:\"(?:\\\\.|[^\"\\\\])*\"|'(?:\\\\.|[^'\\\\])*')";
  const pattern: RegExp = new RegExp('^(?:(' + quoted + ')\\s*\\+\\s*)?' +
    '(result|encodeURIComponent\\(\\s*result\\s*\\))' + '(?:\\s*\\+\\s*(' + quoted + '))?$');
  const parts: RegExpMatchArray | null = expression.match(pattern);
  if (parts === null || parts[1] === undefined && parts[3] === undefined) {
    throw new Error('当前规则需要执行书源脚本');
  }
  const prefix: string = parts[1] === undefined ? '' : quotedText(parts[1]);
  const suffix: string = parts[3] === undefined ? '' : quotedText(parts[3]);
  const encode: boolean = parts[2] !== 'result';
  return (value: string): string => value.length === 0 ? '' : prefix + (encode ? encodeURIComponent(value) : value) + suffix;
}

function quotedText(token: string): string {
  const value = staticOptions('{value:' + token + '}', '规则需要静态字符串')['value'];
  if (typeof value !== 'string') {
    throw new Error('规则需要静态字符串');
  }
  return value;
}

import { url, util } from '@kit.ArkTS';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const ROTATE_BYTES: number = 256 * 1024;

export enum LogLevel {
  Info = 'INFO',
  Warning = 'WARN',
  Error = 'ERROR'
}

export class SourceTrace {
  private log: SourceLog;
  private run: string;
  private source: string;
  private origin: string;

  constructor(log: SourceLog, run: string, source: string = '', address: string = '') {
    this.log = log;
    this.run = safeLine(run, 20);
    this.source = safeLine(source, 80);
    this.origin = requestOrigin(address);
  }

  event(level: LogLevel, step: string, detail: string, address: string = ''): void {
    const origin: string = requestOrigin(address) || this.origin;
    const location: string = this.source.length > 0 ? ' ' + this.source + (origin ? ' @ ' + origin : '') : '';
    this.log.append(new Date().toISOString() + ' [' + this.run + '] [' + level + '] ' +
      safeLine(step, 45) + location + ' · ' + safeLine(detail, 420));
  }
}

export class SourceLog {
  private directory: string;
  private latest: string;
  private previous: string;
  private tail: Promise<void> = Promise.resolve();

  constructor(filesDir: string) {
    this.directory = filesDir + '/diagnostics';
    this.latest = this.directory + '/source.log';
    this.previous = this.directory + '/source.previous.log';
  }

  trace(run: string, source: string = '', address: string = ''): SourceTrace {
    return new SourceTrace(this, run, source, address);
  }

  append(line: string): void {
    const data: Uint8Array = new util.TextEncoder().encodeInto(line + '\n');
    this.tail = this.tail.then(async (): Promise<void> => {
      if (!await fileIo.access(this.directory)) {
        await fileIo.mkdir(this.directory, true);
      }
      if (await fileIo.access(this.latest)) {
        const size: number = (await fileIo.stat(this.latest)).size;
        if (size + data.length > ROTATE_BYTES) {
          await fileIo.rename(this.latest, this.previous);
        }
      }
      await writeBytes(this.latest, data, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.APPEND);
    }).catch((): void => {
      hilog.warn(0x0010, 'Jianyue', 'Could not persist a source log entry');
    });
  }

  flush(): Promise<void> {
    return this.tail;
  }

  snapshot(): Promise<string> {
    const read: Promise<string> = this.tail.then(async (): Promise<string> => {
      const previous: string = await fileIo.access(this.previous) ? await fileIo.readText(this.previous) : '';
      const latest: string = await fileIo.access(this.latest) ? await fileIo.readText(this.latest) : '';
      return previous + latest;
    });
    this.tail = read.then((): void => {}, (): void => {});
    return read;
  }

  async exportTo(uri: string): Promise<void> {
    const snapshot: string = await this.snapshot();
    await writeBytes(uri, new util.TextEncoder().encodeInto(snapshot),
      fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
  }
}

export function newTraceId(): string {
  return util.generateRandomUUID().slice(0, 8);
}

function requestOrigin(address: string): string {
  if (address.length === 0) {
    return '';
  }
  try {
    const value: url.URL = url.URL.parseURL(address);
    return safeLine(value.protocol + '//' + value.host, 120);
  } catch {
    return '';
  }
}

function safeLine(text: string, maxLength: number): string {
  return text.replace(/[\u0000-\u001f\u007f\u2028\u2029]/g, ' ').trim().slice(0, maxLength);
}

async function writeBytes(path: string, bytes: Uint8Array, mode: number): Promise<void> {
  const handle: fileIo.File = await fileIo.open(path, mode);
  try {
    let offset: number = 0;
    while (offset < bytes.length) {
      const rest: ArrayBuffer = bytes.buffer.slice(bytes.byteOffset + offset, bytes.byteOffset + bytes.length);
      const size: number = await fileIo.write(handle.fd, rest);
      if (size <= 0) {
        throw new Error('日志写入中断');
      }
      offset += size;
    }
  } finally {
    await fileIo.close(handle);
  }
}

import { common } from '@kit.AbilityKit';
import { fileIo, fileUri, picker } from '@kit.CoreFileKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { Book, Chapter } from '../model/LibraryModels';
import { decodeText, TextChapter } from '../novel/TextNovel';

const BOOK_LIMIT: number = 32 * 1024 * 1024;
const SOURCE_LIMIT: number = 16 * 1024 * 1024;
const IO_CHUNK_SIZE: number = 256 * 1024;

export async function pickDocument(context: common.UIAbilityContext, title: string, suffix: string): Promise<string> {
  const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
  options.maxSelectNumber = 1;
  options.fileSuffixFilters = [title + '|' + suffix];
  const selected: string[] = await new picker.DocumentViewPicker(context).select(options);
  return selected.length > 0 ? selected[0] : '';
}

export function documentBaseName(uri: string): string {
  const name: string = new fileUri.FileUri(uri).name;
  const title: string = name.replace(/\.txt$/i, '').trim();
  return title.length > 0 ? title : '未命名小说';
}

export class NovelFiles {
  private localDirectory: string;
  private cacheDirectory: string;
  private encoder: util.TextEncoder = new util.TextEncoder();

  constructor(context: common.UIAbilityContext) {
    this.localDirectory = context.filesDir + '/local_books';
    this.cacheDirectory = context.filesDir + '/online_chapters';
  }

  async rawNovel(uri: string): Promise<Uint8Array> {
    return this.readDocument(uri, BOOK_LIMIT, 'TXT 文件需小于或等于 32 MB');
  }

  async sourceJson(uri: string): Promise<string> {
    return decodeText(await this.readDocument(uri, SOURCE_LIMIT, '书源 JSON 需小于或等于 16 MB'));
  }

  async identity(bytes: Uint8Array): Promise<string> {
    const md: cryptoFramework.Md = cryptoFramework.createMd('SHA256');
    await md.update({ data: bytes });
    const digest: Uint8Array = (await md.digest()).data;
    let hex: string = '';
    for (const value of digest) {
      hex += value.toString(16).padStart(2, '0');
    }
    return 'local:' + hex;
  }

  async saveLocalBook(book: Book, bytes: Uint8Array, chapters: TextChapter[]): Promise<Chapter[]> {
    await this.ensureDirectory(this.localDirectory);
    const directory: string = this.localDirectory + '/' + book.id;
    await fileIo.mkdir(directory);
    try {
      await this.writeFile(directory + '/original.txt', bytes);
      const handle: fileIo.File = await fileIo.open(directory + '/text.txt', fileIo.OpenMode.CREATE |
        fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      try {
        const indexed: Chapter[] = [];
        let offset: number = 0;
        for (const chapter of chapters) {
          const body: Uint8Array = chapter.text.length > 0
            ? this.encoder.encodeInto(chapter.text)
            : new Uint8Array(0);
          await this.writeBytes(handle.fd, body, offset);
          indexed.push(new Chapter(book.id + ':' + indexed.length, book.id, indexed.length,
            chapter.title, '', offset, body.length));
          offset += body.length;
        }
        await fileIo.fsync(handle.fd);
        return indexed;
      } finally {
        await fileIo.close(handle);
      }
    } catch (error) {
      await this.discardLocalBook(book.id);
      throw error as Error;
    }
  }

  async readLocalChapter(chapter: Chapter): Promise<string> {
    const handle: fileIo.File = await fileIo.open(
      this.localDirectory + '/' + chapter.bookId + '/text.txt', fileIo.OpenMode.READ_ONLY);
    try {
      const bytes: Uint8Array = await this.readBytes(handle.fd, chapter.byteLength, chapter.byteOffset);
      return decodeText(bytes, 'utf-8');
    } finally {
      await fileIo.close(handle);
    }
  }

  async discardLocalBook(bookId: string): Promise<void> {
    const directory: string = this.localDirectory + '/' + bookId;
    try {
      await this.removeFile(directory + '/original.txt');
      await this.removeFile(directory + '/text.txt');
      if (await fileIo.access(directory)) {
        await fileIo.rmdir(directory);
      }
    } catch {
      // Preserve the original import error.
    }
  }

  async readCachedChapter(chapter: Chapter): Promise<string | undefined> {
    const path: string = this.cachePath(chapter);
    if (!await fileIo.access(path)) {
      return undefined;
    }
    return fileIo.readText(path);
  }

  async cacheChapter(chapter: Chapter, body: string): Promise<void> {
    await this.ensureDirectory(this.cacheDirectory);
    const path: string = this.cachePath(chapter);
    const temporary: string = path + '.' + util.generateRandomUUID() + '.tmp';
    try {
      await this.writeFile(temporary, this.encoder.encodeInto(body));
      await fileIo.rename(temporary, path);
    } catch (error) {
      await this.removeFile(temporary);
      throw error as Error;
    }
  }

  private cachePath(chapter: Chapter): string {
    return this.cacheDirectory + '/' + chapter.id + '.txt';
  }

  private async readDocument(uri: string, limit: number, tooLarge: string): Promise<Uint8Array> {
    const file: fileIo.File = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    try {
      const size: number = (await fileIo.stat(file.fd)).size;
      if (size > limit) {
        throw new Error(tooLarge);
      }
      // Finish every async read before finally closes the selected file.
      return await this.readBytes(file.fd, size, 0);
    } finally {
      await fileIo.close(file);
    }
  }

  private async readBytes(fd: number, length: number, offset: number): Promise<Uint8Array> {
    const output: Uint8Array = new Uint8Array(length);
    if (length === 0) {
      return output;
    }
    const chunk: ArrayBuffer = new ArrayBuffer(Math.min(IO_CHUNK_SIZE, length));
    let read: number = 0;
    while (read < length) {
      const count: number = await fileIo.read(fd, chunk, { offset: offset + read,
        length: Math.min(chunk.byteLength, length - read) });
      if (count <= 0) {
        throw new Error('文件在读取时已改变或不完整');
      }
      output.set(new Uint8Array(chunk, 0, count), read);
      read += count;
    }
    return output;
  }

  private async writeFile(path: string, data: Uint8Array): Promise<void> {
    const file: fileIo.File = await fileIo.open(path, fileIo.OpenMode.CREATE |
      fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      await this.writeBytes(file.fd, data);
      await fileIo.fsync(file.fd);
    } finally {
      await fileIo.close(file);
    }
  }

  private async writeBytes(fd: number, bytes: Uint8Array, offset: number = 0): Promise<void> {
    let start: number = 0;
    while (start < bytes.length) {
      const end: number = Math.min(bytes.length, start + IO_CHUNK_SIZE);
      const buffer: ArrayBuffer = bytes.buffer.slice(bytes.byteOffset + start, bytes.byteOffset + end);
      const count: number = await fileIo.write(fd, buffer, { offset: offset + start });
      if (count <= 0) {
        throw new Error('写入小说文件失败');
      }
      start += count;
    }
  }

  private async ensureDirectory(path: string): Promise<void> {
    if (!await fileIo.access(path)) {
      try {
        await fileIo.mkdir(path, true);
      } catch (error) {
        if (!await fileIo.access(path)) {
          throw error as Error;
        }
      }
    }
  }

  private async removeFile(path: string): Promise<void> {
    if (await fileIo.access(path)) {
      await fileIo.unlink(path);
    }
  }
}

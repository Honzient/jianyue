import { Chapter } from '../model/LibraryModels';

/*
 * Pure directory-filter helpers for the reader.
 *
 * The stored chapter order and chapter.index are never rewritten here: the directory keeps
 * showing the original ordinal (chapter.index + 1) and these functions only decide which
 * chapters remain visible in the virtual list.
 */

const MAX_ORDINAL_DIGITS: number = 9;

// The ordinal readers see in the directory: chapter.index is zero based, the panel is not.
export function chapterOrdinal(chapter: Chapter): number {
  return chapter.index + 1;
}

// Empty keyword keeps every chapter; digits match the ordinal exactly, text matches the title.
export function filterChapters(chapters: Chapter[], keyword: string): Chapter[] {
  const query: string = keyword.trim();
  if (query.length === 0) {
    return chapters.slice();
  }
  if (isOrdinalQuery(query)) {
    return ordinalMatches(chapters, ordinalValue(query));
  }
  return titleMatches(chapters, query.toLowerCase());
}

function isOrdinalQuery(query: string): boolean {
  if (query.length === 0) {
    return false;
  }
  for (let index: number = 0; index < query.length; index++) {
    const code: number = query.charCodeAt(index);
    if (code < 48 || code > 57) {
      return false;
    }
  }
  return true;
}

// Very long digit strings cannot be a real chapter ordinal; return 0 so nothing matches.
function ordinalValue(query: string): number {
  if (query.length > MAX_ORDINAL_DIGITS) {
    return 0;
  }
  let value: number = 0;
  for (let index: number = 0; index < query.length; index++) {
    value = value * 10 + (query.charCodeAt(index) - 48);
  }
  return value;
}

function ordinalMatches(chapters: Chapter[], ordinal: number): Chapter[] {
  const matches: Chapter[] = [];
  if (ordinal < 1) {
    return matches;
  }
  for (const chapter of chapters) {
    if (chapterOrdinal(chapter) === ordinal) {
      matches.push(chapter);
    }
  }
  return matches;
}

function titleMatches(chapters: Chapter[], needle: string): Chapter[] {
  const matches: Chapter[] = [];
  for (const chapter of chapters) {
    if (chapter.title.toLowerCase().includes(needle)) {
      matches.push(chapter);
    }
  }
  return matches;
}

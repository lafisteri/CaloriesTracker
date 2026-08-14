import type { DiaryEntry } from '@/domain/diary/diary-entry'

export interface DiaryRepository {
  createEntry(entry: DiaryEntry): Promise<void>
  updateEntry(entry: DiaryEntry): Promise<void>
  getEntryById(id: string): Promise<DiaryEntry | undefined>
  getEntriesByDate(date: string): Promise<DiaryEntry[]>
  getEntriesByDates(dates: string[]): Promise<DiaryEntry[]>
  getRecentEntries(): Promise<DiaryEntry[]>
  softDeleteEntry(id: string, deletedAt: string): Promise<void>
}

import type { DiaryEntry } from '@/domain/diary/diary-entry'

export interface DiaryRepository {
  save(entry: DiaryEntry): Promise<void>
  getById(id: string): Promise<DiaryEntry | undefined>
  getForDate(date: string): Promise<DiaryEntry[]>
}

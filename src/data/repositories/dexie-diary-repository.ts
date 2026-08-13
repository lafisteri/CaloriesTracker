import { appDatabase, type CalorieDatabase } from '@/data/database/calorie-database'
import type { DiaryEntry } from '@/domain/diary/diary-entry'
import type { DiaryRepository } from '@/domain/repositories/diary-repository'

export class DexieDiaryRepository implements DiaryRepository {
  constructor(private readonly database: CalorieDatabase = appDatabase) {}

  async createEntry(entry: DiaryEntry): Promise<void> {
    await this.database.diaryEntries.add(entry)
  }

  async updateEntry(entry: DiaryEntry): Promise<void> {
    await this.database.diaryEntries.put(entry)
  }

  getEntryById(id: string): Promise<DiaryEntry | undefined> {
    return this.database.diaryEntries.get(id)
  }

  getEntriesByDate(date: string): Promise<DiaryEntry[]> {
    return this.database.diaryEntries
      .where('date')
      .equals(date)
      .and((entry) => entry.deletedAt === undefined)
      .sortBy('createdAt')
  }

  async getRecentProductEntries(): Promise<DiaryEntry[]> {
    return this.database.diaryEntries
      .orderBy('createdAt')
      .reverse()
      .filter((entry) => entry.sourceType === 'product' && entry.deletedAt === undefined)
      .toArray()
  }

  async softDeleteEntry(id: string, deletedAt: string): Promise<void> {
    await this.database.diaryEntries.update(id, { deletedAt, updatedAt: deletedAt })
  }
}

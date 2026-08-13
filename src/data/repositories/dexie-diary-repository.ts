import { appDatabase, type CalorieDatabase } from '@/data/database/calorie-database'
import type { DiaryEntry } from '@/domain/diary/diary-entry'
import type { DiaryRepository } from '@/domain/repositories/diary-repository'

export class DexieDiaryRepository implements DiaryRepository {
  constructor(private readonly database: CalorieDatabase = appDatabase) {}

  async save(entry: DiaryEntry): Promise<void> {
    await this.database.diaryEntries.put(entry)
  }

  getById(id: string): Promise<DiaryEntry | undefined> {
    return this.database.diaryEntries.get(id)
  }

  getForDate(date: string): Promise<DiaryEntry[]> {
    return this.database.diaryEntries
      .where('date')
      .equals(date)
      .and((entry) => entry.deletedAt === undefined)
      .sortBy('createdAt')
  }
}

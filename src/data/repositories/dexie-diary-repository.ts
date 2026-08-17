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

  async updateEntries(entries: DiaryEntry[]): Promise<void> {
    await this.database.transaction('rw', this.database.diaryEntries, async () => {
      await this.database.diaryEntries.bulkPut(entries)
    })
  }

  getEntryById(id: string): Promise<DiaryEntry | undefined> {
    return this.database.diaryEntries.get(id)
  }

  async getEntriesByDate(date: string): Promise<DiaryEntry[]> {
    const entries = await this.database.diaryEntries
      .where('date')
      .equals(date)
      .and((entry) => entry.deletedAt === undefined)
      .toArray()

    return entries.sort(compareDiaryEntries)
  }

  async getEntriesByDates(dates: string[]): Promise<DiaryEntry[]> {
    if (dates.length === 0) {
      return []
    }

    return this.database.diaryEntries
      .where('date')
      .anyOf(dates)
      .and((entry) => entry.deletedAt === undefined)
      .toArray()
  }

  async getRecentEntries(): Promise<DiaryEntry[]> {
    return this.database.diaryEntries
      .orderBy('createdAt')
      .reverse()
      .filter((entry) => entry.deletedAt === undefined)
      .toArray()
  }

  async softDeleteEntry(id: string, deletedAt: string): Promise<void> {
    await this.database.diaryEntries.update(id, { deletedAt, updatedAt: deletedAt })
  }
}

function compareDiaryEntries(left: DiaryEntry, right: DiaryEntry): number {
  const sortOrderDifference = left.sortOrder - right.sortOrder

  if (Number.isFinite(sortOrderDifference) && sortOrderDifference !== 0) {
    return sortOrderDifference
  }

  const createdAtDifference = left.createdAt.localeCompare(right.createdAt)
  return createdAtDifference !== 0 ? createdAtDifference : left.id.localeCompare(right.id)
}

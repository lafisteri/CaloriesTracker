import type { Nutrition } from '@/domain/nutrition/nutrition'

export type MealType = 'breakfast' | 'lunch' | 'dinner' | 'snack'
export type DiarySourceType = 'product' | 'recipe'

/**
 * Nutrition is a snapshot captured when the entry is added and must never be
 * recalculated automatically after a product or recipe version changes.
 */
export interface DiaryEntry extends Nutrition {
  id: string
  date: string
  mealType: MealType
  /** Persistent position within one date and meal section. */
  sortOrder: number
  sourceType: DiarySourceType
  sourceId: string
  sourceVersionId: string
  sourceName: string
  amount: number
  unit: string
  createdAt: string
  updatedAt: string
  deletedAt?: string
}

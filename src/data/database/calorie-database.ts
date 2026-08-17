import Dexie, { type Table } from 'dexie'

import type { DiaryEntry } from '@/domain/diary/diary-entry'
import type { WeeklyGoal } from '@/domain/goals/weekly-goal'
import type { Product } from '@/domain/products/product'
import type { ProductVersion } from '@/domain/products/product-version'
import type { Recipe } from '@/domain/recipes/recipe'
import type { RecipeVersion } from '@/domain/recipes/recipe-version'

export const DATABASE_NAME = 'calorie-tracker'

/** IndexedDB schema. UI code must access it only through repository implementations. */
export class CalorieDatabase extends Dexie {
  products!: Table<Product, string>
  productVersions!: Table<ProductVersion, string>
  recipes!: Table<Recipe, string>
  recipeVersions!: Table<RecipeVersion, string>
  diaryEntries!: Table<DiaryEntry, string>
  weeklyGoals!: Table<WeeklyGoal, string>

  constructor(name = DATABASE_NAME) {
    super(name)

    this.version(1).stores({
      products: '&id, name, barcode, currentVersionId, updatedAt, deletedAt',
      productVersions: '&id, productId, [productId+versionNumber], createdAt',
      recipes: '&id, name, currentVersionId, updatedAt, deletedAt',
      recipeVersions: '&id, recipeId, [recipeId+versionNumber], createdAt',
      diaryEntries: '&id, date, mealType, sourceType, sourceId, sourceVersionId, deletedAt',
      weeklyGoals: '&id, effectiveFrom, createdAt',
    })

    this.version(2).stores({
      products: '&id, name, &barcode, currentVersionId, updatedAt, deletedAt',
      productVersions: '&id, productId, &[productId+versionNumber], createdAt',
      recipes: '&id, name, currentVersionId, updatedAt, deletedAt',
      recipeVersions: '&id, recipeId, [recipeId+versionNumber], createdAt',
      diaryEntries: '&id, date, mealType, sourceType, sourceId, sourceVersionId, deletedAt',
      weeklyGoals: '&id, effectiveFrom, createdAt',
    })

    this.version(3).stores({
      products: '&id, name, &barcode, currentVersionId, updatedAt, deletedAt',
      productVersions: '&id, productId, &[productId+versionNumber], createdAt',
      recipes: '&id, name, currentVersionId, updatedAt, deletedAt',
      recipeVersions: '&id, recipeId, [recipeId+versionNumber], createdAt',
      diaryEntries: '&id, date, mealType, sourceType, sourceId, sourceVersionId, createdAt, updatedAt, deletedAt',
      weeklyGoals: '&id, effectiveFrom, createdAt',
    })

    this.version(4).stores({
      products: '&id, name, &barcode, currentVersionId, updatedAt, deletedAt',
      productVersions: '&id, productId, &[productId+versionNumber], createdAt',
      recipes: '&id, name, currentVersionId, updatedAt, deletedAt',
      recipeVersions: '&id, recipeId, &[recipeId+versionNumber], createdAt',
      diaryEntries: '&id, date, mealType, sortOrder, [date+mealType+sortOrder], sourceType, sourceId, sourceVersionId, createdAt, updatedAt, deletedAt',
      weeklyGoals: '&id, effectiveFrom, createdAt',
    }).upgrade(async (transaction) => {
      const diaryEntries = transaction.table('diaryEntries') as Table<DiaryEntry, string>
      const entries = await diaryEntries.toArray()
      const nextOrderByMeal = new Map<string, number>()

      entries
        .sort(compareEntriesForMigration)
        .forEach((entry) => {
          const mealKey = `${entry.date}:${entry.mealType}`
          const nextSortOrder = nextOrderByMeal.get(mealKey) ?? 0
          entry.sortOrder = nextSortOrder
          nextOrderByMeal.set(mealKey, nextSortOrder + 100)
        })

      await diaryEntries.bulkPut(entries)
    })
  }
}

export const appDatabase = new CalorieDatabase()

export async function initializeLocalDatabase(database = appDatabase): Promise<void> {
  await database.open()
}

function compareEntriesForMigration(left: DiaryEntry, right: DiaryEntry): number {
  const dateDifference = left.date.localeCompare(right.date)

  if (dateDifference !== 0) {
    return dateDifference
  }

  const mealDifference = left.mealType.localeCompare(right.mealType)

  if (mealDifference !== 0) {
    return mealDifference
  }

  const createdAtDifference = left.createdAt.localeCompare(right.createdAt)
  return createdAtDifference !== 0 ? createdAtDifference : left.id.localeCompare(right.id)
}

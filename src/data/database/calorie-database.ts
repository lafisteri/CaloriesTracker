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
  }
}

export const appDatabase = new CalorieDatabase()

export async function initializeLocalDatabase(database = appDatabase): Promise<void> {
  await database.open()
}

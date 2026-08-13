import { initializeLocalDatabase } from '@/data/database/calorie-database'
import type { DiaryRepository } from '@/domain/repositories/diary-repository'
import type { GoalRepository } from '@/domain/repositories/goal-repository'
import type { ProductRepository } from '@/domain/repositories/product-repository'
import type { RecipeRepository } from '@/domain/repositories/recipe-repository'

import { DexieDiaryRepository } from './dexie-diary-repository'
import { DexieGoalRepository } from './dexie-goal-repository'
import { DexieProductRepository } from './dexie-product-repository'
import { DexieRecipeRepository } from './dexie-recipe-repository'

/** The application only depends on these repository ports, not on Dexie tables. */
export interface RepositoryRegistry {
  products: ProductRepository
  recipes: RecipeRepository
  diary: DiaryRepository
  goals: GoalRepository
}

/** Composition root for local data access. This is the future sync-layer seam. */
export const repositories: RepositoryRegistry = {
  products: new DexieProductRepository(),
  recipes: new DexieRecipeRepository(),
  diary: new DexieDiaryRepository(),
  goals: new DexieGoalRepository(),
}

/** Opens the local repository infrastructure before the UI is mounted. */
export async function initializeRepositories(): Promise<void> {
  await initializeLocalDatabase()
}

import { DexieDiaryRepository } from './dexie-diary-repository'
import { DexieGoalRepository } from './dexie-goal-repository'
import { DexieProductRepository } from './dexie-product-repository'
import { DexieRecipeRepository } from './dexie-recipe-repository'

/** Composition root for local data access. This is the future sync-layer seam. */
export const repositories = {
  products: new DexieProductRepository(),
  recipes: new DexieRecipeRepository(),
  diary: new DexieDiaryRepository(),
  goals: new DexieGoalRepository(),
}

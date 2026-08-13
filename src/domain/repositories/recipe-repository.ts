import type { Recipe } from '@/domain/recipes/recipe'
import type { RecipeVersion } from '@/domain/recipes/recipe-version'

export interface RecipeRepository {
  save(recipe: Recipe): Promise<void>
  getById(id: string): Promise<Recipe | undefined>
  getActive(): Promise<Recipe[]>
  saveVersion(version: RecipeVersion): Promise<void>
  getVersions(recipeId: string): Promise<RecipeVersion[]>
  getVersionById(id: string): Promise<RecipeVersion | undefined>
}

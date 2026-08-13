import { appDatabase, type CalorieDatabase } from '@/data/database/calorie-database'
import type { Recipe } from '@/domain/recipes/recipe'
import type { RecipeVersion } from '@/domain/recipes/recipe-version'
import type { RecipeRepository } from '@/domain/repositories/recipe-repository'

export class DexieRecipeRepository implements RecipeRepository {
  constructor(private readonly database: CalorieDatabase = appDatabase) {}

  async save(recipe: Recipe): Promise<void> {
    await this.database.recipes.put(recipe)
  }

  getById(id: string): Promise<Recipe | undefined> {
    return this.database.recipes.get(id)
  }

  async getActive(): Promise<Recipe[]> {
    return this.database.recipes.filter((recipe) => recipe.deletedAt === undefined).sortBy('name')
  }

  async saveVersion(version: RecipeVersion): Promise<void> {
    await this.database.recipeVersions.put(version)
  }

  getVersions(recipeId: string): Promise<RecipeVersion[]> {
    return this.database.recipeVersions.where('recipeId').equals(recipeId).sortBy('versionNumber')
  }

  getVersionById(id: string): Promise<RecipeVersion | undefined> {
    return this.database.recipeVersions.get(id)
  }
}

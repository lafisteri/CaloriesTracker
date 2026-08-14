import { appDatabase, type CalorieDatabase } from '@/data/database/calorie-database'
import type { Recipe } from '@/domain/recipes/recipe'
import type { RecipeVersion } from '@/domain/recipes/recipe-version'
import type { RecipeRepository } from '@/domain/repositories/recipe-repository'

export class DexieRecipeRepository implements RecipeRepository {
  constructor(private readonly database: CalorieDatabase = appDatabase) {}

  async create(recipe: Recipe, initialVersion: RecipeVersion): Promise<void> {
    await this.database.transaction('rw', this.database.recipes, this.database.recipeVersions, async () => {
      await this.database.recipeVersions.add(initialVersion)
      await this.database.recipes.add(recipe)
    })
  }

  async save(recipe: Recipe): Promise<void> {
    await this.database.recipes.put(recipe)
  }

  getById(id: string): Promise<Recipe | undefined> {
    return this.database.recipes.get(id)
  }

  async getActive(): Promise<Recipe[]> {
    return this.database.recipes.filter((recipe) => recipe.deletedAt === undefined).sortBy('name')
  }

  async saveVersionAndUpdateRecipe(recipe: Recipe, version: RecipeVersion): Promise<void> {
    await this.database.transaction('rw', this.database.recipes, this.database.recipeVersions, async () => {
      await this.database.recipeVersions.add(version)
      await this.database.recipes.put(recipe)
    })
  }

  getVersions(recipeId: string): Promise<RecipeVersion[]> {
    return this.database.recipeVersions.where('recipeId').equals(recipeId).sortBy('versionNumber')
  }

  getVersionById(id: string): Promise<RecipeVersion | undefined> {
    return this.database.recipeVersions.get(id)
  }

  async softDelete(id: string, deletedAt: string): Promise<void> {
    await this.database.recipes.update(id, { deletedAt, updatedAt: deletedAt })
  }
}

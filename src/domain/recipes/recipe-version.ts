import type { RecipeIngredient } from './recipe-ingredient'

export interface RecipeVersion {
  id: string
  recipeId: string
  versionNumber: number
  ingredients: RecipeIngredient[]
  totalCalories: number
  totalProtein: number
  totalFat: number
  totalCarbs: number
  cookedWeight?: number
  servingsCount?: number
  createdAt: string
}

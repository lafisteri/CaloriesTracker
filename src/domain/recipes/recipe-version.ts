import type { Nutrition } from '@/domain/nutrition/nutrition'

import type { RecipeIngredient } from './recipe-ingredient'

export interface RecipeVersion extends Nutrition {
  id: string
  recipeId: string
  versionNumber: number
  ingredients: RecipeIngredient[]
  cookedWeight?: number
  servingsCount?: number
  createdAt: string
}

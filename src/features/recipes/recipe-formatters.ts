import type { Nutrition } from '@/domain/nutrition/nutrition'
import { recipeCalculator } from '@/domain/recipes/recipe-calculator'
import type { RecipeVersion } from '@/domain/recipes/recipe-version'

export function formatRecipeNumber(value: number): string {
  return Number.isFinite(value) ? new Intl.NumberFormat('ru-RU', { maximumFractionDigits: 1 }).format(value) : '—'
}

export function formatRecipeNutrition(nutrition: Nutrition): string {
  return `${formatRecipeNumber(nutrition.calories)} ккал · Б ${formatRecipeNumber(nutrition.protein)} · Ж ${formatRecipeNumber(nutrition.fat)} · У ${formatRecipeNumber(nutrition.carbs)}`
}

export function getRecipePrimaryNutrition(version: RecipeVersion): string {
  const total = toNutrition(version)

  try {
    if (version.cookedWeight !== undefined) {
      return `${formatRecipeNumber(recipeCalculator.calculatePer100g(total, version.cookedWeight).calories)} ккал / 100 г`
    }

    if (version.servingsCount !== undefined) {
      return `${formatRecipeNumber(recipeCalculator.calculatePerServing(total, version.servingsCount).calories)} ккал / 1 шт`
    }
  } catch {
    return 'КБЖУ недоступно'
  }

  return 'КБЖУ недоступно'
}

export function toNutrition(version: RecipeVersion): Nutrition {
  return {
    calories: version.totalCalories,
    protein: version.totalProtein,
    fat: version.totalFat,
    carbs: version.totalCarbs,
  }
}

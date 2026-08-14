import type { Nutrition } from '@/domain/nutrition/nutrition'
import { recipeCalculator } from '@/domain/recipes/recipe-calculator'
import type { RecipeVersion } from '@/domain/recipes/recipe-version'

export function formatRecipeNumber(value: number): string {
  return Number.isFinite(value) ? new Intl.NumberFormat('ru-RU', { maximumFractionDigits: 1 }).format(value) : '—'
}

export function formatRecipeNutrition(nutrition: Nutrition): string {
  return `${formatRecipeNumber(nutrition.calories)} ккал · ${formatRecipeMacros(nutrition)}`
}

export function formatRecipeMacros(nutrition: Pick<Nutrition, 'protein' | 'fat' | 'carbs'>): string {
  return `Б ${formatRecipeNumber(nutrition.protein)} · Ж ${formatRecipeNumber(nutrition.fat)} · У ${formatRecipeNumber(nutrition.carbs)}`
}

export function getRecipePrimaryNutrition(version: RecipeVersion): string {
  const primaryNutrition = getRecipePrimaryNutritionValues(version)

  return primaryNutrition === undefined
    ? 'КБЖУ недоступно'
    : `${formatRecipeNumber(primaryNutrition.nutrition.calories)} ккал / ${primaryNutrition.unitLabel}`
}

export function getRecipePrimaryMacros(version: RecipeVersion): string {
  const primaryNutrition = getRecipePrimaryNutritionValues(version)

  return primaryNutrition === undefined ? 'КБЖУ недоступно' : formatRecipeMacros(primaryNutrition.nutrition)
}

export function toNutrition(version: RecipeVersion): Nutrition {
  return {
    calories: version.totalCalories,
    protein: version.totalProtein,
    fat: version.totalFat,
    carbs: version.totalCarbs,
  }
}

function getRecipePrimaryNutritionValues(version: RecipeVersion): { nutrition: Nutrition; unitLabel: string } | undefined {
  const total = toNutrition(version)

  try {
    if (version.cookedWeight !== undefined) {
      return { nutrition: recipeCalculator.calculatePer100g(total, version.cookedWeight), unitLabel: '100 г' }
    }

    if (version.servingsCount !== undefined) {
      return { nutrition: recipeCalculator.calculatePerServing(total, version.servingsCount), unitLabel: '1 шт' }
    }
  } catch {
    return undefined
  }

  return undefined
}

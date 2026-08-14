import type { Nutrition } from '@/domain/nutrition/nutrition'

/** Performs recipe-level aggregation after ingredient nutrition has been resolved. */
export class RecipeCalculator {
  calculateTotalNutrition(ingredients: readonly Nutrition[]): Nutrition {
    return ingredients.reduce<Nutrition>((total, ingredient) => ({
      calories: total.calories + ingredient.calories,
      protein: total.protein + ingredient.protein,
      fat: total.fat + ingredient.fat,
      carbs: total.carbs + ingredient.carbs,
    }), emptyNutrition())
  }

  calculatePer100g(total: Nutrition, cookedWeight: number): Nutrition {
    return this.scale(total, 100 / assertPositiveFinite(cookedWeight, 'Cooked weight'))
  }

  calculatePerServing(total: Nutrition, servingsCount: number): Nutrition {
    return this.scale(total, 1 / assertPositiveFinite(servingsCount, 'Servings count'))
  }

  scale(nutrition: Nutrition, factor: number): Nutrition {
    return {
      calories: nutrition.calories * factor,
      protein: nutrition.protein * factor,
      fat: nutrition.fat * factor,
      carbs: nutrition.carbs * factor,
    }
  }
}

export const recipeCalculator = new RecipeCalculator()

function emptyNutrition(): Nutrition {
  return { calories: 0, protein: 0, fat: 0, carbs: 0 }
}

function assertPositiveFinite(value: number, label: string): number {
  if (!Number.isFinite(value) || value <= 0) {
    throw new Error(`${label} must be a positive finite number.`)
  }

  return value
}

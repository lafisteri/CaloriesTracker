import type { Nutrition } from './nutrition'
import type { ProductVersion } from '@/domain/products/product-version'

/** Calculates nutrition from an amount already normalized to a product's base unit. */
export class NutritionCalculator {
  calculateForProduct(productVersion: ProductVersion, normalizedAmount: number): Nutrition {
    return this.calculate(productVersion, productVersion.baseAmount, normalizedAmount)
  }

  calculate(nutrition: Nutrition, baseAmount: number, normalizedAmount: number): Nutrition {
    if (!Number.isFinite(baseAmount) || baseAmount <= 0) {
      throw new Error('Base amount must be a positive finite number.')
    }

    if (!Number.isFinite(normalizedAmount) || normalizedAmount < 0) {
      throw new Error('Normalized amount must be a non-negative finite number.')
    }

    const factor = normalizedAmount / baseAmount

    return {
      calories: nutrition.calories * factor,
      protein: nutrition.protein * factor,
      fat: nutrition.fat * factor,
      carbs: nutrition.carbs * factor,
    }
  }
}

export const nutritionCalculator = new NutritionCalculator()

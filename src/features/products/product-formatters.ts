import type { Nutrition } from '@/domain/nutrition/nutrition'
import type { ProductBaseUnit, ProductVersion } from '@/domain/products/product-version'

const unitLabels: Record<ProductBaseUnit, string> = {
  g: 'г',
  ml: 'мл',
  piece: 'шт',
  serving: 'порцию',
}

export function formatNumber(value: number): string {
  return new Intl.NumberFormat('ru-RU', { maximumFractionDigits: 1 }).format(value)
}

export function formatBaseAmount(version: Pick<ProductVersion, 'baseUnitType' | 'baseAmount'>): string {
  return `${formatNumber(version.baseAmount)} ${unitLabels[version.baseUnitType]}`
}

export function formatNutrition(nutrition: Nutrition): string {
  return `${formatNumber(nutrition.calories)} ккал · Б ${formatNumber(nutrition.protein)} · Ж ${formatNumber(nutrition.fat)} · У ${formatNumber(nutrition.carbs)}`
}
